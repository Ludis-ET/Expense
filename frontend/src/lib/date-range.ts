export type DatePreset = '7d' | '30d' | '90d' | '6m' | '1y' | 'ytd' | 'all' | 'custom';

export interface DateRange {
  from: Date;
  to: Date;
  preset: DatePreset;
}

const startOfDay = (d: Date) => {
  const x = new Date(d);
  x.setHours(0, 0, 0, 0);
  return x;
};

const endOfDay = (d: Date) => {
  const x = new Date(d);
  x.setHours(23, 59, 59, 999);
  return x;
};

export function rangeFromPreset(preset: DatePreset, customFrom?: string, customTo?: string): DateRange {
  const to = endOfDay(new Date());
  const from = startOfDay(new Date());

  switch (preset) {
    case '7d':
      from.setDate(from.getDate() - 6);
      break;
    case '30d':
      from.setDate(from.getDate() - 29);
      break;
    case '90d':
      from.setDate(from.getDate() - 89);
      break;
    case '6m':
      from.setMonth(from.getMonth() - 6);
      break;
    case '1y':
      from.setFullYear(from.getFullYear() - 1);
      break;
    case 'ytd':
      from.setMonth(0, 1);
      break;
    case 'all':
      from.setFullYear(2020, 0, 1);
      break;
    case 'custom':
      if (customFrom) {
        const f = new Date(customFrom);
        if (!Number.isNaN(f.getTime())) return { from: startOfDay(f), to: customTo ? endOfDay(new Date(customTo)) : to, preset };
      }
      from.setDate(from.getDate() - 29);
      break;
  }

  return { from, to, preset };
};

export function toApiQuery(range: Pick<DateRange, 'from' | 'to'>) {
  const f = range.from.toISOString().slice(0, 10);
  const t = range.to.toISOString().slice(0, 10);
  return `from=${f}&to=${t}`;
}

/**
 * Today as the user's calendar sees it, formatted for `<input type="date">`.
 *
 * Slicing an ISO string gives the UTC date, not the local one. East of
 * Greenwich the two disagree for the first hours of every day: at 01:00 in
 * Addis it is still yesterday in UTC, so every date field in the app opened
 * pre-filled with the wrong day until 03:00.
 */
export function todayInputValue(now = new Date()): string {
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, '0');
  const d = String(now.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

export function presetLabel(preset: DatePreset): string {
  const labels: Record<DatePreset, string> = {
    '7d': '7 days',
    '30d': '30 days',
    '90d': '90 days',
    '6m': '6 months',
    '1y': '1 year',
    ytd: 'Year to date',
    all: 'All time',
    custom: 'Custom',
  };
  return labels[preset];
}

export function formatRangeLabel(from: Date, to: Date): string {
  const fmt = (d: Date) =>
    d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: d.getFullYear() !== to.getFullYear() ? 'numeric' : undefined });
  return `${fmt(from)} – ${fmt(to)}`;
}
