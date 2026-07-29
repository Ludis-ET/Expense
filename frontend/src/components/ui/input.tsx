import { forwardRef, type InputHTMLAttributes, type TextareaHTMLAttributes } from 'react';
import { InfoHint } from '@/components/ui/info-hint';
import { cn } from '@/lib/utils';

export { Select } from '@/components/ui/select';
export type { SelectOption } from '@/components/ui/select';
export { DateField, DateRangeField, todayISO } from '@/components/ui/date-field';

const base =
  'w-full rounded-xl border border-border bg-surface px-3.5 text-sm text-foreground shadow-sm ' +
  'placeholder:text-muted transition-all duration-200 ' +
  'hover:border-primary/30 focus:outline-none focus:ring-2 focus:ring-ring/50 focus:border-ring disabled:opacity-50 disabled:pointer-events-none';

export const Input = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement>>(
  ({ className, ...props }, ref) => <input ref={ref} className={cn(base, 'h-10', className)} {...props} />,
);
Input.displayName = 'Input';

/**
 * Kept as the name every form already imports; `DateField` is the real
 * implementation, so existing call sites pick up the new look for free.
 */
export { DateField as DateInput } from '@/components/ui/date-field';

export const Textarea = forwardRef<HTMLTextAreaElement, TextareaHTMLAttributes<HTMLTextAreaElement>>(
  ({ className, ...props }, ref) => (
    <textarea ref={ref} className={cn(base, 'min-h-24 py-2.5 resize-y', className)} {...props} />
  ),
);
Textarea.displayName = 'Textarea';

export function Label({ className, ...props }: React.LabelHTMLAttributes<HTMLLabelElement>) {
  return <label className={cn('mb-1.5 block text-sm font-medium text-foreground', className)} {...props} />;
}

/**
 * Label + control. A `hint` rides behind an `i` icon on the label row instead
 * of adding another line of grey copy under every input.
 */
export function Field({
  label,
  children,
  hint,
}: {
  label: string;
  children: React.ReactNode;
  hint?: React.ReactNode;
}) {
  return (
    <div>
      <div className="mb-1.5 flex items-center gap-1.5">
        <Label className="mb-0">{label}</Label>
        {hint && <InfoHint label={`About ${label}`}>{hint}</InfoHint>}
      </div>
      {children}
    </div>
  );
}
