'use client';

import { useEffect, useMemo, useState } from 'react';
import useSWR from 'swr';
import { toast } from 'sonner';
import { Modal } from '@/components/ui/modal';
import { Button } from '@/components/ui/button';
import { Field, Input, Select, Textarea, DateInput } from '@/components/ui/input';
import { ApiError } from '@/lib/api';
import { useOffline } from '@/lib/offline/offline-context';
import { newId } from '@/lib/offline/outbox';
import type { Account, Transaction } from '@/lib/types';
import { todayInputValue } from '@/lib/date-range';

export function TransferModal({
  open,
  onClose,
  onSaved,
}: {
  open: boolean;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { data, isLoading: accountsLoading } = useSWR<{ items: Account[] }>(open ? '/accounts' : null);
  const { saveTransfer } = useOffline();
  const accounts = useMemo(
    () => data?.items.filter((a) => !a.archived) ?? [],
    [data?.items],
  );

  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [amount, setAmount] = useState('');
  /** What actually arrived, when the two wallets hold different currencies. */
  const [received, setReceived] = useState('');
  const [note, setNote] = useState('');
  const [date, setDate] = useState(() => todayInputValue());
  const [saving, setSaving] = useState(false);

  const fromAccount = accounts.find((a) => a.id === from);
  const toAccount = accounts.find((a) => a.id === to);
  /**
   * Crossing a currency needs both figures. Crediting the destination the source
   * amount - which is what used to happen - turns 100 USD into 100 birr and
   * quietly destroys the difference.
   */
  const crossCurrency =
    !!fromAccount && !!toAccount && fromAccount.currency !== toAccount.currency;
  const impliedRate =
    crossCurrency && Number(amount) > 0 && Number(received) > 0
      ? Number(received) / Number(amount)
      : null;

  useEffect(() => {
    if (open && accounts.length >= 1) {
      setFrom((f) => f || (accounts.find((a) => a.isDefault) ?? accounts[0]!).id);
      setTo((t) => t || accounts.find((a) => a.id !== (accounts[0]!.id))?.id || '');
    }
  }, [open, accounts]);

  // Same-currency transfers have nothing to ask about.
  useEffect(() => {
    if (!crossCurrency && received) setReceived('');
  }, [crossCurrency, received]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (from === to) return toast.error('Choose two different wallets');
    if (crossCurrency && !(Number(received) > 0)) {
      return toast.error(`Say how much ${toAccount!.currency} arrived.`);
    }
    const txDate = date || todayInputValue();
    setSaving(true);
    const payload = {
      kind: 'TRANSFER',
      amount: Number(amount),
      currency: fromAccount?.currency ?? 'ETB',
      accountId: from,
      transferAccountId: to,
      ...(crossCurrency ? { transferAmount: Number(received) } : {}),
      date: txDate,
      note: note || undefined,
    };
    const optimistic: Transaction = {
      id: newId(),
      kind: 'TRANSFER',
      amount: Number(amount).toFixed(2),
      currency: fromAccount?.currency ?? 'ETB',
      date: `${txDate}T12:00:00.000Z`,
      accountId: from,
      account: fromAccount ? { id: fromAccount.id, name: fromAccount.name, type: fromAccount.type } : undefined,
      transferAccountId: to,
      transferAccount: toAccount ? { id: toAccount.id, name: toAccount.name } : null,
      transferAmount: crossCurrency ? Number(received).toFixed(2) : null,
      categoryId: null,
      category: null,
      note: note || null,
      tags: [],
    };
    try {
      const { queued } = await saveTransfer(payload, optimistic);
      toast.success(queued ? 'Transfer saved offline - will sync later' : 'Transfer recorded');
      onSaved();
      onClose();
      setAmount('');
      setReceived('');
      setDate(todayInputValue());
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
            <Select value={from} onChange={(e) => setFrom(e.target.value)} loading={open && accountsLoading}>
              {accounts.map((a) => (
                <option key={a.id} value={a.id}>{a.name}</option>
              ))}
            </Select>
          </Field>
          <Field label="To">
            <Select value={to} onChange={(e) => setTo(e.target.value)} loading={open && accountsLoading}>
              {accounts.map((a) => (
                <option key={a.id} value={a.id}>{a.name}</option>
              ))}
            </Select>
          </Field>
        </div>
        <div className={crossCurrency ? 'grid grid-cols-2 gap-3' : ''}>
          <Field label={crossCurrency ? `Amount sent (${fromAccount!.currency})` : 'Amount'}>
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
          {crossCurrency && (
            <Field
              label={`Amount received (${toAccount!.currency})`}
              hint="what actually landed, after any conversion"
            >
              <Input
                type="number"
                step="0.01"
                min="0"
                required
                value={received}
                onChange={(e) => setReceived(e.target.value)}
                placeholder="0.00"
              />
            </Field>
          )}
        </div>

        {crossCurrency && (
          <p className="-mt-1 rounded-xl bg-surface-muted px-3 py-2 text-xs text-muted">
            {impliedRate
              ? `That is 1 ${fromAccount!.currency} = ${impliedRate.toFixed(4)} ${toAccount!.currency}. Santim records both figures, so neither wallet drifts.`
              : `These wallets hold different currencies, so Santim needs both figures - the ${toAccount!.currency} amount is what gets credited.`}
          </p>
        )}

        <Field label="Date">
          <DateInput value={date} onChange={(e) => setDate(e.target.value)} required maxToday />
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
