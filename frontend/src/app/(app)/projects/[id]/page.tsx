'use client';

import { use, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import useSWR from 'swr';
import { toast } from 'sonner';
import { ArrowLeft, Trash2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { StatusBadge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/misc';
import { api, ApiError } from '@/lib/api';
import { formatDate } from '@/lib/format';
import type { ProjectDetail } from '@/lib/types';
import { OverviewTab } from './overview-tab';
import { TeamTab } from './team-tab';
import { BudgetTab } from './budget-tab';
import { MilestonesTab } from './milestones-tab';

const TABS = ['Overview', 'Team', 'Budget', 'Milestones'] as const;
type Tab = (typeof TABS)[number];

export default function ProjectDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const router = useRouter();
  const [tab, setTab] = useState<Tab>('Overview');
  const { data: project, isLoading, mutate } = useSWR<ProjectDetail>(`/projects/${id}`);

  async function deleteProject() {
    if (!confirm('Delete this project and all its data? This cannot be undone.')) return;
    try {
      await api.del(`/projects/${id}`);
      toast.success('Project deleted');
      router.push('/projects');
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to delete');
    }
  }

  if (isLoading) {
    return (
      <div className="space-y-4">
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-64 w-full" />
      </div>
    );
  }

  if (!project) {
    return (
      <div className="flex flex-col items-center py-20 text-center">
        <p className="text-muted">Project not found.</p>
        <Link href="/projects" className="mt-3 text-primary hover:underline">
          Back to projects
        </Link>
      </div>
    );
  }

  return (
    <div>
      <Link href="/projects" className="mb-4 inline-flex items-center gap-1.5 text-sm text-muted hover:text-foreground">
        <ArrowLeft className="h-4 w-4" /> Projects
      </Link>

      <div className="mb-6 flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="flex items-center gap-3">
            <h1 className="text-2xl font-bold tracking-tight">{project.title}</h1>
            <StatusBadge.Project status={project.status} />
          </div>
          <p className="mt-1 text-sm text-muted">
            {project.lead ? `Led by ${project.lead.name}` : 'No lead assigned'} ·{' '}
            {project.startDate ? `Started ${formatDate(project.startDate)}` : 'Not started'}
          </p>
        </div>
        <Button variant="outline" size="sm" onClick={deleteProject} className="text-danger">
          <Trash2 className="h-4 w-4" /> Delete
        </Button>
      </div>

      {/* Tabs */}
      <div className="mb-6 flex gap-1 border-b border-border">
        {TABS.map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`relative px-4 py-2.5 text-sm font-medium transition-colors ${
              tab === t ? 'text-primary' : 'text-muted hover:text-foreground'
            }`}
          >
            {t}
            {tab === t && <span className="absolute inset-x-2 -bottom-px h-0.5 rounded-full bg-primary" />}
          </button>
        ))}
      </div>

      <div className="animate-in">
        {tab === 'Overview' && <OverviewTab project={project} onChange={mutate} />}
        {tab === 'Team' && <TeamTab project={project} onChange={mutate} />}
        {tab === 'Budget' && <BudgetTab projectId={project.id} currency={project.currency} />}
        {tab === 'Milestones' && <MilestonesTab project={project} onChange={mutate} />}
      </div>
    </div>
  );
}
