'use client';

import { Check } from 'lucide-react';
import { FINANCE_COLORS, ICON_NAMES, financeIcon } from './icons';
import { cn } from '@/lib/utils';

/** Grid of curated lucide icons. */
export function IconPicker({ value, onChange }: { value: string; onChange: (icon: string) => void }) {
  return (
    <div className="grid max-h-40 grid-cols-8 gap-1.5 overflow-y-auto rounded-lg border border-border p-2">
      {ICON_NAMES.map((name) => {
        const Icon = financeIcon(name);
        return (
          <button
            key={name}
            type="button"
            onClick={() => onChange(name)}
            className={cn(
              'flex h-8 w-8 items-center justify-center rounded-md transition-colors',
              value === name ? 'bg-primary text-primary-foreground' : 'text-muted hover:bg-surface-muted',
            )}
            aria-label={name}
          >
            <Icon className="h-4 w-4" />
          </button>
        );
      })}
    </div>
  );
}

/** Row of color swatches. */
export function ColorPicker({ value, onChange }: { value: string; onChange: (color: string) => void }) {
  return (
    <div className="flex flex-wrap gap-2">
      {FINANCE_COLORS.map((color) => (
        <button
          key={color}
          type="button"
          onClick={() => onChange(color)}
          className="flex h-7 w-7 items-center justify-center rounded-full ring-offset-2 ring-offset-background transition-transform hover:scale-110"
          style={{ backgroundColor: color, boxShadow: value === color ? `0 0 0 2px ${color}` : undefined }}
          aria-label={color}
        >
          {value === color && <Check className="h-3.5 w-3.5 text-white" />}
        </button>
      ))}
    </div>
  );
}
