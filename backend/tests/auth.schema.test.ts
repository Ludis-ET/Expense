import { describe, expect, it } from 'vitest';
import { registerSchema, loginSchema } from '../src/modules/auth/auth.schema.js';

describe('registerSchema', () => {
  it('accepts a valid registration', () => {
    const parsed = registerSchema.parse({
      name: 'Test User',
      email: 'Test@Example.com',
      password: 'supersecret',
    });
    expect(parsed.email).toBe('test@example.com'); // lowercased
    expect(parsed.locale).toBe('en'); // default
  });

  it('rejects a short password', () => {
    const result = registerSchema.safeParse({
      name: 'Test User',
      email: 'test@example.com',
      password: 'short',
    });
    expect(result.success).toBe(false);
  });

  it('rejects an invalid email', () => {
    const result = registerSchema.safeParse({
      name: 'Test User',
      email: 'not-an-email',
      password: 'supersecret',
    });
    expect(result.success).toBe(false);
  });

  it('accepts an explicit locale', () => {
    const parsed = registerSchema.parse({
      name: 'Test User',
      email: 'test@example.com',
      password: 'supersecret',
      locale: 'am',
    });
    expect(parsed.locale).toBe('am');
  });
});

describe('loginSchema', () => {
  it('accepts valid credentials and lowercases the email', () => {
    const parsed = loginSchema.parse({ email: 'A@B.com', password: 'x' });
    expect(parsed.email).toBe('a@b.com');
  });

  it('rejects an invalid email', () => {
    expect(loginSchema.safeParse({ email: 'nope', password: 'x' }).success).toBe(false);
  });

  it('rejects an empty password', () => {
    expect(loginSchema.safeParse({ email: 'a@b.com', password: '' }).success).toBe(false);
  });
});
