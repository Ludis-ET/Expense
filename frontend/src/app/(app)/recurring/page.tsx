'use client';

import { redirect } from 'next/navigation';

export default function RecurringRedirect() {
  redirect('/transactions?tab=recurring');
}
