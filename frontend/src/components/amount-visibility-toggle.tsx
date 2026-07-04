'use client';

import { Eye, EyeOff } from 'lucide-react';
import { useAmountVisibility } from '@/lib/amount-visibility';
import { cn } from '@/lib/utils';

export function AmountVisibilityToggle({ className }: { className?: string }) {
  const { hidden, toggle } = useAmountVisibility();

  return (
    <button
      type="button"
      aria-label={hidden ? 'Show amounts' : 'Hide amounts'}
      title={hidden ? 'Show amounts' : 'Hide amounts'}
      onClick={toggle}
      className={cn(
        'inline-flex h-9 w-9 items-center justify-center rounded-lg border border-border text-muted transition-colors hover:bg-surface-muted hover:text-foreground',
        hidden && 'text-primary',
        className,
      )}
    >
      {hidden ? <EyeOff className="h-4.5 w-4.5" /> : <Eye className="h-4.5 w-4.5" />}
    </button>
  );
}
