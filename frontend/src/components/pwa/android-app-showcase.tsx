"use client";

import { useEffect, useState } from "react";
import {
  Banknote,
  Download,
  Hand,
  MessageSquareText,
  Smartphone,
  WifiOff,
  type LucideIcon,
} from "lucide-react";
import { ANDROID_APP, isAndroid } from "@/lib/android-app";

/**
 * Landing-page section for the Android build.
 *
 * Given its own block rather than a bullet in the feature grid because it is
 * the one thing the web app structurally cannot do - a browser has no access
 * to SMS on any platform.
 */
export function AndroidAppShowcase() {
  const [android, setAndroid] = useState(false);
  useEffect(() => setAndroid(isAndroid()), []);

  return (
    <section
      id="android"
      className="relative overflow-hidden border-y border-border/70 bg-surface/40"
    >
      <div
        aria-hidden
        className="pointer-events-none absolute -left-24 top-1/2 h-72 w-72 -translate-y-1/2 rounded-full bg-primary/15 blur-[120px]"
      />

      <div className="relative mx-auto grid max-w-6xl items-center gap-12 px-5 py-20 md:grid-cols-2 md:py-24">
        <div>
          <div className="inline-flex items-center gap-2 rounded-full border border-primary/25 bg-primary/10 px-3.5 py-1.5 text-xs font-semibold text-primary">
            <Smartphone className="h-3.5 w-3.5" />
            Android app
          </div>

          <h2 className="mt-5 text-3xl font-bold leading-tight tracking-tight md:text-4xl">
            Your bank already texts you.{" "}
            <span className="bg-gradient-to-r from-emerald-500 to-teal-500 bg-clip-text text-transparent">
              Let it do the typing.
            </span>
          </h2>

          <p className="mt-4 max-w-lg text-base text-muted">
            Every time CBE, telebirr, Awash or Dashen sends you an alert, Santim
            reads the amount out of it and puts a draft transaction in your
            inbox. Swipe right to record it. That is the whole workflow.
          </p>

          <ul className="mt-7 space-y-3.5">
            <Point icon={MessageSquareText}>
              Reads only the senders you approve everything else is discarded on
              your phone
            </Point>
            <Point icon={Hand}>
              Swipe through a month of messages in about a minute
            </Point>
            <Point icon={Banknote}>
              Knows an ATM withdrawal is not spending it moves to your cash
              wallet
            </Point>
            <Point icon={WifiOff}>
              Queues offline and uploads itself when signal comes back
            </Point>
          </ul>

          <div className="mt-8 flex flex-wrap items-center gap-3">
            <a
              href={ANDROID_APP.url}
              download
              className="inline-flex h-11 items-center justify-center gap-2 rounded-xl bg-primary px-6 text-base font-medium text-primary-foreground shadow-sm shadow-primary/25 transition-all hover:brightness-110 active:scale-[0.98]"
            >
              <Download className="h-4 w-4" aria-hidden />
              Download for Android
            </a>
            <span className="text-xs text-muted">
              v{ANDROID_APP.version}
              {ANDROID_APP.size ? ` · ${ANDROID_APP.size}` : ""}
              {!android && " · Android only"}
            </span>
          </div>

          {/* Said plainly rather than buried: people are right to be wary of an
              APK from a website, and the reason it is not on Play is legitimate. */}
          <p className="mt-4 max-w-lg text-xs leading-relaxed text-muted">
            Not on Google Play Google restricts SMS access to a short list of
            approved app types, and expense trackers are not on it. You will
            need to allow installs from your browser once.
          </p>
        </div>

        <PhoneMock />
      </div>
    </section>
  );
}

function Point({
  icon: Icon,
  children,
}: {
  icon: LucideIcon;
  children: React.ReactNode;
}) {
  return (
    <li className="flex items-start gap-3">
      <span className="mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-lg bg-primary/12 text-primary">
        <Icon className="h-3.5 w-3.5" aria-hidden />
      </span>
      <span className="text-sm text-muted">{children}</span>
    </li>
  );
}

/**
 * A mocked-up review card. Static markup rather than a screenshot so it stays
 * sharp on any display, themes correctly, and never goes stale against the UI.
 */
function PhoneMock() {
  return (
    <div className="relative mx-auto w-full max-w-[290px]">
      <div className="rounded-[2.2rem] border-[7px] border-foreground/85 bg-background p-3 shadow-2xl">
        <div className="mx-auto mb-3 h-1 w-16 rounded-full bg-foreground/20" />

        <div className="space-y-3">
          <div className="flex items-center justify-between text-[10px] text-muted">
            <span>3 to review</span>
            <span>Skip</span>
          </div>
          <div className="h-1 overflow-hidden rounded-full bg-surface-muted">
            <div className="h-full w-1/3 rounded-full bg-primary" />
          </div>

          <div className="rounded-2xl border border-border bg-surface p-3.5 shadow-sm">
            <div className="flex items-center gap-2">
              <span className="flex h-7 w-7 items-center justify-center rounded-lg bg-danger/12 text-danger">
                <MessageSquareText className="h-3.5 w-3.5" aria-hidden />
              </span>
              <div className="min-w-0">
                <p className="truncate text-[11px] font-semibold">
                  Commercial Bank of Ethiopia
                </p>
                <p className="text-[10px] text-muted">2m ago</p>
              </div>
            </div>

            <p className="mt-3 text-2xl font-extrabold text-danger">
              <span className="text-sm font-semibold opacity-70">Br </span>
              249.00
            </p>

            <div className="mt-3 space-y-1.5">
              <MockField label="Account" value="CBE" />
              <MockField label="What was it for" value="Food &amp; Groceries" />
            </div>

            <div className="mt-3 rounded-lg bg-surface-muted/60 p-2 text-[9px] leading-relaxed text-muted">
              Your account has been debited with ETB 249.00 at SHOA SUPERMARKET…
            </div>
          </div>

          <div className="flex gap-2">
            <div className="flex-1 rounded-xl border border-danger/40 py-2 text-center text-[11px] font-medium text-danger">
              Skip
            </div>
            <div className="flex-[2] rounded-xl bg-primary py-2 text-center text-[11px] font-medium text-primary-foreground">
              Record
            </div>
          </div>
        </div>
      </div>

      <div className="pointer-events-none absolute -right-3 top-16 rotate-[8deg] rounded-lg border-2 border-emerald-500 px-2 py-0.5 text-[10px] font-black tracking-wider text-emerald-500">
        RECORD
      </div>
    </div>
  );
}

function MockField({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg bg-surface-muted/50 px-2.5 py-1.5">
      <p className="text-[8px] uppercase tracking-wide text-muted">{label}</p>
      <p className="text-[11px] font-semibold">{value}</p>
    </div>
  );
}
