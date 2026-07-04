// Gregorian ↔ Ethiopic (Amete Mihret) calendar conversion via Julian Day Number.
// The Ethiopian calendar has 13 months: 12 × 30 days + Pagume (5 or 6 days),
// and runs ~7–8 years behind the Gregorian calendar.

const ETHIOPIC_EPOCH = 1723856; // JDN of 1 Meskerem, year 1 (Amete Mihret)

const MONTHS = [
  'Meskerem',
  'Tikimt',
  'Hidar',
  'Tahsas',
  'Tir',
  'Yekatit',
  'Megabit',
  'Miazia',
  'Ginbot',
  'Sene',
  'Hamle',
  'Nehase',
  'Pagume',
];

const mod = (n: number, m: number) => ((n % m) + m) % m;

function gregorianToJDN(year: number, month: number, day: number): number {
  const a = Math.floor((14 - month) / 12);
  const y = year + 4800 - a;
  const m = month + 12 * a - 3;
  return (
    day +
    Math.floor((153 * m + 2) / 5) +
    365 * y +
    Math.floor(y / 4) -
    Math.floor(y / 100) +
    Math.floor(y / 400) -
    32045
  );
}

export interface EthiopianDate {
  year: number;
  month: number; // 1..13
  day: number; // 1..30
  monthName: string;
}

export function toEthiopian(date: Date): EthiopianDate {
  const jdn = gregorianToJDN(date.getFullYear(), date.getMonth() + 1, date.getDate());
  const r = mod(jdn - ETHIOPIC_EPOCH, 1461);
  const n = mod(r, 365) + 365 * Math.floor(r / 1460);
  const year = 4 * Math.floor((jdn - ETHIOPIC_EPOCH) / 1461) + Math.floor(r / 365) - Math.floor(r / 1460);
  const month = Math.floor(n / 30) + 1;
  const day = mod(n, 30) + 1;
  return { year, month, day, monthName: MONTHS[month - 1] ?? '' };
}

/** e.g. "15 Sene 2018" */
export function formatEthiopian(date: string | Date | null | undefined): string {
  if (!date) return '-';
  const e = toEthiopian(new Date(date));
  return `${e.day} ${e.monthName} ${e.year}`;
}
