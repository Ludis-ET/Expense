'use client';

import { Check, Loader2 } from 'lucide-react';
import { cn } from '@/lib/utils';

interface CheckboxProps {
  checked: boolean;
  onChange: (checked: boolean) => void;
  loading?: boolean;
  disabled?: boolean;
  label?: React.ReactNode;
  className?: string;
  id?: string;
}

export function Checkbox({ checked, onChange, loading, disabled, label, className, id }: CheckboxProps) {
  const off = disabled || loading;

  return (
    <label
      htmlFor={id}
      className={cn(
        'inline-flex cursor-pointer select-none items-center gap-2.5 text-sm transition-opacity',
        off && 'cursor-not-allowed opacity-60',
        className,
      )}
    >
      <span
        className={cn(
          'relative flex h-5 w-5 shrink-0 items-center justify-center rounded-md border-2 transition-all duration-200',
          checked ? 'border-primary bg-primary text-primary-foreground shadow-sm shadow-primary/20' : 'border-border bg-surface hover:border-primary/40',
          !off && !checked && 'hover:bg-surface-muted',
        )}
      >
        {loading ? (
          <Loader2 className="h-3 w-3 animate-spin text-primary" />
        ) : checked ? (
          <Check className="h-3 w-3 stroke-[3]" />
        ) : null}
      </span>
      <input
        id={id}
        type="checkbox"
        className="sr-only"
        checked={checked}
        disabled={off}
        onChange={(e) => onChange(e.target.checked)}
      />
      {label && <span className={cn('text-muted', checked && 'text-foreground')}>{label}</span>}
    </label>
  );
}
