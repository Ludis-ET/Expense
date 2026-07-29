'use client';

import { forwardRef, useId, type InputHTMLAttributes } from 'react';
import { ArrowRight, CalendarDays, X } from 'lucide-react';
import { cn } from '@/lib/utils';

/** Today as YYYY-MM-DD, the format `<input type="date">` speaks. */
export function todayISO(): string {
  const d = new Date();
  const local = new Date(d.getTime() - d.getTimezoneOffset() * 60_000);
  return local.toISOString().slice(0, 10);
}

const shell =
  'group relative flex h-11 w-full items-center gap-2 rounded-xl border border-border bg-surface px-3 ' +
  'shadow-sm transition-all duration-200 hover:border-primary/40 ' +
  'focus-within:border-ring focus-within:ring-2 focus-within:ring-ring/50';

export interface DateFieldProps
  extends Omit<InputHTMLAttributes<HTMLInputElement>, 'type' | 'size'> {
  /** Refuse anything after today. Use for things that already happened. */
  maxToday?: boolean;
  /** Show a clear button once a value is set. */
  clearable?: boolean;
  onClear?: () => void;
}

/**
 * A single date. Wraps the native picker so the calendar stays the OS one
 * (fast, accessible, localised) while the chrome matches the rest of the app:
 * the whole field is the hit target, and the value reads back in words.
 */
export const DateField = forwardRef<HTMLInputElement, DateFieldProps>(
  ({ className, maxToday, clearable, onClear, value, max, disabled, ...props }, ref) => {
    const id = useId();
    const resolvedMax = maxToday ? (max ? minOf(String(max), todayISO()) : todayISO()) : max;
    const has = !!value;

    return (
      <div className={cn(shell, disabled && 'pointer-events-none opacity-50', className)}>
        <CalendarDays className="h-4 w-4 shrink-0 text-muted transition-colors group-focus-within:text-primary" />

        <label htmlFor={id} className="min-w-0 flex-1 cursor-pointer">
          <span className={cn('block truncate text-sm', has ? 'text-foreground' : 'text-muted')}>
            {has ? prettyDate(String(value)) : 'Any date'}
          </span>
        </label>

        {clearable && has && (
          <button
            type="button"
            onClick={onClear}
            aria-label="Clear date"
            className="shrink-0 rounded-md p-1 text-muted transition-colors hover:bg-surface-muted hover:text-foreground"
          >
            <X className="h-3.5 w-3.5" />
          </button>
        )}

        {/* The real control, stretched over the field so a click anywhere opens
            the picker. Browsers only open it from the calendar indicator, so
            ask for it explicitly; where showPicker is missing the input still
            focuses and takes keyboard input as normal. */}
        <input
          {...props}
          ref={ref}
          id={id}
          type="date"
          value={value}
          max={resolvedMax}
          disabled={disabled}
          onClick={(e) => {
            try {
              e.currentTarget.showPicker?.();
            } catch {
              // Safari throws when called outside a user gesture it trusts.
            }
            props.onClick?.(e);
          }}
          className="absolute inset-0 h-full w-full cursor-pointer opacity-0 scheme-light dark:scheme-dark"
        />
      </div>
    );
  },
);
DateField.displayName = 'DateField';

/**
 * A from/to pair that cannot express nonsense: "to" never precedes "from",
 * and neither can run past today when `maxToday` is set.
 */
export function DateRangeField({
  from,
  to,
  onFrom,
  onTo,
  maxToday,
  className,
  disabled,
}: {
  from: string;
  to: string;
  onFrom: (v: string) => void;
  onTo: (v: string) => void;
  maxToday?: boolean;
  className?: string;
  disabled?: boolean;
}) {
  return (
    <div className={cn('flex items-center gap-2', className)}>
      <DateField
        value={from}
        onChange={(e) => {
          const next = e.target.value;
          onFrom(next);
          // Dragging the start past the end pushes the end along, rather than
          // leaving an impossible range on screen.
          if (next && to && next > to) onTo(next);
        }}
        max={to || undefined}
        maxToday={maxToday}
        clearable
        onClear={() => onFrom('')}
        disabled={disabled}
        aria-label="From date"
      />

      <ArrowRight className="h-4 w-4 shrink-0 text-muted" aria-hidden />

      <DateField
        value={to}
        onChange={(e) => onTo(e.target.value)}
        min={from || undefined}
        maxToday={maxToday}
        clearable
        onClear={() => onTo('')}
        disabled={disabled}
        aria-label="To date"
      />
    </div>
  );
}

function minOf(a: string, b: string): string {
  return a < b ? a : b;
}

/** "12 Mar 2026", or "Today" / "Yesterday" when that is friendlier. */
function prettyDate(iso: string): string {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(iso)) return iso;
  const today = todayISO();
  if (iso === today) return 'Today';

  const y = new Date(`${today}T00:00:00`);
  y.setDate(y.getDate() - 1);
  if (iso === y.toISOString().slice(0, 10)) return 'Yesterday';

  const [yy, mm, dd] = iso.split('-').map(Number);
  const d = new Date(yy!, (mm ?? 1) - 1, dd ?? 1);
  return new Intl.DateTimeFormat('en-GB', {
    day: 'numeric',
    month: 'short',
    year: d.getFullYear() === new Date().getFullYear() ? undefined : 'numeric',
  }).format(d);
}
