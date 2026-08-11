"use client";

import { useCallback, useEffect, useMemo, useState } from "react";

/**
 * Where the Android build lives.
 *
 * The APK is not on Google Play - `RECEIVE_SMS` is restricted to a short list
 * of approved use cases that expense tracking is not on - so it is served
 * directly. Drop the file at `frontend/public/downloads/santim.apk`, or point
 * `NEXT_PUBLIC_ANDROID_APP_URL` at wherever you host it.
 */
export const ANDROID_APP = {
  url: process.env.NEXT_PUBLIC_ANDROID_APP_URL ?? "/downloads/santim.apk",
  version: process.env.NEXT_PUBLIC_ANDROID_APP_VERSION ?? "1.0.0",
  size: process.env.NEXT_PUBLIC_ANDROID_APP_SIZE ?? "",
} as const;

/** Rotating pitches. All of them sell the one thing the web app cannot do. */
export const AD_PITCHES = [
  {
    id: "typing",
    headline: "Stop typing your transactions",
    body: "Your bank already texts you every purchase. Santim reads those messages and files them for you.",
  },
  {
    id: "banks",
    headline: "CBE, telebirr, Awash   read automatically",
    body: "Pick which senders are your banks. Every alert they send becomes a transaction waiting for one tap.",
  },
  {
    id: "swipe",
    headline: "A whole month in about a minute",
    body: "Swipe right to record, left to skip. Your ledger fills itself while you flick through.",
  },
  {
    id: "atm",
    headline: "Cash from the ATM is not spending",
    body: "Santim knows the difference and moves it into your cash wallet instead of counting it twice.",
  },
  {
    id: "offline",
    headline: "Works with no signal",
    body: "Messages queue on your phone and upload themselves once you are back online. Nothing gets lost.",
  },
] as const;

export type AdPitch = (typeof AD_PITCHES)[number];

const KEY_DISMISSED = "santim-appad-dismissed";
const KEY_COUNT = "santim-appad-count";
const KEY_LAST = "santim-appad-last";

/**
 * Frequency caps. An ad the user cannot get rid of is worse than no ad, so:
 * at most once per page load, a handful of times ever, and never again once
 * it has been turned down or acted on.
 */
const MAX_LIFETIME_SHOWS = 4;
const MIN_HOURS_BETWEEN = 6;
const DELAY_MIN_MS = 20_000;
const DELAY_MAX_MS = 55_000;

function read(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function write(key: string, value: string) {
  try {
    localStorage.setItem(key, value);
  } catch {
    /* private mode - the ad just reverts to session-only behaviour */
  }
}

export function isAndroid(): boolean {
  if (typeof navigator === "undefined") return false;
  return /Android/i.test(navigator.userAgent);
}

/**
 * Decides whether and when to surface the app ad, and which pitch to use.
 *
 * Only Android sees it: handing an APK to someone on an iPhone or a desktop is
 * useless, and those users are better served by the existing add-to-home-screen
 * path.
 */
export function useAppAd() {
  const [visible, setVisible] = useState(false);
  const [pitch, setPitch] = useState<AdPitch>(AD_PITCHES[0]);

  useEffect(() => {
    if (!isAndroid()) return;
    if (read(KEY_DISMISSED) === "1") return;

    const shown = Number(read(KEY_COUNT) ?? "0");
    if (shown >= MAX_LIFETIME_SHOWS) return;

    const last = Number(read(KEY_LAST) ?? "0");
    if (last && Date.now() - last < MIN_HOURS_BETWEEN * 3_600_000) return;

    // Random pitch and random delay, so a returning user does not get the
    // same ad at the same moment every visit.
    const chosen = AD_PITCHES[Math.floor(Math.random() * AD_PITCHES.length)]!;
    const delay = DELAY_MIN_MS + Math.random() * (DELAY_MAX_MS - DELAY_MIN_MS);

    const timer = window.setTimeout(() => {
      setPitch(chosen);
      setVisible(true);
      write(KEY_COUNT, String(shown + 1));
      write(KEY_LAST, String(Date.now()));
    }, delay);

    return () => window.clearTimeout(timer);
  }, []);

  const close = useCallback(() => setVisible(false), []);

  /** "Don't show again" and "I downloaded it" both mean: stop asking. */
  const dismissForever = useCallback(() => {
    write(KEY_DISMISSED, "1");
    setVisible(false);
  }, []);

  return useMemo(
    () => ({ visible, pitch, close, dismissForever }),
    [visible, pitch, close, dismissForever],
  );
}
