import { Router } from 'express';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { requireDevice } from '../../core/middleware/device-auth.js';
import { validate } from '../../core/middleware/validate.js';
import {
  confirmInboxSchema,
  inboxIdParam,
  ingestBatchSchema,
  listInboxQuery,
  previewSchema,
  senderRuleIdParam,
  upsertSenderRuleSchema,
} from './ingest.schema.js';
import * as ingest from './ingest.service.js';

export const ingestRouter = Router();

// --- phone-authenticated ----------------------------------------------------
// The only two routes a device token can reach. Everything else needs a real
// login, so a stolen phone token can add messages but cannot read the ledger.

ingestRouter.post(
  '/sms',
  requireDevice,
  validate({ body: ingestBatchSchema }),
  asyncHandler(async (req, res) => {
    res.status(202).json(await ingest.ingestBatch(req.user!, req.device!.id, req.body));
  }),
);

/** Lets the phone refresh its local sender allowlist without a user session. */
ingestRouter.get(
  '/manifest',
  requireDevice,
  asyncHandler(async (req, res) => {
    res.json(await ingest.syncManifest(req.user!));
  }),
);

// --- user-authenticated -----------------------------------------------------

ingestRouter.get(
  '/banks',
  requireAuth,
  asyncHandler(async (_req, res) => {
    res.json(ingest.listBanks());
  }),
);

ingestRouter.post(
  '/preview',
  requireAuth,
  validate({ body: previewSchema }),
  asyncHandler(async (req, res) => {
    res.json(ingest.preview(req.body.sender, req.body.body));
  }),
);

ingestRouter.get(
  '/inbox',
  requireAuth,
  validate({ query: listInboxQuery }),
  asyncHandler(async (req, res) => {
    res.json(await ingest.listInbox(req.user!, req.query as never));
  }),
);

ingestRouter.get(
  '/inbox/stats',
  requireAuth,
  asyncHandler(async (req, res) => {
    res.json(await ingest.inboxStats(req.user!));
  }),
);

ingestRouter.post(
  '/inbox/reparse',
  requireAuth,
  asyncHandler(async (req, res) => {
    res.json(await ingest.reparse(req.user!));
  }),
);

ingestRouter.get(
  '/inbox/:id',
  requireAuth,
  validate({ params: inboxIdParam }),
  asyncHandler(async (req, res) => {
    res.json(await ingest.getInboxMessage(req.user!, req.params.id!));
  }),
);

ingestRouter.post(
  '/inbox/:id/confirm',
  requireAuth,
  validate({ params: inboxIdParam, body: confirmInboxSchema }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await ingest.confirm(req.user!, req.params.id!, req.body));
  }),
);

ingestRouter.post(
  '/inbox/:id/reject',
  requireAuth,
  validate({ params: inboxIdParam }),
  asyncHandler(async (req, res) => {
    res.json(await ingest.reject(req.user!, req.params.id!));
  }),
);

ingestRouter.delete(
  '/inbox/:id',
  requireAuth,
  validate({ params: inboxIdParam }),
  asyncHandler(async (req, res) => {
    await ingest.remove(req.user!, req.params.id!);
    res.status(204).end();
  }),
);

ingestRouter.get(
  '/senders',
  requireAuth,
  asyncHandler(async (req, res) => {
    res.json(await ingest.listSenderRules(req.user!));
  }),
);

ingestRouter.put(
  '/senders',
  requireAuth,
  validate({ body: upsertSenderRuleSchema }),
  asyncHandler(async (req, res) => {
    res.json(await ingest.upsertSenderRule(req.user!, req.body));
  }),
);

ingestRouter.delete(
  '/senders/:id',
  requireAuth,
  validate({ params: senderRuleIdParam }),
  asyncHandler(async (req, res) => {
    await ingest.deleteSenderRule(req.user!, req.params.id!);
    res.status(204).end();
  }),
);
