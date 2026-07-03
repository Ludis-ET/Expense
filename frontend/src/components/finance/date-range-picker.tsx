'use client';

import { useState } from 'react';
import { CalendarRange } from 'lucide-react';
import { DateInput } from '@/components/ui/input';
import { cn } from '@/lib/utils';
import {
  type DatePreset,
  formatRangeLabel,
  presetLabel,
  rangeFromPreset,
  type DateRange,
} from '@/lib/date-range';

const PRESETS: DatePreset[] = ['7d', '30d', '90d', '6m', '1y', 'ytd', 'all', 'custom'];

interface DateRangePickerProps {
  value: DateRange;
  onChange: (range: DateRange) => void;
  loading?: boolean;
}

export function DateRangePicker({ value, onChange, loading }: DateRangePickerProps) {
  const [customFrom, setCustomFrom] = useState(value.from.toISOString().slice(0, 10));
  const [customTo, setCustomTo] = useState(value.to.toISOString().slice(0, 10));

  function pick(preset: DatePreset) {
    if (preset === 'custom') {
      onChange(rangeFromPreset('custom', customFrom, customTo));
      return;
    }
    onChange(rangeFromPreset(preset));
  }

  function applyCustom() {
    onChange(rangeFromPreset('custom', customFrom, customTo));
  }

  return (
    <div className={cn('card overflow-hidden transition-opacity', loading && 'opacity-70')}>
      <div className="flex flex-col gap-4 border-b border-border bg-gradient-to-r from-primary/5 via-transparent to-accent/5 px-5 py-4 lg:flex-row lg:items-center lg:justify-between">
        <div className="flex items-center gap-3">
          <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary/10 text-primary">
            <CalendarRange className="h-5 w-5" />
          </span>
          <div>
            <p className="text-sm font-semibold">Date range</p>
            <p className="text-xs text-muted">{formatRangeLabel(value.from, value.to)}</p>
          </div>
        </div>
        <div className="flex flex-wrap gap-1.5">
          {PRESETS.filter((p) => p !== 'custom').map((p) => (
            <button
              key={p}
              type="button"
              onClick={() => pick(p)}
              disabled={loading}
              className={cn(
                'rounded-lg px-3 py-1.5 text-xs font-medium transition-all active:scale-95',
                value.preset === p
                  ? 'bg-primary text-primary-foreground shadow-sm shadow-primary/20'
                  : 'bg-surface-muted text-muted hover:bg-surface-muted/80 hover:text-foreground',
              )}
            >
              {presetLabel(p)}
            </button>
          ))}
        </div>
      </div>

      <div className="flex flex-wrap items-end gap-3 px-5 py-4">
        <div className="w-40">
          <label className="mb-1.5 block text-xs font-medium text-muted">From</label>
          <DateInput
            value={customFrom}
            onChange={(e) => setCustomFrom(e.target.value)}
            max={customTo}
          />
        </div>
        <div className="w-40">
          <label className="mb-1.5 block text-xs font-medium text-muted">To</label>
          <DateInput
            value={customTo}
            onChange={(e) => setCustomTo(e.target.value)}
            min={customFrom}
            max={new Date().toISOString().slice(0, 10)}
          />
        </div>
        <button
          type="button"
          onClick={applyCustom}
          disabled={loading}
          className={cn(
            'h-10 rounded-xl border border-border bg-surface px-4 text-sm font-medium transition-all hover:bg-surface-muted active:scale-95',
            value.preset === 'custom' && 'border-primary/40 bg-primary/5 text-primary',
          )}
        >
          Apply custom
        </button>
      </div>
    </div>
  );
}
