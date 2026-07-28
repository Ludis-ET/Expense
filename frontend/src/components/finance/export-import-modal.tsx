'use client';

import { useCallback, useMemo, useRef, useState } from 'react';
import useSWR from 'swr';
import { toast } from 'sonner';
import {
  Download,
  Upload,
  CheckCircle2,
  XCircle,
  AlertCircle,
  Calendar,
  Loader2,
} from 'lucide-react';
import { Modal } from '@/components/ui/modal';
import { Button } from '@/components/ui/button';
import { Field, DateInput } from '@/components/ui/input';
import { api, ApiError } from '@/lib/api';
import { cn } from '@/lib/utils';
import type { Account, Category, Transaction, TransactionPage } from '@/lib/types';

type Tab = 'export' | 'import';
type DateRange = 'all' | 'this-month' | 'last-3' | 'custom';

const CSV_HEADERS = ['id', 'Date', 'Kind', 'Amount', 'Currency', 'Payee', 'Note', 'Category', 'Account', 'TransferAccount', 'Tags', 'RecurringRuleId'];

function escapeCell(v: string | number | null | undefined) {
  return `"${String(v ?? '').replace(/"/g, '""')}"`;
}

function txToCsvRow(t: Transaction): string {
  return [
    t.id,
    t.date.slice(0, 10),
    t.kind,
    t.amount,
    t.currency,
    t.payee ?? '',
    t.note ?? '',
    t.category?.name ?? '',
    t.account?.name ?? '',
    t.transferAccount?.name ?? '',
    t.tags.join('|'),
    t.recurringRuleId ?? '',
  ].map(escapeCell).join(',');
}

function dateRangeBounds(range: DateRange, custom: { from: string; to: string }) {
  const today = new Date();
  const pad = (n: number) => String(n).padStart(2, '0');
  const fmt = (d: Date) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

  if (range === 'all') return { from: '', to: '' };

  if (range === 'this-month') {
    const from = fmt(new Date(today.getFullYear(), today.getMonth(), 1));
    const to = fmt(new Date(today.getFullYear(), today.getMonth() + 1, 0));
    return { from, to };
  }

  if (range === 'last-3') {
    const d = new Date(today.getFullYear(), today.getMonth() - 2, 1);
    const from = fmt(d);
    const to = fmt(new Date(today.getFullYear(), today.getMonth() + 1, 0));
    return { from, to };
  }

  return { from: custom.from, to: custom.to };
}

/* ── Export Tab ─────────────────────────────────────────────── */
function ExportTab() {
  const [range, setRange] = useState<DateRange>('this-month');
  const [custom, setCustom] = useState({ from: '', to: '' });
  const [exporting, setExporting] = useState(false);
  const [progress, setProgress] = useState(0);
  const [done, setDone] = useState(false);

  async function doExport() {
    setExporting(true);
    setProgress(0);
    setDone(false);

    const { from, to } = dateRangeBounds(range, custom);
    const allRows: Transaction[] = [];
    let page = 1;
    let totalPages = 1;

    try {
      do {
        const params = new URLSearchParams({ page: String(page), pageSize: '200' });
        if (from) params.set('from', from);
        if (to) params.set('to', to);

        const res = await api.get<TransactionPage>(`/transactions?${params}`);
        allRows.push(...res.items);
        totalPages = Math.max(1, Math.ceil(res.total / res.pageSize));
        setProgress(Math.round((page / totalPages) * 90));
        page++;
      } while (page <= totalPages);

      if (allRows.length === 0) {
        toast.info('No transactions found for this period');
        setExporting(false);
        return;
      }

      const csv = [CSV_HEADERS.join(','), ...allRows.map(txToCsvRow)].join('\n');
      const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = from && to
        ? `transactions-${from}-to-${to}.csv`
        : `transactions-all-time.csv`;
      a.click();
      URL.revokeObjectURL(url);
      setProgress(100);
      setDone(true);
      toast.success(`Exported ${allRows.length} transactions`);
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Export failed');
    } finally {
      setExporting(false);
    }
  }

  const rangeOptions: { value: DateRange; label: string }[] = [
    { value: 'all', label: 'All time' },
    { value: 'this-month', label: 'This month' },
    { value: 'last-3', label: 'Last 3 months' },
    { value: 'custom', label: 'Custom range' },
  ];

  return (
    <div className="space-y-5">
      <div className="rounded-xl border border-border bg-surface-muted/30 p-4">
        <p className="flex items-center gap-2 text-sm font-medium mb-3">
          <Calendar className="h-4 w-4 text-primary" />
          Date range
        </p>
        <div className="grid grid-cols-2 gap-2">
          {rangeOptions.map((o) => (
            <button
              key={o.value}
              type="button"
              onClick={() => setRange(o.value)}
              className={cn(
                'rounded-lg border px-3 py-2 text-sm font-medium transition-colors text-left',
                range === o.value
                  ? 'border-primary bg-primary/10 text-primary'
                  : 'border-border text-muted hover:bg-surface-muted',
              )}
            >
              {o.label}
            </button>
          ))}
        </div>

        {range === 'custom' && (
          <div className="mt-3 grid grid-cols-2 gap-3">
            <Field label="From">
              <DateInput value={custom.from} onChange={(e) => setCustom((c) => ({ ...c, from: e.target.value }))} />
            </Field>
            <Field label="To">
              <DateInput value={custom.to} onChange={(e) => setCustom((c) => ({ ...c, to: e.target.value }))} />
            </Field>
          </div>
        )}
      </div>

      <div className="rounded-xl border border-border bg-surface-muted/30 p-4 text-xs text-muted space-y-1">
        <p className="font-medium text-foreground text-sm mb-2">What&apos;s included</p>
        <p>✓ Every transaction matching the range (all pages)</p>
        <p>✓ Transaction ID (for import deduplication)</p>
        <p>✓ Date, Kind, Amount, Currency, Category, Account</p>
        <p>✓ Payee, Note, Tags, Transfer Account, Recurring Rule</p>
      </div>

      {exporting && (
        <div className="space-y-2">
          <div className="flex items-center justify-between text-sm">
            <span className="text-muted">Fetching transactions…</span>
            <span className="font-medium">{progress}%</span>
          </div>
          <div className="h-2 rounded-full bg-surface-muted overflow-hidden">
            <div
              className="h-full rounded-full bg-primary transition-all duration-300"
              style={{ width: `${progress}%` }}
            />
          </div>
        </div>
      )}

      {done && (
        <div className="flex items-center gap-2 rounded-xl bg-emerald-500/10 px-4 py-3 text-sm text-emerald-700 dark:text-emerald-400">
          <CheckCircle2 className="h-4 w-4 shrink-0" />
          Export complete — check your downloads!
        </div>
      )}

      <Button
        className="w-full"
        onClick={doExport}
        loading={exporting}
        disabled={range === 'custom' && (!custom.from || !custom.to)}
      >
        <Download className="h-4 w-4" />
        Export CSV
      </Button>
    </div>
  );
}

