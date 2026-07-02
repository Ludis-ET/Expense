'use client';

import { useEffect, useState } from 'react';
import useSWR from 'swr';
import { toast } from 'sonner';
import { Modal } from '@/components/ui/modal';
import { Button } from '@/components/ui/button';
import { Field, Input, Select, Textarea } from '@/components/ui/input';
import { api, ApiError } from '@/lib/api';
import type { Account } from '@/lib/types';

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
  const accounts = data?.items.filter((a) => !a.archived) ?? [];

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
    setSaving(true);
    try {
      await api.post('/transactions', {
        kind: 'TRANSFER',
        amount: Number(amount),
        accountId: from,
        transferAccountId: to,
        date: new Date().toISOString().slice(0, 10),
        note: note || undefined,
      });
      toast.success('Transfer recorded');
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
