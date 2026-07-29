'use client';

import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type CSSProperties,
  type ReactNode,
} from 'react';
import { createPortal } from 'react-dom';
import { Info } from 'lucide-react';
import { cn } from '@/lib/utils';

/**
 * Small `i` affordance that tucks explanatory copy out of the layout.
 * Hover (pointer devices) or tap/click opens a bubble anchored to the icon,
 * so pages and modals keep their headings clean instead of carrying a
 * paragraph of helper text nobody reads twice.
 */
export function InfoHint({
  children,
  label = 'More information',
  className,
  side = 'bottom',
}: {
  children: ReactNode;
  /** Accessible name for the trigger. */
  label?: string;
  className?: string;
  /** Preferred placement; flips automatically when space runs out. */
  side?: 'bottom' | 'top';
}) {
  const triggerRef = useRef<HTMLButtonElement>(null);
  const bubbleRef = useRef<HTMLDivElement>(null);
  const closeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [open, setOpen] = useState(false);
  const [mounted, setMounted] = useState(false);
  const [style, setStyle] = useState<CSSProperties>({});

  useEffect(() => setMounted(true), []);

  const cancelClose = useCallback(() => {
    if (closeTimer.current) clearTimeout(closeTimer.current);
    closeTimer.current = null;
  }, []);

  // Small grace period so the pointer can travel from icon to bubble.
  const scheduleClose = useCallback(() => {
    cancelClose();
    closeTimer.current = setTimeout(() => setOpen(false), 120);
  }, [cancelClose]);

  useEffect(() => cancelClose, [cancelClose]);

  useLayoutEffect(() => {
    if (!open || !triggerRef.current) return;
    const place = () => {
      const rect = triggerRef.current!.getBoundingClientRect();
      const width = Math.min(288, window.innerWidth - 24);
      const spaceBelow = window.innerHeight - rect.bottom;
      const flip = side === 'top' ? spaceBelow > 200 && rect.top < 200 : spaceBelow < 140 && rect.top > spaceBelow;
      const openUp = side === 'top' ? !flip : flip;
      // Centre on the icon, then keep the bubble inside the viewport.
      const left = Math.min(
        Math.max(12, rect.left + rect.width / 2 - width / 2),
        window.innerWidth - width - 12,
      );
      setStyle({
        position: 'fixed',
        left,
        width,
        zIndex: 120,
        ...(openUp
          ? { bottom: window.innerHeight - rect.top + 8 }
          : { top: rect.bottom + 8 }),
      });
    };
    place();
    window.addEventListener('resize', place);
    window.addEventListener('scroll', place, true);
    return () => {
      window.removeEventListener('resize', place);
      window.removeEventListener('scroll', place, true);
    };
  }, [open, side]);

  useEffect(() => {
    if (!open) return;
    const onDoc = (e: MouseEvent) => {
      const t = e.target as Node;
      if (triggerRef.current?.contains(t) || bubbleRef.current?.contains(t)) return;
      setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false);
    document.addEventListener('mousedown', onDoc);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('mousedown', onDoc);
      document.removeEventListener('keydown', onKey);
    };
  }, [open]);

  return (
    <>
      <button
        ref={triggerRef}
        type="button"
        aria-label={label}
        aria-expanded={open}
        onClick={(e) => {
          // Cards and rows often wrap this in a link — never navigate on a hint tap.
          e.preventDefault();
          e.stopPropagation();
          cancelClose();
          setOpen((o) => !o);
        }}
        onMouseEnter={() => {
          cancelClose();
          setOpen(true);
        }}
        onMouseLeave={scheduleClose}
        onFocus={() => setOpen(true)}
        onBlur={scheduleClose}
        className={cn(
          'inline-flex h-5 w-5 shrink-0 items-center justify-center rounded-full align-middle text-muted transition-colors',
          'hover:bg-surface-muted hover:text-foreground focus:outline-none focus-visible:ring-2 focus-visible:ring-ring/50',
          open && 'bg-primary/10 text-primary',
          className,
        )}
      >
        <Info className="h-3.5 w-3.5" />
      </button>

      {open && mounted
        ? createPortal(
            <div
              ref={bubbleRef}
              role="tooltip"
              style={{ ...style, boxShadow: 'var(--shadow-elevated)' }}
              onMouseEnter={cancelClose}
              onMouseLeave={scheduleClose}
              className="rounded-xl border border-border bg-surface p-3 text-xs leading-relaxed text-muted animate-in"
            >
              {children}
            </div>,
            document.body,
          )
        : null}
    </>
  );
}
