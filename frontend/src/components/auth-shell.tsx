import { Brand } from '@/components/brand';
import { ThemeToggle } from '@/components/theme-toggle';

export function AuthShell({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex min-h-screen">
      {/* Left brand panel */}
      <div className="relative hidden w-1/2 overflow-hidden bg-gradient-to-br from-emerald-600 via-primary to-teal-600 lg:block">
        <div className="absolute inset-0 bg-grid opacity-20" />
        <div className="relative flex h-full flex-col justify-between p-12 text-white">
          <Brand className="[&_span]:text-white [&_.text-primary]:text-white" />
          <div>
            <h2 className="max-w-sm text-3xl font-bold leading-snug">
              Know where every birr goes.
            </h2>
            <p className="mt-4 max-w-sm text-white/80">
              Track income and spending, set budgets, save towards goals, and get insights - all private to you.
            </p>
          </div>
          <p className="text-sm text-white/70">© {new Date().getFullYear()} Santim</p>
        </div>
      </div>

      {/* Right form panel */}
      <div className="relative flex w-full flex-col items-center justify-center px-5 py-10 lg:w-1/2">
        <div className="absolute right-5 top-5">
          <ThemeToggle />
        </div>
        <div className="w-full max-w-sm animate-in">
          <div className="mb-8 lg:hidden">
            <Brand />
          </div>
          <h1 className="text-2xl font-bold tracking-tight">{title}</h1>
          <p className="mt-1 text-sm text-muted">{subtitle}</p>
          <div className="mt-8">{children}</div>
        </div>
      </div>
    </div>
  );
}
