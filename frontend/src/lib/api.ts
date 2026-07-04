function apiBase(): string {
  if (process.env.NEXT_PUBLIC_API_BASE) return process.env.NEXT_PUBLIC_API_BASE;
  if (typeof window !== 'undefined') {
    const { hostname, pathname } = window.location;
    if (hostname !== 'localhost' && hostname !== '127.0.0.1') {
      if (pathname.startsWith('/frontend')) return '/backend/api/v1';
      return '/backend/api/v1';
    }
  }
  return '/api/v1';
}

const TOKEN_KEY = 'rt.accessToken';
const REFRESH_KEY = 'rt.refreshToken';

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
    public code?: string,
    public details?: unknown,
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

// --- Token storage (localStorage, browser only) ---
export const tokens = {
  get access() {
    return typeof window === 'undefined' ? null : localStorage.getItem(TOKEN_KEY);
  },
  get refresh() {
    return typeof window === 'undefined' ? null : localStorage.getItem(REFRESH_KEY);
  },
  set(access: string, refresh: string) {
    localStorage.setItem(TOKEN_KEY, access);
    localStorage.setItem(REFRESH_KEY, refresh);
  },
  clear() {
    localStorage.removeItem(TOKEN_KEY);
    localStorage.removeItem(REFRESH_KEY);
  },
};

interface RequestOptions {
  method?: string;
  body?: unknown;
  /** When true, a 401 will not trigger a refresh attempt (used by auth calls). */
  skipAuth?: boolean;
}

async function request<T>(path: string, opts: RequestOptions = {}, isRetry = false): Promise<T> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  const token = tokens.access;
  if (token && !opts.skipAuth) headers.Authorization = `Bearer ${token}`;

  const res = await fetch(`${apiBase()}${path}`, {
    method: opts.method ?? 'GET',
    headers,
    body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined,
  });

  // Transparently refresh once on a 401, then retry the original request.
  if (res.status === 401 && !opts.skipAuth && !isRetry && tokens.refresh) {
    const refreshed = await tryRefresh();
    if (refreshed) return request<T>(path, opts, true);
    tokens.clear();
  }

  if (res.status === 204) return undefined as T;

  const data = await res.json().catch(() => null);
  if (!res.ok) {
    const err = data?.error;
    throw new ApiError(res.status, err?.message ?? res.statusText, err?.code, err?.details);
  }
  return data as T;
}

async function tryRefresh(): Promise<boolean> {
  try {
    const res = await fetch(`${apiBase()}/auth/refresh`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refreshToken: tokens.refresh }),
    });
    if (!res.ok) return false;
    const data = await res.json();
    tokens.set(data.accessToken, data.refreshToken);
    return true;
  } catch {
    return false;
  }
}

export const api = {
  get: <T>(path: string) => request<T>(path),
  post: <T>(path: string, body?: unknown, skipAuth = false) => request<T>(path, { method: 'POST', body, skipAuth }),
  put: <T>(path: string, body?: unknown) => request<T>(path, { method: 'PUT', body }),
  patch: <T>(path: string, body?: unknown) => request<T>(path, { method: 'PATCH', body }),
  del: <T>(path: string) => request<T>(path, { method: 'DELETE' }),
};

/** SWR fetcher. */
export const fetcher = <T>(path: string) => api.get<T>(path);
