import type { HTMLAttributes } from 'react';
import { cn } from '@/lib/utils';
import type { ExpenseStatus, IdeaStatus, MilestoneStatus, ProjectStatus } from '@/lib/types';

type Tone = 'neutral' | 'primary' | 'success' | 'warning' | 'danger' | 'info';

const tones: Record<Tone, string> = {
  neutral: 'bg-surface-muted text-muted',
  primary: 'bg-primary/10 text-primary',
  success: 'bg-emerald-500/12 text-emerald-600 dark:text-emerald-400',
  warning: 'bg-amber-500/12 text-amber-600 dark:text-amber-400',
  danger: 'bg-red-500/12 text-red-600 dark:text-red-400',
  info: 'bg-sky-500/12 text-sky-600 dark:text-sky-400',
};

export function Badge({
  tone = 'neutral',
  className,
  ...props
}: HTMLAttributes<HTMLSpanElement> & { tone?: Tone }) {
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-medium',
        tones[tone],
        className,
      )}
      {...props}
    />
  );
}

const projectTone: Record<ProjectStatus, Tone> = {
  PLANNING: 'info',
  ACTIVE: 'success',
  ON_HOLD: 'warning',
  COMPLETED: 'primary',
  CANCELLED: 'danger',
};

const milestoneTone: Record<MilestoneStatus, Tone> = {
  PENDING: 'neutral',
  IN_PROGRESS: 'info',
  DONE: 'success',
};

const expenseTone: Record<ExpenseStatus, Tone> = {
  PENDING: 'warning',
  APPROVED: 'success',
  REJECTED: 'danger',
};

const ideaTone: Record<IdeaStatus, Tone> = {
  OPEN: 'info',
  CONVERTED: 'success',
  CLOSED: 'neutral',
};

const label = (s: string) => s.replace(/_/g, ' ').toLowerCase().replace(/^\w/, (c) => c.toUpperCase());

export const StatusBadge = {
  Project: ({ status }: { status: ProjectStatus }) => <Badge tone={projectTone[status]}>{label(status)}</Badge>,
  Milestone: ({ status }: { status: MilestoneStatus }) => <Badge tone={milestoneTone[status]}>{label(status)}</Badge>,
  Expense: ({ status }: { status: ExpenseStatus }) => <Badge tone={expenseTone[status]}>{label(status)}</Badge>,
  Idea: ({ status }: { status: IdeaStatus }) => <Badge tone={ideaTone[status]}>{label(status)}</Badge>,
};
