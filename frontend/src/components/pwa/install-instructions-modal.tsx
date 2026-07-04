'use client';

import { Download, Share, Smartphone } from 'lucide-react';
import { Modal } from '@/components/ui/modal';
import { Button } from '@/components/ui/button';
import { usePwaInstall } from '@/lib/pwa-install-context';

export function InstallInstructionsModal() {
  const { instructionsOpen, closeInstructions, platform } = usePwaInstall();

  const steps =
    platform === 'ios'
      ? [
          { icon: Share, text: 'Tap the Share button in Safari (square with arrow).' },
          { icon: Smartphone, text: 'Scroll down and tap "Add to Home Screen".' },
          { icon: Download, text: 'Tap Add - Santim will appear on your home screen like an app.' },
        ]
      : platform === 'android'
        ? [
            { icon: Download, text: 'Open the Chrome menu (three dots, top right).' },
            { icon: Smartphone, text: 'Tap "Install app" or "Add to Home screen".' },
            { icon: Download, text: 'Confirm - Santim opens full screen from your home screen.' },
          ]
        : [
            { icon: Download, text: 'Open your browser menu.' },
            { icon: Smartphone, text: 'Look for "Install app" or "Add to Home screen".' },
            { icon: Download, text: 'Add Santim to your home screen for quick access.' },
          ];

  return (
    <Modal open={instructionsOpen} onClose={closeInstructions} title="Download Santim app">
      <div className="space-y-4">
        <p className="text-sm text-muted">
          Install Santim on your phone for a full-screen app experience, faster access, and your balances one tap away.
        </p>
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
        <div className="flex justify-end">
          <Button onClick={closeInstructions}>Got it</Button>
        </div>
      </div>
    </Modal>
  );
}
