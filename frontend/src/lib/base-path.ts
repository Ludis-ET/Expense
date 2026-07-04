/** Path prefix when hosted under e.g. /frontend on cPanel. Empty locally. */
export const BASE_PATH = process.env.NEXT_PUBLIC_BASE_PATH ?? process.env.NEXT_BASE_PATH ?? '';

export function withBase(path: string): string {
  const base = BASE_PATH.replace(/\/$/, '');
  const normalized = path.startsWith('/') ? path : `/${path}`;
  return `${base}${normalized}` || '/';
}
