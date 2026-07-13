'use client';

import { Download, Share, Smartphone } from 'lucide-react';
import { Modal } from '@/components/ui/modal';
import { Button } from '@/components/ui/button';
import { usePwaInstall } from '@/lib/pwa-install-context';

export function InstallInstructionsModal() {
  const { instructionsOpen, closeInstructions, platform, hasNativePrompt, install } = usePwaInstall();

  const steps =
    platform === 'ios'
      ? [
          { icon: Share, text: 'Open Santim in Safari (not Chrome or in-app browsers).' },
          { icon: Share, text: 'Tap the Share button (square with an arrow).' },
          { icon: Smartphone, text: 'Scroll down and tap "Add to Home Screen".' },
          { icon: Download, text: 'Tap Add — Santim appears on your home screen like an app.' },
        ]
      : platform === 'android'
        ? hasNativePrompt
          ? [
              { icon: Download, text: 'Tap Install below to open Chrome’s install dialog.' },
              { icon: Smartphone, text: 'Confirm Install — Santim opens full screen from your home screen.' },
            ]
          : [
              { icon: Download, text: 'Use Chrome (not Facebook/Instagram in-app browser).' },
              { icon: Smartphone, text: 'Stay on the site ~30 seconds, then open the ⋮ menu.' },
              { icon: Download, text: 'Tap "Install app" or "Add to Home screen", then confirm.' },
            ]
        : [
            { icon: Download, text: 'In Chrome, open the browser menu (⋮).' },
            { icon: Smartphone, text: 'Choose "Install Santim…" or "Cast, save, and share" → "Install page as app".' },
            { icon: Download, text: 'Confirm — Santim opens in its own window.' },
          ];

  return (
    <Modal open={instructionsOpen} onClose={closeInstructions} title="Install Santim">
      <div className="space-y-4">
        <p className="text-sm text-muted">
          Install Santim for a full-screen app experience and one-tap access to your money.
        </p>
        {!hasNativePrompt && platform === 'android' && (
          <p className="rounded-xl border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-xs text-amber-800 dark:text-amber-200">
            If Chrome says “Can’t install app”, open this site in Chrome over HTTPS (or localhost), refresh once,
            and make sure Santim isn’t already installed under your apps list.
          </p>
        )}
        <ol className="space-y-3">
          {steps.map((step, i) => {
            const Icon = step.icon;
            return (
              <li key={i} className="flex gap-3 text-sm">
                <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
                  <Icon className="h-4 w-4" aria-hidden />
                </span>
                <span className="pt-1 leading-relaxed">
                  <span className="font-medium text-foreground">{i + 1}. </span>
                  {step.text}
                </span>
              </li>
            );
          })}
        </ol>
        <div className="flex justify-end gap-2">
          <Button variant="outline" onClick={closeInstructions}>
            Close
          </Button>
          {hasNativePrompt && (
            <Button
              onClick={() => {
                void install();
                closeInstructions();
              }}
            >
              Install now
            </Button>
          )}
          {!hasNativePrompt && <Button onClick={closeInstructions}>Got it</Button>}
        </div>
      </div>
    </Modal>
  );
}
