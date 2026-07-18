'use client';

import { useEffect, useMemo, useState } from 'react';
import useSWR from 'swr';
import { toast } from 'sonner';
import { Modal } from '@/components/ui/modal';
import { Button } from '@/components/ui/button';
import { Field, Input, Select, Textarea } from '@/components/ui/input';
import { ApiError } from '@/lib/api';
import { useOffline } from '@/lib/offline/offline-context';
import { newId } from '@/lib/offline/outbox';
import type { Account, Transaction } from '@/lib/types';

export function TransferModal({
  open,
  onClose,
  onSaved,
}: {
  open: boolean;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { data } = useSWR<{ items: Account[] }>(open ? '/accounts' : null);
  const { saveTransfer } = useOffline();
  const accounts = useMemo(
    () => data?.items.filter((a) => !a.archived) ?? [],
    [data?.items],
  );

  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [amount, setAmount] = useState('');
  const [note, setNote] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (open && accounts.length >= 1) {
      setFrom((f) => f || (accounts.find((a) => a.isDefault) ?? accounts[0]!).id);
      setTo((t) => t || accounts.find((a) => a.id !== (accounts[0]!.id))?.id || '');
    }
  }, [open, accounts]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (from === to) return toast.error('Choose two different accounts');
    const fromAccount = accounts.find((a) => a.id === from);
    const toAccount = accounts.find((a) => a.id === to);
    const today = new Date().toISOString().slice(0, 10);
    setSaving(true);
    const payload = {
      kind: 'TRANSFER',
      amount: Number(amount),
      currency: fromAccount?.currency ?? 'ETB',
      accountId: from,
      transferAccountId: to,
      date: today,
      note: note || undefined,
    };
    const optimistic: Transaction = {
      id: newId(),
      kind: 'TRANSFER',
      amount: Number(amount).toFixed(2),
      currency: fromAccount?.currency ?? 'ETB',
      date: `${today}T12:00:00.000Z`,
      accountId: from,
      account: fromAccount ? { id: fromAccount.id, name: fromAccount.name, type: fromAccount.type } : undefined,
      transferAccountId: to,
      transferAccount: toAccount ? { id: toAccount.id, name: toAccount.name } : null,
      categoryId: null,
      category: null,
      note: note || null,
      tags: [],
    };
    try {
      const { queued } = await saveTransfer(payload, optimistic);
      toast.success(queued ? 'Transfer saved offline — will sync later' : 'Transfer recorded');
      onSaved();
      onClose();
      setAmount('');
      setNote('');
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to transfer');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal open={open} onClose={onClose} title="Transfer between accounts">
      <form onSubmit={submit} className="space-y-4">
        <div className="grid grid-cols-2 gap-3">
          <Field label="From">
            <Select value={from} onChange={(e) => setFrom(e.target.value)}>
              {accounts.map((a) => (
                <option key={a.id} value={a.id}>{a.name}</option>
              ))}
            </Select>
          </Field>
          <Field label="To">
            <Select value={to} onChange={(e) => setTo(e.target.value)}>
              {accounts.map((a) => (
                <option key={a.id} value={a.id}>{a.name}</option>
              ))}
            </Select>
          </Field>
        </div>
        <Field label="Amount">
          <Input
            type="number"
            step="0.01"
            min="0"
            required
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0.00"
          />
        </Field>
        <Field label="Note">
          <Textarea value={note} onChange={(e) => setNote(e.target.value)} rows={2} placeholder="Optional…" />
        </Field>
        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={onClose}>Cancel</Button>
          <Button type="submit" loading={saving}>Transfer</Button>
        </div>
      </form>
    </Modal>
  );
}
