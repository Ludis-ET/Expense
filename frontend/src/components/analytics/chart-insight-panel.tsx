'use client';

import { X } from 'lucide-react';
import { cn } from '@/lib/utils';
import { withBase } from '@/lib/base-path';

export interface ChartInsight {
  title: string;
  subtitle?: string;
  value?: string;
  detail?: string;
  tone?: 'default' | 'income' | 'expense' | 'warning';
  action?: { label: string; href: string };
}

export function ChartInsightPanel({
  insight,
  onClose,
  className,
}: {
  insight: ChartInsight | null;
  onClose: () => void;
  className?: string;
}) {
  if (!insight) return null;

  const tones = {
    default: 'border-border bg-surface-muted/50',
    income: 'border-emerald-500/30 bg-emerald-500/5',
    expense: 'border-red-500/30 bg-red-500/5',
    warning: 'border-warning/30 bg-warning/5',
  };

  return (
    <div
      role="status"
      className={cn('animate-in rounded-xl border p-4', tones[insight.tone ?? 'default'], className)}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="font-semibold">{insight.title}</p>
          {insight.subtitle && <p className="mt-0.5 text-xs text-muted">{insight.subtitle}</p>}
        </div>
        <button
          type="button"
          onClick={onClose}
          className="shrink-0 rounded-lg p-1 text-muted hover:bg-surface-muted"
          aria-label="Close insight"
        >
          <X className="h-4 w-4" />
        </button>
      </div>
      {insight.value && <p className="mt-2 text-2xl font-bold tabular-nums">{insight.value}</p>}
      {insight.detail && <p className="mt-2 text-sm leading-relaxed text-muted">{insight.detail}</p>}
      {insight.action && (
        <a href={withBase(insight.action.href)} className="mt-3 inline-block text-sm font-medium text-primary hover:underline">
          {insight.action.label} →
        </a>
      )}
    </div>
  );
}
