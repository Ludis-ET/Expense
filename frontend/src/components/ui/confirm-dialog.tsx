'use client';

import { createContext, useCallback, useContext, useState, type ReactNode } from 'react';
import { AlertTriangle } from 'lucide-react';
import { Modal } from '@/components/ui/modal';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';

export interface ConfirmOptions {
  title?: string;
  description: string;
  confirmLabel?: string;
  cancelLabel?: string;
  tone?: 'danger' | 'default';
}

interface ConfirmState extends ConfirmOptions {
  resolve: (value: boolean) => void;
}

const ConfirmContext = createContext<((options: ConfirmOptions) => Promise<boolean>) | null>(null);

export function ConfirmProvider({ children }: { children: ReactNode }) {
  const [pending, setPending] = useState<ConfirmState | null>(null);

  const confirm = useCallback((options: ConfirmOptions) => {
    return new Promise<boolean>((resolve) => {
      setPending({ ...options, resolve });
    });
  }, []);

  function finish(value: boolean) {
    pending?.resolve(value);
    setPending(null);
  }

  const tone = pending?.tone ?? 'default';

  return (
    <ConfirmContext.Provider value={confirm}>
      {children}
      {pending && (
        <Modal
          open
          onClose={() => finish(false)}
          title={pending.title ?? 'Are you sure?'}
          className="max-w-md"
        >
          <div className="flex flex-col gap-4">
            <div
              className={cn(
                'flex items-start gap-3 rounded-xl border p-4',
                tone === 'danger'
                  ? 'border-danger/20 bg-danger/5'
                  : 'border-border bg-surface-muted/50',
              )}
            >
              <span
                className={cn(
                  'flex h-10 w-10 shrink-0 items-center justify-center rounded-xl',
                  tone === 'danger' ? 'bg-danger/10 text-danger' : 'bg-primary/10 text-primary',
                )}
              >
                <AlertTriangle className="h-5 w-5" />
              </span>
              <p className="text-sm leading-relaxed text-foreground">{pending.description}</p>
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => finish(false)}>
                {pending.cancelLabel ?? 'Cancel'}
              </Button>
              <Button variant={tone === 'danger' ? 'danger' : 'primary'} onClick={() => finish(true)}>
                {pending.confirmLabel ?? 'Confirm'}
              </Button>
            </div>
          </div>
        </Modal>
      )}
    </ConfirmContext.Provider>
  );
}

export function useConfirm() {
  const confirm = useContext(ConfirmContext);
  if (!confirm) throw new Error('useConfirm must be used within ConfirmProvider');
  return confirm;
}
