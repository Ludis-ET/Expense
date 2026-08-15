/**
 * Request budgets.
 *
 * There were none. `POST /auth/login` accepted unlimited guesses against a
 * bcrypt hash, `POST /auth/register` accepted unlimited signups, and
 * `POST /ai/ask` would spend the user's own provider credit as fast as a
 * stolen session could ask for it.
 *
 * Three buckets, because the three failure modes are different: guessing a
 * password is per-credential, spending someone's API balance is per-account,
 * and everything else just needs a ceiling.
 */
import rateLimit, { ipKeyGenerator, type Options } from 'express-rate-limit';
import { isProd, isTest } from '../../config/env.js';

/** Shared shape: draft-8 headers, no legacy ones, one JSON error body. */
function make(opts: Pick<Options, 'windowMs' | 'limit'> & Partial<Options>) {
  return rateLimit({
    standardHeaders: 'draft-8',
    legacyHeaders: false,
    // The suite fires hundreds of requests from one address on purpose.
    skip: () => isTest,
    handler: (_req, res) => {
      res.status(429).json({
        error: {
          code: 'RATE_LIMITED',
          message: 'Too many requests. Wait a moment and try again.',
        },
      });
    },
    ...opts,
  });
}

/**
 * Credential endpoints, keyed by address *and* the email being tried.
 *
 * Keying on IP alone lets one attacker spread guesses across a botnet; keying
 * on email alone lets one attacker lock a victim out of their own account. The
 * pair costs an attacker both a new address and a new target to get a fresh
 * budget, and never locks a real user out from their own device.
 */
export const authLimiter = make({
  windowMs: 15 * 60 * 1000,
  limit: isProd ? 10 : 100,
  keyGenerator: (req) => {
    const email = typeof req.body?.email === 'string' ? req.body.email.toLowerCase() : '';
    // ipKeyGenerator normalises IPv6 to a /56 so a single host cannot rotate
    // through its own address space for a fresh budget each time.
    return `${ipKeyGenerator(req.ip ?? '')}:${email}`;
  },
});

/** Refresh is called legitimately on every cold start, so it gets more room. */
export const refreshLimiter = make({
  windowMs: 15 * 60 * 1000,
  limit: isProd ? 60 : 500,
});

/**
 * AI calls, keyed by user rather than address.
 *
 * The cost here lands on the user's own Anthropic or OpenAI key, so the budget
 * follows the account that pays for it - not the network it happens to be on.
 */
export const aiLimiter = make({
  windowMs: 60 * 1000,
  limit: isProd ? 20 : 200,
  keyGenerator: (req) => req.user?.id ?? ipKeyGenerator(req.ip ?? ''),
});

/** Everything else. High enough that normal use never sees it. */
export const globalLimiter = make({
  windowMs: 60 * 1000,
  limit: isProd ? 300 : 5000,
  keyGenerator: (req) => req.user?.id ?? ipKeyGenerator(req.ip ?? ''),
});
