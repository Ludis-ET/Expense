import type { RequestHandler } from 'express';
import { UnauthorizedError } from '../errors.js';
import { authenticateToken } from '../../modules/devices/devices.service.js';

/**
 * Authenticates a paired phone via `X-Device-Token` (or `Authorization: Device
 * <token>`) and populates both `req.device` and `req.user`.
 *
 * The companion app's upload worker runs headless, hours after the user last
 * opened the app, so it cannot walk a 15-minute JWT's refresh dance. A
 * long-lived, individually revocable device token is the right credential for
 * that job - and it is deliberately scoped to the ingest routes only.
 */
export const requireDevice: RequestHandler = (req, _res, next) => {
  const header = req.headers['x-device-token'];
  const fromHeader = Array.isArray(header) ? header[0] : header;
  const auth = req.headers.authorization;
  const fromAuth = auth?.startsWith('Device ') ? auth.slice('Device '.length) : undefined;

  const token = (fromHeader ?? fromAuth)?.trim();
  if (!token) throw new UnauthorizedError('Missing device token');

  authenticateToken(token)
    .then(({ device, user }) => {
      req.device = { id: device.id, name: device.name };
      req.user = user;
      next();
    })
    .catch(next);
};
