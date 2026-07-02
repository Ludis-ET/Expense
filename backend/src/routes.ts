import { Router } from 'express';
import { authRouter } from './modules/auth/auth.router.js';
import { usersRouter } from './modules/users/users.router.js';
import { projectsRouter } from './modules/projects/projects.router.js';
import { budgetRouter } from './modules/budget/budget.router.js';
import { ideasRouter } from './modules/ideas/ideas.router.js';
import { notificationsRouter } from './modules/notifications/notifications.router.js';
import { dashboardRouter } from './modules/dashboard/dashboard.router.js';
import { milestonesRouter } from './modules/milestones/milestones.router.js';
import { aiRouter } from './modules/ai/ai.router.js';
import { invitationsRouter } from './modules/invitations/invitations.router.js';
import { insightsRouter } from './modules/insights/insights.router.js';

/** All API routes are mounted under /api/v1 (see app.ts). */
export const apiRouter = Router();

apiRouter.use('/auth', authRouter);
apiRouter.use('/users', usersRouter);
apiRouter.use('/projects', projectsRouter);
apiRouter.use('/milestones', milestonesRouter);
apiRouter.use('/ideas', ideasRouter);
apiRouter.use('/notifications', notificationsRouter);
apiRouter.use('/dashboard', dashboardRouter);
apiRouter.use('/ai', aiRouter);
apiRouter.use('/invitations', invitationsRouter);
apiRouter.use('/insights', insightsRouter);
// Budget routes define their own /projects/:id/budget and /budget paths.
apiRouter.use('/', budgetRouter);
