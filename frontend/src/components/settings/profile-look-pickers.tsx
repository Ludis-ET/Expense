'use client';

import { Check } from 'lucide-react';
import { AVATARS, BANNERS, ProfileBanner, type AvatarId, type BannerId } from '@/lib/profile-presets';
import { cn } from '@/lib/utils';

export function AvatarPicker({
  value,
  onChange,
}: {
  value: string;
  onChange: (id: AvatarId) => void;
}) {
  return (
    <div className="grid grid-cols-4 gap-2 sm:grid-cols-6">
      {AVATARS.map((avatar) => {
        const selected = value === avatar.id;
        return (
          <button
            key={avatar.id}
            type="button"
            onClick={() => onChange(avatar.id)}
            aria-label={avatar.label}
            aria-pressed={selected}
            className={cn(
              'group relative aspect-square overflow-hidden rounded-2xl border-2 transition-all',
              selected
                ? 'border-primary ring-2 ring-primary/25 scale-[1.02]'
                : 'border-transparent hover:border-border hover:scale-[1.02]',
            )}
            style={{ background: avatar.bg }}
          >
            <div className="absolute inset-0">{avatar.art}</div>
            {selected && (
              <span className="absolute right-1 top-1 flex h-5 w-5 items-center justify-center rounded-full bg-primary text-primary-foreground shadow">
                <Check className="h-3 w-3" />
              </span>
            )}
            <span className="pointer-events-none absolute inset-x-0 bottom-0 bg-black/40 px-1 py-0.5 text-center text-[10px] font-medium text-white opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100">
              {avatar.label}
            </span>
          </button>
        );
      })}
    </div>
  );
}

export function BannerPicker({
  value,
  onChange,
}: {
  value: string;
  onChange: (id: BannerId) => void;
}) {
  return (
    <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-5">
      {BANNERS.map((banner) => {
        const selected = value === banner.id;
        return (
          <button
            key={banner.id}
            type="button"
            onClick={() => onChange(banner.id)}
            aria-label={banner.label}
            aria-pressed={selected}
            className={cn(
              'relative h-14 overflow-hidden rounded-xl border-2 transition-all sm:h-16',
              selected
                ? 'border-primary ring-2 ring-primary/25'
                : 'border-transparent hover:border-border',
            )}
          >
            <ProfileBanner bannerId={banner.id} className="absolute inset-0" />
            {selected && (
              <span className="absolute right-1.5 top-1.5 flex h-5 w-5 items-center justify-center rounded-full bg-primary text-primary-foreground shadow">
                <Check className="h-3 w-3" />
              </span>
            )}
            <span className="absolute inset-x-0 bottom-0 bg-black/30 px-1.5 py-0.5 text-[10px] font-medium text-white">
              {banner.label}
            </span>
          </button>
        );
      })}
    </div>
  );
}
