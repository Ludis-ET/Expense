'use client';

import { redirect } from 'next/navigation';

export default function AssistantRedirect() {
  redirect('/dashboard?assistant=1');
}
