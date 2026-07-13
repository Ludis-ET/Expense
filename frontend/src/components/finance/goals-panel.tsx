'use client';

import { useEffect, useState } from 'react';
import useSWR from 'swr';
import { toast } from 'sonner';
import { Check, Plus, Target, Trash2, Repeat } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Modal } from '@/components/ui/modal';
import { Button } from '@/components/ui/button';
import { Field, Input, Textarea, DateInput } from '@/components/ui/input';
import { ProgressBar, Skeleton, EmptyState } from '@/components/ui/misc';
import { IconPicker, ColorPicker } from '@/components/finance/pickers';
import { financeIcon } from '@/components/finance/icons';
import { api, ApiError } from '@/lib/api';
import { formatDate } from '@/lib/format';
import { useMoney } from '@/lib/amount-visibility';
import { useConfirm } from '@/components/ui/confirm-dialog';
import type { SavingsGoal } from '@/lib/types';

export function GoalsPanel() {
  const confirm = useConfirm();
  const { money } = useMoney();
  const { data, mutate } = useSWR<{ items: SavingsGoal[] }>('/goals');
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<SavingsGoal | null>(null);
  const [contributing, setContributing] = useState<SavingsGoal | null>(null);

  async function remove(goal: SavingsGoal) {
    const ok = await confirm({
      title: 'Delete goal?',
      description: `Delete "${goal.name}" and its progress?`,
      confirmLabel: 'Delete',
      tone: 'danger',
    });
    if (!ok) return;
    try {
      await api.del(`/goals/${goal.id}`);
      toast.success('Goal deleted');
      void mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    }
  }

  return (
    <div>
      <div className="mb-4 flex justify-end">
        <Button size="sm" onClick={() => { setEditing(null); setFormOpen(true); }}>
          <Plus className="h-4 w-4" /> New goal
        </Button>
      </div>

      {!data ? (
        <div className="grid gap-4 sm:grid-cols-2">{Array.from({ length: 2 }).map((_, i) => <Skeleton key={i} className="h-44" />)}</div>
      ) : data.items.length === 0 ? (
        <EmptyState icon={<Target className="h-5 w-5" />} title="No goals yet" description="Save towards what matters." action={<Button onClick={() => { setEditing(null); setFormOpen(true); }}>Create a goal</Button>} />
      ) : (
        <div className="grid gap-4 sm:grid-cols-2">
          {data.items.map((g) => {
            const Icon = financeIcon(g.icon);
            const color = g.color ?? '#10b981';
            const achieved = !!g.achievedAt;
            return (
              <Card key={g.id}>
                <CardContent className="p-5">
                  <div className="flex items-start justify-between">
                    <span className="flex h-10 w-10 items-center justify-center rounded-lg" style={{ backgroundColor: `${color}22`, color }}>
                      <Icon className="h-5 w-5" />
                    </span>
                    <div className="flex gap-1">
                      <button onClick={() => { setEditing(g); setFormOpen(true); }} className="rounded-md px-2 py-1 text-xs text-muted hover:bg-surface-muted">Edit</button>
                      <button onClick={() => remove(g)} className="rounded-md p-1 text-muted hover:bg-surface-muted hover:text-danger" aria-label="Delete"><Trash2 className="h-3.5 w-3.5" /></button>
                    </div>
                  </div>
                  <p className="mt-3 flex items-center gap-2 font-semibold">
                    {g.name}
                    {achieved && <span className="inline-flex items-center gap-1 rounded-full bg-emerald-500/12 px-2 py-0.5 text-[10px] font-medium text-emerald-600 dark:text-emerald-400"><Check className="h-3 w-3" /> reached</span>}
                  </p>
                  <p className="mt-3 text-sm tabular-nums"><span className="font-bold">{money(g.saved)}</span><span className="text-muted"> of {money(g.targetAmount)}</span></p>
                  <div className="mt-2"><ProgressBar value={g.pct} tone="success" /></div>
                  <div className="mt-2 flex items-center justify-between text-xs text-muted">
                    <span>{g.pct}%</span>
                    {g.deadline && <span>by {formatDate(g.deadline)}</span>}
                  </div>
                  {g.monthlyNeeded && !achieved && <p className="mt-1 text-xs text-muted">Save {money(g.monthlyNeeded)}/mo to hit deadline.</p>}
                  {!achieved && g.autoSave.planCount > 0 && (
                    <div className="mt-2 flex flex-wrap items-center gap-1.5 rounded-lg bg-primary/5 px-2.5 py-1.5 text-xs">
                      <Repeat className="h-3 w-3 text-primary" />
                      <span className="font-medium text-primary">Auto-saving {money(g.autoSave.monthly)}/mo</span>
                      {g.autoSave.projectedDate && (
                        <span className={g.autoSave.onTrack === false ? 'text-amber-600 dark:text-amber-400' : 'text-muted'}>
                          · done ~{formatDate(g.autoSave.projectedDate)}
                          {g.autoSave.onTrack === false ? ' (after deadline)' : g.autoSave.onTrack === true ? ' ✓' : ''}
                        </span>
                      )}
                    </div>
                  )}
                  {!achieved && <Button variant="outline" size="sm" className="mt-3 w-full" onClick={() => setContributing(g)}>Add contribution</Button>}
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}

      <GoalForm open={formOpen} editing={editing} onClose={() => setFormOpen(false)} onSaved={() => void mutate()} />
      <ContributionModal goal={contributing} onClose={() => setContributing(null)} onSaved={() => void mutate()} />
    </div>
  );
}

function GoalForm({ open, editing, onClose, onSaved }: { open: boolean; editing: SavingsGoal | null; onClose: () => void; onSaved: () => void }) {
  const [name, setName] = useState('');
  const [targetAmount, setTargetAmount] = useState('');
  const [deadline, setDeadline] = useState('');
  const [note, setNote] = useState('');
  const [icon, setIcon] = useState('target');
  const [color, setColor] = useState('#10b981');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open) return;
    setName(editing?.name ?? '');
    setTargetAmount(editing ? String(Number(editing.targetAmount)) : '');
    setDeadline(editing?.deadline ? editing.deadline.slice(0, 10) : '');
    setNote(editing?.note ?? '');
    setIcon(editing?.icon ?? 'target');
    setColor(editing?.color ?? '#10b981');
  }, [open, editing]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setSaving(true);
    const payload = { name, targetAmount: Number(targetAmount), deadline: deadline || undefined, note: note || undefined, icon, color };
    try {
      if (editing) await api.put(`/goals/${editing.id}`, payload);
      else await api.post('/goals', payload);
      toast.success(editing ? 'Goal updated' : 'Goal created');
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal open={open} onClose={onClose} title={editing ? 'Edit goal' : 'New goal'}>
      <form onSubmit={submit} className="space-y-4">
        <Field label="Name"><Input required value={name} onChange={(e) => setName(e.target.value)} placeholder="Emergency Fund" /></Field>
        <div className="grid grid-cols-2 gap-3">
          <Field label="Target"><Input type="number" step="0.01" min="0" required value={targetAmount} onChange={(e) => setTargetAmount(e.target.value)} /></Field>
          <Field label="Deadline"><DateInput value={deadline} onChange={(e) => setDeadline(e.target.value)} /></Field>
        </div>
        <Field label="Icon"><IconPicker value={icon} onChange={setIcon} /></Field>
        <Field label="Color"><ColorPicker value={color} onChange={setColor} /></Field>
        <Field label="Note"><Textarea rows={2} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={onClose}>Cancel</Button>
          <Button type="submit" loading={saving}>{editing ? 'Save' : 'Create'}</Button>
        </div>
      </form>
    </Modal>
  );
}

function ContributionModal({ goal, onClose, onSaved }: { goal: SavingsGoal | null; onClose: () => void; onSaved: () => void }) {
  const [amount, setAmount] = useState('');
  const [note, setNote] = useState('');
  const [saving, setSaving] = useState(false);
  useEffect(() => { if (goal) { setAmount(''); setNote(''); } }, [goal]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!goal) return;
    setSaving(true);
    try {
      await api.post(`/goals/${goal.id}/contributions`, { amount: Number(amount), note: note || undefined });
      toast.success('Contribution added');
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal open={!!goal} onClose={onClose} title={`Add to ${goal?.name ?? ''}`}>
      <form onSubmit={submit} className="space-y-4">
        <Field label="Amount"><Input type="number" step="0.01" min="0" required autoFocus value={amount} onChange={(e) => setAmount(e.target.value)} /></Field>
        <Field label="Note"><Input value={note} onChange={(e) => setNote(e.target.value)} /></Field>
        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={onClose}>Cancel</Button>
          <Button type="submit" loading={saving}>Add</Button>
        </div>
      </form>
    </Modal>
  );
}