/* ── Import Tab ─────────────────────────────────────────────── */
type ImportStatus = 'idle' | 'parsing' | 'importing' | 'done';
interface ImportResult { imported: number; skipped: number; failed: number; errors: string[] }

function ImportTab() {
  const { data: accountsData } = useSWR<{ items: Account[] }>('/accounts');
  const { data: categoriesData } = useSWR<{ items: Category[] }>('/categories');
  const fileRef = useRef<HTMLInputElement>(null);
  const [status, setStatus] = useState<ImportStatus>('idle');
  const [progress, setProgress] = useState(0);
  const [result, setResult] = useState<ImportResult | null>(null);
  const [dragging, setDragging] = useState(false);

  const accounts = useMemo(() => accountsData?.items ?? [], [accountsData?.items]);
  const categories = useMemo(() => categoriesData?.items ?? [], [categoriesData?.items]);

  const parseAndImport = useCallback(async (file: File) => {
    setStatus('parsing');
    setProgress(0);
    setResult(null);

    const text = await file.text();
    const lines = text.split('\n').filter((l) => l.trim());
    if (lines.length < 2) {
      toast.error('CSV appears empty or has no data rows');
      setStatus('idle');
      return;
    }

    const headers = lines[0]!.split(',').map((h) => h.trim().replace(/^"|"$/g, ''));
    const idIdx = headers.indexOf('id');
    const dateIdx = headers.indexOf('Date');
    const kindIdx = headers.indexOf('Kind');
    const amountIdx = headers.indexOf('Amount');
    const currencyIdx = headers.indexOf('Currency');
    const payeeIdx = headers.indexOf('Payee');
    const noteIdx = headers.indexOf('Note');
    const categoryIdx = headers.indexOf('Category');
    const accountIdx = headers.indexOf('Account');
    const tagsIdx = headers.indexOf('Tags');

    if (idIdx === -1 || dateIdx === -1 || kindIdx === -1 || amountIdx === -1) {
      toast.error('CSV must include id, Date, Kind, and Amount columns');
      setStatus('idle');
      return;
    }

    function parseRow(line: string): string[] {
      const result: string[] = [];
      let current = '';
      let inQuotes = false;
      for (let i = 0; i < line.length; i++) {
        const ch = line[i];
        if (ch === '"') {
          if (inQuotes && line[i + 1] === '"') { current += '"'; i++; }
          else inQuotes = !inQuotes;
        } else if (ch === ',' && !inQuotes) {
          result.push(current);
          current = '';
        } else {
          current += ch;
        }
      }
      result.push(current);
      return result;
    }

    const dataLines = lines.slice(1);
    setStatus('importing');

    const summary: ImportResult = { imported: 0, skipped: 0, failed: 0, errors: [] };

    // First, collect all existing IDs for this user to check duplicates
    // We batch-check by trying to GET each transaction (or use a simpler approach:
    // the API will reject duplicates if we pass the same id).
    // Strategy: try to POST each row; if 409 conflict → skip; else → import.

    for (let i = 0; i < dataLines.length; i++) {
      const fields = parseRow(dataLines[i]!);
      const csvId = fields[idIdx]?.trim();
      const date = fields[dateIdx]?.trim();
      const kind = fields[kindIdx]?.trim() as 'INCOME' | 'EXPENSE' | 'TRANSFER';
      const amount = parseFloat(fields[amountIdx]?.trim() ?? '0');
      const currency = fields[currencyIdx]?.trim() || 'ETB';
      const payee = payeeIdx >= 0 ? fields[payeeIdx]?.trim() || undefined : undefined;
      const note = noteIdx >= 0 ? fields[noteIdx]?.trim() || undefined : undefined;
      const categoryName = categoryIdx >= 0 ? fields[categoryIdx]?.trim() : '';
      const accountName = accountIdx >= 0 ? fields[accountIdx]?.trim() : '';
      const tags = tagsIdx >= 0 ? (fields[tagsIdx]?.trim() || '').split('|').filter(Boolean) : [];

      if (!date || !kind || isNaN(amount)) {
        summary.failed++;
        summary.errors.push(`Row ${i + 2}: missing required fields`);
        setProgress(Math.round(((i + 1) / dataLines.length) * 100));
        continue;
      }

      const account = accounts.find((a) => a.name === accountName);
      const category = categories.find((c) => c.name === categoryName);

      const payload = {
        kind,
        amount,
        currency,
        date,
        accountId: account?.id || accounts[0]?.id || '',
        categoryId: category?.id || undefined,
        payee,
        note,
        tags,
        importedId: csvId, // server uses this for deduplication
      };

      if (!payload.accountId) {
        summary.failed++;
        summary.errors.push(`Row ${i + 2}: no matching account for "${accountName}"`);
        setProgress(Math.round(((i + 1) / dataLines.length) * 100));
        continue;
      }

      try {
        // Try to create; server should return 409 if importedId already exists
        await api.post('/transactions', payload);
        summary.imported++;
      } catch (err) {
        if (err instanceof ApiError && err.status === 409) {
          summary.skipped++;
        } else {
          // Fallback deduplication: check if the CSV id matches an existing record
          // by treating it as skipped when we get any conflict-like error
          const msg = err instanceof ApiError ? err.message : 'Unknown error';
          if (msg.toLowerCase().includes('duplicate') || msg.toLowerCase().includes('already')) {
            summary.skipped++;
          } else {
            summary.failed++;
            summary.errors.push(`Row ${i + 2}: ${msg}`);
          }
        }
      }

      setProgress(Math.round(((i + 1) / dataLines.length) * 100));
    }

    setResult(summary);
    setStatus('done');

    if (summary.imported > 0) {
      toast.success(`Imported ${summary.imported} transaction${summary.imported !== 1 ? 's' : ''}`);
    }
    if (summary.skipped > 0) {
      toast.info(`Skipped ${summary.skipped} duplicate${summary.skipped !== 1 ? 's' : ''}`);
    }
    if (summary.failed > 0) {
      toast.error(`${summary.failed} row${summary.failed !== 1 ? 's' : ''} failed — see details below`);
    }
  }, [accounts, categories]);

  function handleFile(file: File) {
    if (!file.name.endsWith('.csv')) {
      toast.error('Please select a .csv file');
      return;
    }
    void parseAndImport(file);
  }

  return (
    <div className="space-y-5">
      {/* Drop zone */}
      <div
        onDragOver={(e) => { e.preventDefault(); setDragging(true); }}
        onDragLeave={() => setDragging(false)}
        onDrop={(e) => {
          e.preventDefault();
          setDragging(false);
          const file = e.dataTransfer.files[0];
          if (file) handleFile(file);
        }}
        onClick={() => fileRef.current?.click()}
        className={cn(
          'flex flex-col items-center justify-center gap-3 rounded-2xl border-2 border-dashed p-8 text-center cursor-pointer transition-colors',
          dragging
            ? 'border-primary bg-primary/8 text-primary'
            : 'border-border hover:border-primary/50 hover:bg-surface-muted/50',
          (status === 'parsing' || status === 'importing') && 'pointer-events-none opacity-60',
        )}
      >
        <input
          ref={fileRef}
          type="file"
          accept=".csv"
          className="hidden"
          onChange={(e) => { const f = e.target.files?.[0]; if (f) handleFile(f); }}
        />
        <span className="flex h-14 w-14 items-center justify-center rounded-2xl bg-primary/10 text-primary">
          <Upload className="h-6 w-6" />
        </span>
        <div>
          <p className="font-semibold">Drop your CSV here</p>
          <p className="text-sm text-muted mt-0.5">or click to browse — .csv files only</p>
        </div>
      </div>

      {/* Progress */}
      {(status === 'parsing' || status === 'importing') && (
        <div className="space-y-2">
          <div className="flex items-center justify-between text-sm">
            <span className="flex items-center gap-1.5 text-muted">
              <Loader2 className="h-3.5 w-3.5 animate-spin" />
              {status === 'parsing' ? 'Parsing file…' : `Importing rows… ${progress}%`}
            </span>
            <span className="font-medium tabular-nums">{progress}%</span>
          </div>
          <div className="h-2.5 rounded-full bg-surface-muted overflow-hidden">
            <div
              className="h-full rounded-full bg-primary transition-all duration-200"
              style={{ width: `${progress}%` }}
            />
          </div>
        </div>
      )}

      {/* Results */}
      {status === 'done' && result && (
        <div className="space-y-3">
          <div className="grid grid-cols-3 gap-2">
            <div className="rounded-xl bg-emerald-500/10 p-3 text-center">
              <CheckCircle2 className="mx-auto h-5 w-5 text-emerald-600 dark:text-emerald-400 mb-1" />
              <p className="text-xl font-bold text-emerald-700 dark:text-emerald-400">{result.imported}</p>
              <p className="text-xs text-muted">Imported</p>
            </div>
            <div className="rounded-xl bg-amber-500/10 p-3 text-center">
              <AlertCircle className="mx-auto h-5 w-5 text-amber-600 dark:text-amber-400 mb-1" />
              <p className="text-xl font-bold text-amber-700 dark:text-amber-400">{result.skipped}</p>
              <p className="text-xs text-muted">Duplicates</p>
            </div>
            <div className="rounded-xl bg-red-500/10 p-3 text-center">
              <XCircle className="mx-auto h-5 w-5 text-red-600 dark:text-red-400 mb-1" />
              <p className="text-xl font-bold text-red-700 dark:text-red-400">{result.failed}</p>
              <p className="text-xs text-muted">Failed</p>
            </div>
          </div>

          {result.errors.length > 0 && (
            <div className="rounded-xl border border-danger/30 bg-danger/5 p-3 max-h-32 overflow-y-auto">
              <p className="text-xs font-medium text-danger mb-1">Errors:</p>
              {result.errors.map((e, i) => (
                <p key={i} className="text-xs text-muted">{e}</p>
              ))}
            </div>
          )}

          <Button
            variant="outline"
            className="w-full"
            onClick={() => { setStatus('idle'); setResult(null); setProgress(0); if (fileRef.current) fileRef.current.value = ''; }}
          >
            Import another file
          </Button>
        </div>
      )}

      {status === 'idle' && (
        <div className="rounded-xl border border-border bg-surface-muted/30 p-4 text-xs text-muted space-y-1">
          <p className="font-medium text-foreground text-sm mb-2">Import notes</p>
          <p>• Rows with an existing <code className="font-mono bg-surface-muted px-1 rounded">id</code> are skipped (no duplicates)</p>
          <p>• Account and category matched by name — create them first if needed</p>
          <p>• Use the Export feature to get the correct column format</p>
        </div>
      )}
    </div>
  );
}

