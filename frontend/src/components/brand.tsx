import { FlaskConical } from 'lucide-react';
import { cn } from '@/lib/utils';

export function Brand({ className, compact = false }: { className?: string; compact?: boolean }) {
  return (
    <div className={cn('flex items-center gap-2.5', className)}>
      <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-gradient-to-br from-primary to-accent text-white shadow-sm shadow-primary/30">
        <FlaskConical className="h-5 w-5" />
      </div>
      {!compact && (
        <span className="text-lg font-bold tracking-tight">
          Research<span className="text-primary">Tracker</span>
        </span>
      )}
    </div>
  );
}
