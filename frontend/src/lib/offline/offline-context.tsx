'use client';

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { mutate as globalMutate } from 'swr';
import { api, ApiError } from '@/lib/api';
import type { Transaction } from '@/lib/types';
import {
  allOps,
  deleteOp,
  getOp,
  isLocalId,
  newId,
  putOp,
  type OutboxOp,
} from './outbox';

/** SWR keys that should refresh once queued work reaches the server. */
function shouldRevalidate(key: unknown): boolean {
  if (typeof key !== 'string') return false;
  return (
    key.startsWith('/transactions') ||
    key.startsWith('/dashboard') ||
    key.startsWith('/accounts') ||
    key.startsWith('/budgets') ||
    key.startsWith('/analytics')
  );
}

/** A fetch/network failure (offline) vs. a real server rejection (ApiError). */
function isNetworkError(err: unknown): boolean {
  return !(err instanceof ApiError);
}

interface OfflineContextValue {
  online: boolean;
  syncing: boolean;
  /** Briefly true right after a successful drain — drives the "synced" flourish. */
  justSynced: boolean;
  lastSyncedAt: number | null;
  ops: OutboxOp[];
  pendingCount: number;
  errorCount: number;
  /** Optimistic new transactions (create/transfer) not yet on the server. */
  pendingCreates: Transaction[];
  /** targetId → optimistic edit, for server transactions edited while offline. */
  pendingPatches: Map<string, Transaction>;
  /** Server transaction ids deleted while offline. */
  deletedIds: Set<string>;
  saveTransaction: (body: Record<string, unknown>, optimistic: Transaction) => Promise<{ queued: boolean }>;
  saveTransfer: (body: Record<string, unknown>, optimistic: Transaction) => Promise<{ queued: boolean }>;
  updateTransaction: (
    id: string,
    body: Record<string, unknown>,
    optimistic: Transaction,
  ) => Promise<{ queued: boolean }>;
  deleteTransaction: (id: string) => Promise<{ queued: boolean }>;
  flush: () => Promise<void>;
  retry: (id: string) => Promise<void>;
  discard: (id: string) => Promise<void>;
}

const OfflineContext = createContext<OfflineContextValue | null>(null);

