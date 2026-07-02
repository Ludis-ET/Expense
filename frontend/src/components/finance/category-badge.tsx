'use client';

import { financeIcon } from './icons';
import { cn } from '@/lib/utils';

interface CategoryLike {
  name: string;
  icon?: string | null;
  color?: string | null;
}

/** Colored icon chip + name for a category (or account). */
export function CategoryBadge({ category, className }: { category: CategoryLike; className?: string }) {
  const Icon = financeIcon(category.icon);
  const color = category.color ?? '#64748b';
  return (
    <span className={cn('inline-flex items-center gap-1.5 text-sm', className)}>
      <span
        className="flex h-6 w-6 shrink-0 items-center justify-center rounded-md"
        style={{ backgroundColor: `${color}22`, color }}
      >
        <Icon className="h-3.5 w-3.5" />
      </span>
      {category.name}
    </span>
  );
}