/* ── Main Modal ─────────────────────────────────────────────── */
export function ExportImportModal({
  open,
  onClose,
}: {
  open: boolean;
  onClose: () => void;
}) {
  const [tab, setTab] = useState<Tab>('export');

  return (
    <Modal open={open} onClose={onClose} title="Export & Import">
      {/* Tab switcher */}
      <div className="mb-5 flex gap-1 rounded-xl border border-border p-1">
        <button
          type="button"
          onClick={() => setTab('export')}
          className={cn(
            'flex flex-1 items-center justify-center gap-2 rounded-lg px-4 py-2 text-sm font-medium transition-colors',
            tab === 'export' ? 'bg-primary text-primary-foreground' : 'text-muted hover:bg-surface-muted',
          )}
        >
          <Download className="h-4 w-4" /> Export
        </button>
        <button
          type="button"
          onClick={() => setTab('import')}
          className={cn(
            'flex flex-1 items-center justify-center gap-2 rounded-lg px-4 py-2 text-sm font-medium transition-colors',
            tab === 'import' ? 'bg-primary text-primary-foreground' : 'text-muted hover:bg-surface-muted',
          )}
        >
          <Upload className="h-4 w-4" /> Import
        </button>
      </div>

      {tab === 'export' ? <ExportTab /> : <ImportTab />}
    </Modal>
  );
}