export function OfflineProvider({ children }: { children: ReactNode }) {
  const [online, setOnline] = useState(true);
  const [ops, setOps] = useState<OutboxOp[]>([]);
  const [syncing, setSyncing] = useState(false);
  const [justSynced, setJustSynced] = useState(false);
  const [lastSyncedAt, setLastSyncedAt] = useState<number | null>(null);
  const flushing = useRef(false);
  const syncedTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const refresh = useCallback(async () => {
    setOps(await allOps());
  }, []);

  // Initial hydrate + connectivity wiring.
  useEffect(() => {
    setOnline(navigator.onLine);
    void refresh();
    const goOnline = () => {
      setOnline(true);
      void flush();
    };
    const goOffline = () => setOnline(false);
    const onFocus = () => {
      if (navigator.onLine) void flush();
    };
    window.addEventListener('online', goOnline);
    window.addEventListener('offline', goOffline);
    window.addEventListener('focus', onFocus);
    // Safety-net retry while anything is queued.
    const interval = setInterval(() => {
      if (navigator.onLine) void flush();
    }, 20_000);
    return () => {
      window.removeEventListener('online', goOnline);
      window.removeEventListener('offline', goOffline);
      window.removeEventListener('focus', onFocus);
      clearInterval(interval);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const markSynced = useCallback(() => {
    setLastSyncedAt(Date.now());
    setJustSynced(true);
    if (syncedTimer.current) clearTimeout(syncedTimer.current);
    syncedTimer.current = setTimeout(() => setJustSynced(false), 2600);
  }, []);

  async function sendOp(op: OutboxOp): Promise<void> {
    switch (op.kind) {
      case 'create':
      case 'transfer':
        await api.post('/transactions', op.payload);
        return;
      case 'update':
        await api.put(`/transactions/${op.targetId}`, op.payload);
        return;
      case 'delete':
        await api.del(`/transactions/${op.targetId}`);
        return;
    }
  }

  const flush = useCallback(async () => {
    if (flushing.current || !navigator.onLine) return;
    const queue = (await allOps()).filter((o) => o.status !== 'error');
    if (queue.length === 0) return;

    flushing.current = true;
    setSyncing(true);
    let anySynced = false;
    try {
      for (const op of queue) {
        if (!navigator.onLine) break; // dropped offline mid-drain — stop cleanly
        await putOp({ ...op, status: 'syncing' });
        setOps(await allOps());
        try {
          await sendOp(op);
          await deleteOp(op.id);
          anySynced = true;
        } catch (err) {
          if (isNetworkError(err)) {
            // Connection lost — requeue as pending and stop; we'll retry later.
            await putOp({ ...op, status: 'pending' });
            break;
          }
          // Server rejected it (validation/business rule) — park as error for the user.
          await putOp({
            ...op,
            status: 'error',
            attempts: op.attempts + 1,
            error: err instanceof ApiError ? err.message : 'Failed to sync',
          });
        }
        setOps(await allOps());
      }
    } finally {
      flushing.current = false;
      setSyncing(false);
      await refresh();
      if (anySynced) {
        markSynced();
        void globalMutate(shouldRevalidate);
      }
    }
  }, [refresh, markSynced]);

  /** Enqueue a brand-new op, then (if online) kick a drain. */
  const enqueue = useCallback(
    async (op: OutboxOp) => {
      await putOp(op);
      await refresh();
      if (navigator.onLine) void flush();
    },
    [flush, refresh],
  );

  /**
   * Try a request immediately when online; fall back to the durable queue on a
   * network failure. Offline → queue straight away. Returns whether it queued.
   */
  const attemptOrQueue = useCallback(
    async (op: OutboxOp, direct: () => Promise<unknown>): Promise<{ queued: boolean }> => {
      if (navigator.onLine) {
        try {
          await direct();
          void globalMutate(shouldRevalidate);
          return { queued: false };
        } catch (err) {
          if (!isNetworkError(err)) throw err; // real server error → let caller surface it
        }
      }
      await enqueue(op);
      return { queued: true };
    },
    [enqueue],
  );

  const saveTransaction = useCallback(
    (body: Record<string, unknown>, optimistic: Transaction) => {
      const id = optimistic.id;
      return attemptOrQueue(
        { id, kind: 'create', payload: body, optimistic, status: 'pending', attempts: 0, createdAt: Date.now() },
        () => api.post('/transactions', body),
      );
    },
    [attemptOrQueue],
  );

  const saveTransfer = useCallback(
    (body: Record<string, unknown>, optimistic: Transaction) => {
      const id = optimistic.id;
      return attemptOrQueue(
        { id, kind: 'transfer', payload: body, optimistic, status: 'pending', attempts: 0, createdAt: Date.now() },
        () => api.post('/transactions', body),
      );
    },
    [attemptOrQueue],
  );

  const updateTransaction = useCallback(
    async (id: string, body: Record<string, unknown>, optimistic: Transaction) => {
      // Editing a transaction that is itself still queued: rewrite that op in place.
      if (isLocalId(id)) {
        const existing = await getOp(id);
        if (existing) {
          await putOp({ ...existing, payload: body, optimistic: { ...optimistic, id }, status: 'pending', error: undefined });
          await refresh();
          if (navigator.onLine) void flush();
          return { queued: true };
        }
      }
      return attemptOrQueue(
        {
          id: newId(),
          kind: 'update',
          targetId: id,
          payload: body,
          optimistic: { ...optimistic, id },
          status: 'pending',
          attempts: 0,
          createdAt: Date.now(),
        },
        () => api.put(`/transactions/${id}`, body),
      );
    },
    [attemptOrQueue, flush, refresh],
  );

  const deleteTransaction = useCallback(
    async (id: string) => {
      // Deleting a still-queued create: just drop it from the outbox.
      if (isLocalId(id)) {
        await deleteOp(id);
        await refresh();
        return { queued: true };
      }
      return attemptOrQueue(
        { id: newId(), kind: 'delete', targetId: id, status: 'pending', attempts: 0, createdAt: Date.now() },
        () => api.del(`/transactions/${id}`),
      );
    },
    [attemptOrQueue, refresh],
  );

  const retry = useCallback(
    async (id: string) => {
      const op = await getOp(id);
      if (!op) return;
      await putOp({ ...op, status: 'pending', error: undefined });
      await refresh();
      void flush();
    },
    [flush, refresh],
  );

  const discard = useCallback(
    async (id: string) => {
      await deleteOp(id);
      await refresh();
    },
    [refresh],
  );

  const { pendingCreates, pendingPatches, deletedIds } = useMemo(() => {
    const creates: Transaction[] = [];
    const patches = new Map<string, Transaction>();
    const deleted = new Set<string>();
    for (const op of ops) {
      const status = op.status;
      if ((op.kind === 'create' || op.kind === 'transfer') && op.optimistic) {
        creates.push({ ...op.optimistic, pending: status });
      } else if (op.kind === 'update' && op.optimistic && op.targetId) {
        patches.set(op.targetId, { ...op.optimistic, pending: status });
      } else if (op.kind === 'delete' && op.targetId) {
        deleted.add(op.targetId);
      }
    }
    creates.sort((a, b) => b.date.localeCompare(a.date));
    return { pendingCreates: creates, pendingPatches: patches, deletedIds: deleted };
  }, [ops]);

  const pendingCount = ops.filter((o) => o.status !== 'error').length;
  const errorCount = ops.filter((o) => o.status === 'error').length;

  const value: OfflineContextValue = {
    online,
    syncing,
    justSynced,
    lastSyncedAt,
    ops,
    pendingCount,
    errorCount,
    pendingCreates,
    pendingPatches,
    deletedIds,
    saveTransaction,
    saveTransfer,
    updateTransaction,
    deleteTransaction,
    flush,
    retry,
    discard,
  };

  return <OfflineContext.Provider value={value}>{children}</OfflineContext.Provider>;
}

export function useOffline(): OfflineContextValue {
  const ctx = useContext(OfflineContext);
  if (!ctx) throw new Error('useOffline must be used within OfflineProvider');
  return ctx;
}
