'use client';

import { useEffect, useState } from 'react';
import useSWR from 'swr';
import { toast } from 'sonner';
import { Plus, Trash2 } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Modal } from '@/components/ui/modal';
import { Button } from '@/components/ui/button';
import { Field, Input, Select } from '@/components/ui/input';
import { Spinner } from '@/components/ui/misc';
import { IconPicker, ColorPicker } from '@/components/finance/pickers';
import { financeIcon } from '@/components/finance/icons';
import { api, ApiError } from '@/lib/api';
import { useConfirm } from '@/components/ui/confirm-dialog';
import type { Category, CategoryKind } from '@/lib/types';

export function CategoryManager() {
  const confirm = useConfirm();
  const { data, mutate } = useSWR<{ items: Category[] }>('/categories');
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<Category | null>(null);
  const [reassignOpen, setReassignOpen] = useState(false);
  const [pendingDelete, setPendingDelete] = useState<Category | null>(null);
  const [reassignTargetId, setReassignTargetId] = useState('');

  const income = (data?.items ?? []).filter((c) => c.kind === 'INCOME' && !c.archived);
  const expense = (data?.items ?? []).filter((c) => c.kind === 'EXPENSE' && !c.archived);

  async function performDelete(categoryId: string, reassignTo?: string) {
    try {
      await api.del(`/categories/${categoryId}${reassignTo ? `?reassignTo=${reassignTo}` : ''}`);
      toast.success('Category deleted');
      void mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    }
  }

  async function remove(category: Category) {
    const used = category.transactionCount ?? 0;
    if (used > 0) {
      const sameKind = (data?.items ?? []).filter((c) => c.kind === category.kind && c.id !== category.id && !c.archived);
      if (sameKind.length === 0) return toast.error('Add another category first to move its transactions.');
      setPendingDelete(category);
      setReassignTargetId(sameKind[0]!.id);
      setReassignOpen(true);
      return;
    }
    const ok = await confirm({
      title: 'Delete category?',
      description: `Delete "${category.name}"? This cannot be undone.`,
      confirmLabel: 'Delete',
      tone: 'danger',
    });
    if (!ok) return;
    await performDelete(category.id);
  }

  const reassignOptions = pendingDelete
    ? (data?.items ?? []).filter((c) => c.kind === pendingDelete.kind && c.id !== pendingDelete.id && !c.archived)
    : [];

  function renderGroup(title: string, items: Category[]) {
    return (
      <div>
        <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted">{title}</p>
        <div className="flex flex-wrap gap-2">
          {items.map((c) => {
            const Icon = financeIcon(c.icon);
            return (
              <button
                key={c.id}
                onClick={() => { setEditing(c); setModalOpen(true); }}
                className="group inline-flex items-center gap-1.5 rounded-full border border-border px-3 py-1.5 text-sm transition-colors hover:bg-surface-muted"
              >
                <Icon className="h-3.5 w-3.5" style={{ color: c.color }} />
                {c.name}
                <Trash2
                  className="h-3 w-3 text-muted opacity-0 transition-opacity hover:text-danger group-hover:opacity-100"
                  onClick={(e) => { e.stopPropagation(); void remove(c); }}
                />
              </button>
            );
          })}
        </div>
      </div>
    );
  }

  return (
    <Card>
      <CardHeader>
        <div>
          <CardTitle>Categories</CardTitle>
          <CardDescription>Organize your income and spending. Click one to edit.</CardDescription>
        </div>
        <Button size="sm" variant="outline" onClick={() => { setEditing(null); setModalOpen(true); }}>
          <Plus className="h-4 w-4" /> Add
        </Button>
      </CardHeader>
      <CardContent className="space-y-5">
        {!data ? (
          <div className="flex justify-center py-6"><Spinner /></div>
        ) : (
          <>
            {renderGroup('Expense', expense)}
            {renderGroup('Income', income)}
          </>
        )}
      </CardContent>

      <CategoryModal open={modalOpen} editing={editing} onClose={() => setModalOpen(false)} onSaved={() => void mutate()} />

      <Modal
        open={reassignOpen}
        onClose={() => { setReassignOpen(false); setPendingDelete(null); }}
        title="Move transactions first"
      >
        {pendingDelete && (
          <div className="space-y-4">
            <p className="text-sm leading-relaxed text-muted">
              <span className="font-medium text-foreground">&quot;{pendingDelete.name}&quot;</span> has{' '}
              {pendingDelete.transactionCount} transaction{(pendingDelete.transactionCount ?? 0) === 1 ? '' : 's'}.
              Choose a category to move them to before deleting.
            </p>
            <Field label="Move transactions to">
              <Select value={reassignTargetId} onChange={(e) => setReassignTargetId(e.target.value)}>
                {reassignOptions.map((c) => (
                  <option key={c.id} value={c.id}>{c.name}</option>
                ))}
              </Select>
            </Field>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => { setReassignOpen(false); setPendingDelete(null); }}>
                Cancel
              </Button>
              <Button
                variant="danger"
                onClick={async () => {
                  await performDelete(pendingDelete.id, reassignTargetId);
                  setReassignOpen(false);
                  setPendingDelete(null);
                }}
              >
                Delete category
              </Button>
            </div>
          </div>
        )}
      </Modal>
    </Card>
  );
}

function CategoryModal({ open, editing, onClose, onSaved }: { open: boolean; editing: Category | null; onClose: () => void; onSaved: () => void }) {
  const [name, setName] = useState('');
  const [kind, setKind] = useState<CategoryKind>('EXPENSE');
  const [icon, setIcon] = useState('circle');
  const [color, setColor] = useState('#64748b');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open) return;
    setName(editing?.name ?? '');
    setKind(editing?.kind ?? 'EXPENSE');
    setIcon(editing?.icon ?? 'circle');
    setColor(editing?.color ?? '#64748b');
  }, [open, editing]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setSaving(true);
    try {
      if (editing) await api.put(`/categories/${editing.id}`, { name, icon, color });
      else await api.post('/categories', { name, kind, icon, color });
      toast.success(editing ? 'Category updated' : 'Category added');
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to save');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal open={open} onClose={onClose} title={editing ? 'Edit category' : 'New category'}>
      <form onSubmit={submit} className="space-y-4">
        <Field label="Name"><Input required value={name} onChange={(e) => setName(e.target.value)} placeholder="Coffee" /></Field>
        {!editing && (
          <Field label="Type">
            <Select value={kind} onChange={(e) => setKind(e.target.value as CategoryKind)}>
              <option value="EXPENSE">Expense</option>
              <option value="INCOME">Income</option>
            </Select>
          </Field>
        )}
        <Field label="Icon"><IconPicker value={icon} onChange={setIcon} /></Field>
        <Field label="Color"><ColorPicker value={color} onChange={setColor} /></Field>
        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={onClose}>Cancel</Button>
          <Button type="submit" loading={saving}>{editing ? 'Save' : 'Add category'}</Button>
        </div>
      </form>
    </Modal>
  );
}
