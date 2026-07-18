// Durable offline queue for transaction mutations, backed by IndexedDB so
// queued work survives reloads and app restarts. The app drains this queue
// whenever it is online (see offline-context).
import type { Transaction } from '@/lib/types';

export type OutboxKind = 'create' | 'transfer' | 'update' | 'delete';
export type OutboxStatus = 'pending' | 'syncing' | 'error';

export interface OutboxOp {
  /** Client id. For create/transfer this doubles as the optimistic transaction id. */
  id: string;
  kind: OutboxKind;
  /** Request body (create/transfer/update) — undefined for delete. */
  payload?: Record<string, unknown>;
  /** Server transaction id the op acts on (update/delete). */
  targetId?: string;
  /** A Transaction-shaped preview so the UI can render the change before it syncs. */
  optimistic?: Transaction;
  status: OutboxStatus;
  error?: string;
  attempts: number;
  createdAt: number;
}

const DB_NAME = 'santim-offline';
const STORE = 'outbox';
const VERSION = 1;

function hasIDB(): boolean {
  return typeof window !== 'undefined' && 'indexedDB' in window;
}

let dbPromise: Promise<IDBDatabase> | null = null;

function openDB(): Promise<IDBDatabase> {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(STORE)) {
        db.createObjectStore(STORE, { keyPath: 'id' });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  return dbPromise;
}

function run<T>(mode: IDBTransactionMode, fn: (store: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  return openDB().then(
    (db) =>
      new Promise<T>((resolve, reject) => {
        const tx = db.transaction(STORE, mode);
        const req = fn(tx.objectStore(STORE));
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
      }),
  );
}

export async function allOps(): Promise<OutboxOp[]> {
  if (!hasIDB()) return [];
  const ops = await run<OutboxOp[]>('readonly', (s) => s.getAll() as IDBRequest<OutboxOp[]>);
  return ops.sort((a, b) => a.createdAt - b.createdAt);
}

export async function putOp(op: OutboxOp): Promise<void> {
  if (!hasIDB()) return;
  await run('readwrite', (s) => s.put(op));
}

export async function getOp(id: string): Promise<OutboxOp | undefined> {
  if (!hasIDB()) return undefined;
  return run<OutboxOp | undefined>('readonly', (s) => s.get(id) as IDBRequest<OutboxOp | undefined>);
}

export async function deleteOp(id: string): Promise<void> {
  if (!hasIDB()) return;
  await run('readwrite', (s) => s.delete(id));
}

export function newId(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) return `local:${crypto.randomUUID()}`;
  return `local:${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

/** A locally-created transaction that has not synced yet carries a `local:` id. */
export function isLocalId(id: string | null | undefined): boolean {
  return typeof id === 'string' && id.startsWith('local:');
}
