'use client';

import { useAuth } from '@/lib/auth';
import { formatDate } from '@/lib/format';
import { formatEthiopian } from '@/lib/ethiopian-calendar';

/**
 * Renders a date in the user's preferred calendar, with the alternate calendar
 * shown on hover. Defaults to Gregorian.
 */
export function CalendarDate({ value, className }: { value: string | Date | null | undefined; className?: string }) {
  const { user } = useAuth();
  if (!value) return <span className={className}>—</span>;

  const gregorian = formatDate(value);
  const ethiopian = formatEthiopian(value);
  const ethiopianPreferred = user?.calendar === 'ethiopian';

  const primary = ethiopianPreferred ? `${ethiopian} (Eth.)` : gregorian;
  const secondary = ethiopianPreferred ? gregorian : `${ethiopian} (Ethiopian)`;

  return (
    <span className={className} title={secondary}>
      {primary}
    </span>
  );
}
