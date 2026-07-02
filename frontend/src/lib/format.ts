const CURRENCY_LOCALE: Record<string, string> = {
  ETB: 'am-ET',
  USD: 'en-US',
  EUR: 'en-IE',
  GBP: 'en-GB',
};

export function formatMoney(
  amount: number | string,
  currency = 'ETB',
  opts: { compact?: boolean; decimals?: boolean } = {},
): string {
  const value = typeof amount === 'string' ? Number(amount) : amount;
  try {
    return new Intl.NumberFormat(CURRENCY_LOCALE[currency] ?? 'en-US', {
      style: 'currency',
      currency,
      maximumFractionDigits: opts.decimals ? 2 : 0,
      ...(opts.compact ? { notation: 'compact' as const } : {}),
    }).format(value);
  } catch {
    return `${currency} ${value.toLocaleString()}`;
  }
}

/** "+ETB 500" in green contexts / "−ETB 500" in red — sign carried by the caller's styling. */
export function formatSignedMoney(amount: number | string, kind: 'INCOME' | 'EXPENSE' | 'TRANSFER', currency = 'ETB'): string {
  const formatted = formatMoney(amount, currency);
  if (kind === 'INCOME') return `+${formatted}`;
  if (kind === 'EXPENSE') return `−${formatted}`;
  return formatted;
}

/** "2026-07" → "July 2026". */
export function formatMonth(yyyyMm: string): string {
  const [y, m] = yyyyMm.split('-').map(Number);
  return new Intl.DateTimeFormat('en-GB', { month: 'long', year: 'numeric' }).format(new Date(Date.UTC(y, (m ?? 1) - 1, 1)));
}

export function formatDate(date: string | Date | null | undefined): string {
  if (!date) return '—';
  return new Intl.DateTimeFormat('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }).format(new Date(date));
}

export function relativeTime(date: string | Date): string {
  const d = new Date(date).getTime();
  const diff = d - Date.now();
  const abs = Math.abs(diff);
  const rtf = new Intl.RelativeTimeFormat('en', { numeric: 'auto' });
  const units: [Intl.RelativeTimeFormatUnit, number][] = [
    ['day', 86_400_000],
    ['hour', 3_600_000],
    ['minute', 60_000],
  ];
  for (const [unit, ms] of units) {
    if (abs >= ms || unit === 'minute') return rtf.format(Math.round(diff / ms), unit);
  }
  return 'just now';
}

export function initials(name: string): string {
  return name
    .split(' ')
    .map((p) => p[0])
    .filter(Boolean)
    .slice(0, 2)
    .join('')
    .toUpperCase();
}
