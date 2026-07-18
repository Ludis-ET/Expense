'use client';

import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react';
import { useRouter } from 'next/navigation';
import { api, ApiError, tokens } from './api';
import type { AuthResponse, User } from './types';

const USER_KEY = 'rt.user';

/** Last-known user, cached so the app still opens offline. */
const cachedUser = {
  get(): User | null {
    if (typeof window === 'undefined') return null;
    try {
      const raw = localStorage.getItem(USER_KEY);
      return raw ? (JSON.parse(raw) as User) : null;
    } catch {
      return null;
    }
  },
  set(user: User) {
    try {
      localStorage.setItem(USER_KEY, JSON.stringify(user));
    } catch {
      /* ignore */
    }
  },
  clear() {
    try {
      localStorage.removeItem(USER_KEY);
    } catch {
      /* ignore */
    }
  },
};

interface AuthContextValue {
  user: User | null;
  loading: boolean;
  login: (email: string, password: string) => Promise<void>;
  register: (input: RegisterInput) => Promise<void>;
  logout: () => void;
  refreshUser: () => Promise<void>;
}

interface RegisterInput {
  name: string;
  email: string;
  password: string;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const router = useRouter();

  const loadUser = useCallback(async () => {
    if (!tokens.access) {
      cachedUser.clear();
      setUser(null);
      setLoading(false);
      return;
    }
    // Show the last-known user immediately so the app opens while offline.
    const cached = cachedUser.get();
    if (cached) setUser(cached);
    try {
      const fresh = await api.get<User>('/users/me');
      cachedUser.set(fresh);
      setUser(fresh);
    } catch (err) {
      // Only sign out on a real auth rejection — never just because we're offline.
      if (err instanceof ApiError && (err.status === 401 || err.status === 403)) {
        tokens.clear();
        cachedUser.clear();
        setUser(null);
      }
      // Network/offline error: keep whatever cached user we already have.
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadUser();
  }, [loadUser]);

  const handleAuth = useCallback((res: AuthResponse) => {
    tokens.set(res.accessToken, res.refreshToken);
  }, []);

  const login = useCallback(
    async (email: string, password: string) => {
      const res = await api.post<AuthResponse>('/auth/login', { email, password }, true);
      handleAuth(res);
      await loadUser();
      router.push('/dashboard');
    },
    [handleAuth, loadUser, router],
  );

  const register = useCallback(
    async (input: RegisterInput) => {
      const res = await api.post<AuthResponse>('/auth/register', input, true);
      handleAuth(res);
      await loadUser();
      router.push('/dashboard');
    },
    [handleAuth, loadUser, router],
  );

  const logout = useCallback(() => {
    tokens.clear();
    cachedUser.clear();
    setUser(null);
    try {
      sessionStorage.removeItem('santim-app-lock-unlocked');
    } catch {
      /* ignore */
    }
    router.push('/login');
  }, [router]);

  return (
    <AuthContext.Provider value={{ user, loading, login, register, logout, refreshUser: loadUser }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}
