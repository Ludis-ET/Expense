'use client';

import { Download } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { usePwaInstall } from '@/lib/pwa-install-context';

interface DownloadAppButtonProps {
  size?: 'sm' | 'md';
  variant?: 'primary' | 'outline' | 'ghost';
  className?: string;
  showIcon?: boolean;
  label?: string;
}

export function DownloadAppButton({
  size = 'sm',
  variant = 'outline',
  className,
  showIcon = true,
  label = 'Download app',
}: DownloadAppButtonProps) {
  const { canInstall, install } = usePwaInstall();

  if (!canInstall) return null;

  return (
    <Button
      type="button"
      size={size}
      variant={variant}
      className={cn('shrink-0', className)}
      onClick={() => void install()}
    >
      {showIcon && <Download className="h-4 w-4" aria-hidden />}
      {label}
    </Button>
  );
}
