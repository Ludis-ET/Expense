import { Coins } from 'lucide-react';
import { cn } from '@/lib/utils';

export function Brand({ className, compact = false }: { className?: string; compact?: boolean }) {
  return (
    <div className={cn('flex items-center gap-2.5', className)}>
      <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-primary to-accent text-white shadow-md shadow-primary/25">
        <Coins className="h-5 w-5" />
      </div>
      {!compact && (
        <span className="text-lg font-bold tracking-tight">
          San<span className="text-primary">tim</span>
        </span>
      )}
    </div>
  );
}
