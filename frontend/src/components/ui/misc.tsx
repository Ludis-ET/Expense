import type { ReactNode } from 'react';
import { Loader2 } from 'lucide-react';
import { Brand } from '@/components/brand';
import { cn } from '@/lib/utils';
import { initials } from '@/lib/format';

export function Avatar({ name, className }: { name: string; className?: string }) {
  return (
    <div
      className={cn(
        'flex shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-primary to-accent text-xs font-semibold text-white shadow-sm',
        'h-9 w-9',
        className,
      )}
      title={name}
    >
      {initials(name)}
    </div>
  );
}

export function Skeleton({ className }: { className?: string }) {
  return (
    <div
      className={cn(
        'relative overflow-hidden rounded-xl bg-surface-muted/80',
        'before:absolute before:inset-0 before:-translate-x-full before:animate-shimmer',
        'before:bg-gradient-to-r before:from-transparent before:via-white/40 before:to-transparent',
        'dark:before:via-white/10',
        className,
      )}
    />
  );
}

export function Spinner({ className }: { className?: string }) {
  return <Loader2 className={cn('h-5 w-5 animate-spin text-muted', className)} />;
}

/** Full-screen branded loader used while auth/shell bootstraps. */
export function AppLoader({ label = 'Loading your workspace…' }: { label?: string }) {
  return (
    <div className="relative flex min-h-screen flex-col items-center justify-center overflow-hidden bg-mesh px-6">
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 bg-grid opacity-40 [mask-image:radial-gradient(ellipse_at_center,black_20%,transparent_70%)]"
      />
      <div className="relative flex flex-col items-center gap-6 animate-in">
        <div className="relative">
          <div
            aria-hidden
            className="absolute -inset-4 rounded-[1.75rem] bg-gradient-to-br from-primary/25 to-accent/20 blur-xl"
          />
          <div className="relative flex h-16 w-16 items-center justify-center rounded-2xl border border-border/60 bg-surface shadow-[var(--shadow-elevated)]">
            <Brand compact className="[&>div]:h-11 [&>div]:w-11 [&>div]:rounded-xl [&>div>svg]:h-6 [&>div>svg]:w-6" />
            <span
              aria-hidden
              className="absolute inset-0 rounded-2xl border-2 border-transparent border-t-primary/80 animate-spin-slow"
            />
          </div>
        </div>
        <div className="text-center">
          <p className="text-sm font-medium text-foreground">{label}</p>
          <div className="mx-auto mt-4 flex items-center justify-center gap-1.5" aria-hidden>
            <span className="h-1.5 w-1.5 animate-bounce-dot rounded-full bg-primary [animation-delay:0ms]" />
            <span className="h-1.5 w-1.5 animate-bounce-dot rounded-full bg-primary [animation-delay:120ms]" />
            <span className="h-1.5 w-1.5 animate-bounce-dot rounded-full bg-primary [animation-delay:240ms]" />
          </div>
        </div>
      </div>
    </div>
  );
}

/** Compact in-page loading block with shimmer cards. */
export function PageLoader({ rows = 4 }: { rows?: number }) {
  return (
    <div className="animate-in space-y-4" role="status" aria-label="Loading">
      <div className="flex items-end justify-between gap-3">
        <div className="space-y-2">
          <Skeleton className="h-8 w-48" />
          <Skeleton className="h-4 w-64 max-w-full" />
        </div>
        <Skeleton className="h-10 w-28" />
      </div>
      <div className="grid gap-3 sm:grid-cols-3">
        <Skeleton className="h-24" />
        <Skeleton className="h-24" />
        <Skeleton className="h-24" />
      </div>
      <div className="space-y-3">
        {Array.from({ length: rows }).map((_, i) => (
          <Skeleton key={i} className="h-14" />
        ))}
      </div>
    </div>
  );
}

export function ProgressBar({ value, tone = 'primary' }: { value: number; tone?: 'primary' | 'success' | 'warning' | 'danger' }) {
  const colors = {
    primary: 'bg-gradient-to-r from-primary to-accent',
    success: 'bg-gradient-to-r from-emerald-500 to-teal-500',
    warning: 'bg-gradient-to-r from-amber-500 to-orange-500',
    danger: 'bg-gradient-to-r from-red-500 to-rose-500',
  };
  return (
    <div className="h-2 w-full overflow-hidden rounded-full bg-surface-muted">
      <div
        className={cn('h-full rounded-full transition-all duration-700 ease-out', colors[tone])}
        style={{ width: `${Math.min(100, Math.max(0, value))}%` }}
      />
    </div>
  );
}

export function EmptyState({
  icon,
  title,
  description,
  action,
}: {
  icon?: ReactNode;
  title: string;
  description?: string;
  action?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center rounded-xl border border-dashed border-border bg-surface-muted/30 px-6 py-12 text-center">
      {icon && (
        <div className="mb-3 flex h-12 w-12 items-center justify-center rounded-2xl bg-surface-muted text-muted">
          {icon}
        </div>
      )}
      <h3 className="text-sm font-semibold">{title}</h3>
      {description && <p className="mt-1 max-w-sm text-sm text-muted">{description}</p>}
      {action && <div className="mt-4">{action}</div>}
    </div>
  );
}

export function PageHeader({
  title,
  description,
  action,
  badge,
}: {
  title: string;
  description?: string;
  action?: ReactNode;
  badge?: ReactNode;
}) {
  return (
    <div className="mb-6 flex flex-wrap items-end justify-between gap-3">
      <div>
        <div className="flex items-center gap-2">
          <h1 className="text-2xl font-bold tracking-tight md:text-3xl">{title}</h1>
          {badge}
        </div>
        {description && <p className="mt-1 text-sm text-muted">{description}</p>}
      </div>
      {action}
    </div>
  );
}
