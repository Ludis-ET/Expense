import { describe, expect, it } from 'vitest';
import { registerSchema, loginSchema } from '../src/modules/auth/auth.schema.js';

describe('registerSchema', () => {
  it('accepts a valid new-org registration', () => {
    const parsed = registerSchema.parse({
      name: 'Test User',
      email: 'Test@Example.com',
      password: 'supersecret',
      orgName: 'My Lab',
    });
    expect(parsed.email).toBe('test@example.com'); // lowercased
    expect(parsed.locale).toBe('en'); // default
  });

  it('rejects when neither orgName nor orgId is provided', () => {
    const result = registerSchema.safeParse({
      name: 'Test User',
      email: 'test@example.com',
      password: 'supersecret',
    });
    expect(result.success).toBe(false);
  });

  it('rejects a short password', () => {
    const result = registerSchema.safeParse({
      name: 'Test User',
      email: 'test@example.com',
      password: 'short',
      orgName: 'My Lab',
    });
    expect(result.success).toBe(false);
  });
});

describe('loginSchema', () => {
  it('rejects an invalid email', () => {
    expect(loginSchema.safeParse({ email: 'nope', password: 'x' }).success).toBe(false);
  });
});
