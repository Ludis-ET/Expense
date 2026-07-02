export type Role = 'ADMIN' | 'PROJECT_LEAD' | 'RESEARCHER' | 'REVIEWER' | 'FUNDER' | 'FINANCE_OFFICER';
export type ProjectStatus = 'PLANNING' | 'ACTIVE' | 'ON_HOLD' | 'COMPLETED' | 'CANCELLED';
export type TeamRole = 'PI' | 'CO_PI' | 'COLLABORATOR' | 'REVIEWER';
export type MilestoneStatus = 'PENDING' | 'IN_PROGRESS' | 'DONE';
export type ExpenseStatus = 'PENDING' | 'APPROVED' | 'REJECTED';
export type IdeaStatus = 'OPEN' | 'CONVERTED' | 'CLOSED';

export interface User {
  id: string;
  name: string;
  email: string;
  role: Role;
  locale?: string;
  calendar?: 'gregorian' | 'ethiopian';
  orcidId?: string | null;
  orgId: string;
  org?: { name: string };
}

export interface AuthResponse {
  user: { id: string; email: string; role: Role; orgId: string };
  accessToken: string;
  refreshToken: string;
}

export interface Project {
  id: string;
  title: string;
  summary?: string | null;
  status: ProjectStatus;
  currency: string;
  startDate?: string | null;
  endDate?: string | null;
  leadUserId?: string | null;
  updatedAt: string;
  _count?: { team: number; milestones: number; budgetItems: number };
}

export interface TeamMember {
  projectId: string;
  userId: string;
  role: TeamRole;
  user: { id: string; name: string; email: string };
}

export interface Milestone {
  id: string;
  description: string;
  dueDate?: string | null;
  status: MilestoneStatus;
  completedDate?: string | null;
}

export interface ProjectDetail extends Project {
  lead?: { id: string; name: string; email: string } | null;
  team: TeamMember[];
  milestones: Milestone[];
  budgetItems: BudgetItem[];
}

export interface BudgetItem {
  id: string;
  category: string;
  plannedAmount: string;
  currency: string;
  notes?: string | null;
}

export interface Expense {
  id: string;
  amount: string;
  currency: string;
  date: string;
  description?: string | null;
  status: ExpenseStatus;
  user?: { id: string; name: string };
}

export interface BudgetSummaryItem extends BudgetItem {
  spent: string;
  pending: string;
  remaining: string;
  expenses: Expense[];
}

export interface BudgetSummary {
  items: BudgetSummaryItem[];
  totalPlanned: string;
}

export interface Idea {
  id: string;
  title: string;
  description?: string | null;
  priority: number;
  status: IdeaStatus;
  createdAt: string;
  user: { id: string; name: string };
  project?: { id: string; title: string } | null;
}

export interface Notification {
  id: string;
  type: string;
  message: string;
  link?: string | null;
  readFlag: boolean;
  createdAt: string;
}

export interface DashboardStats {
  counts: { projects: number; publications: number; datasets: number; openIdeas: number; pendingExpenses: number };
  projectsByStatus: { status: ProjectStatus; count: number }[];
  budget: { totalPlanned: string; totalSpent: string; utilization: number };
  recentProjects: Pick<Project, 'id' | 'title' | 'status' | 'currency' | 'updatedAt'>[];
  upcomingMilestones: (Milestone & { project: { id: string; title: string } })[];
}
