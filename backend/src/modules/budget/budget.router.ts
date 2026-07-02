import { Router } from 'express';
import { Role } from '@prisma/client';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { requireRole } from '../../core/middleware/rbac.js';
import { validate } from '../../core/middleware/validate.js';
import {
  budgetItemIdParam,
  createBudgetItemSchema,
  createExpenseSchema,
  expenseDecisionSchema,
  expenseIdParam,
  projectIdParam,
  updateBudgetItemSchema,
} from './budget.schema.js';
import * as budget from './budget.service.js';

export const budgetRouter = Router();

budgetRouter.use(requireAuth);

// --- Org-wide portfolio overview ---

budgetRouter.get(
  '/budget-overview',
  asyncHandler(async (req, res) => {
    res.json(await budget.orgOverview(req.user!));
  }),
);

// --- Budget items (scoped under a project) ---

budgetRouter.get(
  '/projects/:projectId/budget',
  validate({ params: projectIdParam }),
  asyncHandler(async (req, res) => {
    res.json(await budget.listBudget(req.user!, req.params.projectId));
  }),
);

budgetRouter.post(
  '/projects/:projectId/budget',
  requireRole(Role.ADMIN, Role.PROJECT_LEAD, Role.FINANCE_OFFICER),
  validate({ params: projectIdParam, body: createBudgetItemSchema }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await budget.createBudgetItem(req.user!, req.params.projectId, req.body));
  }),
);

budgetRouter.put(
  '/budget/:budgetItemId',
  requireRole(Role.ADMIN, Role.PROJECT_LEAD, Role.FINANCE_OFFICER),
  validate({ params: budgetItemIdParam, body: updateBudgetItemSchema }),
  asyncHandler(async (req, res) => {
    res.json(await budget.updateBudgetItem(req.user!, req.params.budgetItemId, req.body));
  }),
);

budgetRouter.delete(
  '/budget/:budgetItemId',
  requireRole(Role.ADMIN, Role.PROJECT_LEAD, Role.FINANCE_OFFICER),
  validate({ params: budgetItemIdParam }),
  asyncHandler(async (req, res) => {
    await budget.deleteBudgetItem(req.user!, req.params.budgetItemId);
    res.status(204).end();
  }),
);

// --- Expenses ---

// Any project member can submit an expense; approval is gated below.
budgetRouter.post(
  '/budget/:budgetItemId/expenses',
  validate({ params: budgetItemIdParam, body: createExpenseSchema }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await budget.submitExpense(req.user!, req.params.budgetItemId, req.body));
  }),
);

budgetRouter.post(
  '/expenses/:expenseId/decision',
  requireRole(Role.ADMIN, Role.FINANCE_OFFICER, Role.PROJECT_LEAD),
  validate({ params: expenseIdParam, body: expenseDecisionSchema }),
  asyncHandler(async (req, res) => {
    res.json(await budget.decideExpense(req.user!, req.params.expenseId, req.body.decision));
  }),
);
