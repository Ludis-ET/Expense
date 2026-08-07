import type { CSSProperties, ReactNode } from 'react';
import { cn } from '@/lib/utils';

/** Keep in sync with backend `profile-presets.ts`. */
export const AVATAR_IDS = [
  'ember',
  'lagoon',
  'meadow',
  'dusk',
  'citrus',
  'blush',
  'slate',
  'cocoa',
  'ocean',
  'sunrise',
  'mint',
  'berry',
] as const;

export const BANNER_IDS = [
  'aurora',
  'terrace',
  'monsoon',
  'savanna',
  'glacier',
  'dusk-wave',
  'citrus-mist',
  'rainforest',
  'coral-reef',
  'night-market',
] as const;

export type AvatarId = (typeof AVATAR_IDS)[number];
export type BannerId = (typeof BANNER_IDS)[number];

type AvatarPreset = {
  id: AvatarId;
  label: string;
  bg: string;
  art: ReactNode;
};

type BannerPreset = {
  id: BannerId;
  label: string;
  style: CSSProperties;
  art?: ReactNode;
};

function Face({
  skin,
  hair,
  accent,
  eyes = '#1e293b',
}: {
  skin: string;
  hair: string;
  accent: string;
  eyes?: string;
}) {
  return (
    <g>
      <circle cx="40" cy="44" r="22" fill={skin} />
      <path d={hair} fill={accent} />
      <circle cx="33" cy="42" r="2.2" fill={eyes} />
      <circle cx="47" cy="42" r="2.2" fill={eyes} />
      <path
        d="M34 50c2.5 3 9.5 3 12 0"
        fill="none"
        stroke={eyes}
        strokeWidth="1.6"
        strokeLinecap="round"
        opacity="0.55"
      />
    </g>
  );
}

export const AVATARS: AvatarPreset[] = [
  {
    id: 'ember',
    label: 'Ember',
    bg: 'linear-gradient(145deg,#fb923c 0%,#ef4444 55%,#9f1239 100%)',
    art: (
      <svg viewBox="0 0 80 80" className="h-full w-full" aria-hidden>
        <Face
          skin="#fecaca"
          hair="M18 38c2-16 14-26 22-26s20 10 22 26c-6-8-14-10-22-10s-16 2-22 10z"
          accent="#7f1d1d"
        />
        <circle cx="58" cy="22" r="6" fill="#fbbf24" opacity="0.85" />
      </svg>
    ),
  },
  {
    id: 'lagoon',
    label: 'Lagoon',
    bg: 'linear-gradient(145deg,#22d3ee 0%,#0ea5e9 50%,#0369a1 100%)',
    art: (
      <svg viewBox="0 0 80 80" className="h-full w-full" aria-hidden>
        <Face
          skin="#bae6fd"
          hair="M16 40c4-18 16-28 24-28s20 10 24 28c-7-6-14-8-24-8s-17 2-24 8z"
          accent="#0c4a6e"
        />
        <path d="M12 62c8-6 20-6 28 0s20 6 28 0" fill="none" stroke="#fff" strokeWidth="2" opacity="0.35" />
      </svg>
    ),
  },
  {
    id: 'meadow',
    label: 'Meadow',
    bg: 'linear-gradient(145deg,#86efac 0%,#22c55e 45%,#15803d 100%)',
    art: (
      <svg viewBox="0 0 80 80" className="h-full w-full" aria-hidden>
        <Face
          skin="#dcfce7"
          hair="M18 36c3-14 13-24 22-24s19 10 22 24c-6-7-13-9-22-9s-16 2-22 9z"
          accent="#14532d"
        />
        <circle cx="20" cy="58" r="4" fill="#fde047" />
        <circle cx="60" cy="56" r="3.5" fill="#fef08a" />
      </svg>
    ),
  },
  {
    id: 'dusk',
    label: 'Dusk',
    bg: 'linear-gradient(145deg,#a5b4fc 0%,#6366f1 50%,#312e81 100%)',
    art: (
      <svg viewBox="0 0 80 80" className="h-full w-full" aria-hidden>
        <Face
          skin="#e0e7ff"
          hair="M17 38c3-16 14-26 23-26s20 10 23 26c-7-8-14-10-23-10s-16 2-23 10z"
          accent="#1e1b4b"
        />
        <circle cx="62" cy="18" r="5" fill="#f8fafc" opacity="0.9" />
        <circle cx="54" cy="14" r="2" fill="#f8fafc" opacity="0.7" />
      </svg>
    ),
  },
  {
    id: 'citrus',
    label: 'Citrus',
    bg: 'linear-gradient(145deg,#fde047 0%,#f59e0b 55%,#d97706 100%)',
    art: (
      <svg viewBox="0 0 80 80" className="h-full w-full" aria-hidden>
        <Face
          skin="#fef3c7"
          hair="M18 37c3-15 13-25 22-25s19 10 22 25c-6-7-13-9-22-9s-16 2-22 9z"
          accent="#78350f"
        />
        <path d="M14 20h8l-4 8z" fill="#65a30d" />
      </svg>
    ),
  },
  {
    id: 'blush',
    label: 'Blush',
    bg: 'linear-gradient(145deg,#fda4af 0%,#f43f5e 50%,#be123c 100%)',
    art: (
      <svg viewBox="0 0 80 80" className="h-full w-full" aria-hidden>
        <Face
          skin="#ffe4e6"
          hair="M16 39c4-17 15-27 24-27s20 10 24 27c-7-7-14-9-24-9s-17 2-24 9z"
          accent="#881337"
        />
        <circle cx="28" cy="48" r="3" fill="#fb7185" opacity="0.55" />
        <circle cx="52" cy="48" r="3" fill="#fb7185" opacity="0.55" />
      </svg>
    ),
  },
  {
    id: 'slate',
    label: 'Slate',
    bg: 'linear-gradient(145deg,#94a3b8 0%,#475569 55%,#0f172a 100%)',
    art: (
      <svg viewBox="0 0 80 80" className="h-full w-full" aria-hidden>
        <Face
          skin="#e2e8f0"
          hair="M18 36c2-14 12-24 22-24s20 10 22 24c-6-6-13-8-22-8s-16 2-22 8z"
          accent="#020617"
          eyes="#0f172a"
        />
        <rect x="54" y="16" width="12" height="8" rx="2" fill="#38bdf8" opacity="0.8" />
      </svg>
    ),
  },
  {
    id: 'cocoa',
    label: 'Cocoa',
    bg: 'linear-gradient(145deg,#d6a57a 0%,#a16207 50%,#713f12 100%)',
    art: (
      <svg viewBox="0 0 80 80" className="h-full w-full" aria-hidden>
        <Face
          skin="#f5d0a9"
          hair="M15 40c5-18 16-28 25-28s20 10 25 28c-8-7-15-9-25-9s-17 2-25 9z"
          accent="#451a03"
        />
        <ellipse cx="40" cy="64" rx="18" ry="6" fill="#451a03" opacity="0.25" />
      </svg>
    ),
  },
  {
    id: 'ocean',
    label: 'Ocean',
    bg: 'linear-gradient(145deg,#38bdf8 0%,#2563eb 50%,#1e3a8a 100%)',
    art: (
      <svg viewBox="0 0 80 80" className="h-full w-full" aria-hidden>
        <Face
          skin="#bfdbfe"
          hair="M17 38c3-16 14-26 23-26s20 10 23 26c-7-8-14-10-23-10s-16 2-23 10z"
          accent="#172554"
        />
        <path d="M10 66c10-8 20-4 30-8s20-2 30 4" fill="none" stroke="#fff" strokeWidth="2.2" opacity="0.4" />
      </svg>
    ),
  },
  {
    id: 'sunrise',
    label: 'Sunrise',
    bg: 'linear-gradient(145deg,#fdba74 0%,#fb7185 45%,#c026d3 100%)',
    art: (
      <svg viewBox="0 0 80 80" className="h-full w-full" aria-hidden>
        <Face
          skin="#ffedd5"
          hair="M18 37c3-15 13-25 22-25s19 10 22 25c-6-7-13-9-22-9s-16 2-22 9z"
          accent="#701a75"
        />
        <circle cx="64" cy="20" r="8" fill="#fef08a" opacity="0.9" />
      </svg>
    ),
  },
  {
    id: 'mint',
    label: 'Mint',
    bg: 'linear-gradient(145deg,#5eead4 0%,#14b8a6 50%,#0f766e 100%)',
    art: (
      <svg viewBox="0 0 80 80" className="h-full w-full" aria-hidden>
        <Face
          skin="#ccfbf1"
          hair="M16 39c4-17 15-27 24-27s20 10 24 27c-7-7-14-9-24-9s-17 2-24 9z"
          accent="#134e4a"
        />
        <path d="M58 18c4 6 4 12 0 16-4-4-4-10 0-16z" fill="#99f6e4" />
      </svg>
    ),
  },
  {
    id: 'berry',
    label: 'Berry',
    bg: 'linear-gradient(145deg,#e879f9 0%,#c026d3 50%,#86198f 100%)',
    art: (
      <svg viewBox="0 0 80 80" className="h-full w-full" aria-hidden>
        <Face
          skin="#fae8ff"
          hair="M17 38c3-16 14-26 23-26s20 10 23 26c-7-8-14-10-23-10s-16 2-23 10z"
          accent="#4a044e"
        />
        <circle cx="18" cy="22" r="4" fill="#f0abfc" />
        <circle cx="24" cy="16" r="3" fill="#f5d0fe" />
      </svg>
    ),
  },
];

export const BANNERS: BannerPreset[] = [
  {
    id: 'aurora',
    label: 'Aurora',
    style: {
      background:
        'radial-gradient(ellipse 80% 60% at 20% 30%, rgba(52,211,153,0.55), transparent 55%), radial-gradient(ellipse 70% 50% at 80% 20%, rgba(56,189,248,0.45), transparent 50%), linear-gradient(120deg,#064e3b 0%,#0f766e 40%,#1e3a8a 100%)',
    },
  },
  {
    id: 'terrace',
    label: 'Terrace',
    style: {
      background: 'linear-gradient(160deg,#fef3c7 0%,#fdba74 35%,#ea580c 70%,#9a3412 100%)',
    },
    art: (
      <svg viewBox="0 0 400 120" className="absolute inset-0 h-full w-full" preserveAspectRatio="xMidYMid slice" aria-hidden>
        <path d="M0 90c40-20 80-10 120-25s80-5 120-20 80-10 160-5v80H0z" fill="rgba(255,255,255,0.12)" />
      </svg>
    ),
  },
  {
    id: 'monsoon',
    label: 'Monsoon',
    style: {
      background:
        'radial-gradient(circle at 70% 20%, rgba(125,211,252,0.4), transparent 40%), linear-gradient(145deg,#0c4a6e 0%,#075985 45%,#164e63 100%)',
    },
    art: (
      <svg viewBox="0 0 400 120" className="absolute inset-0 h-full w-full" preserveAspectRatio="xMidYMid slice" aria-hidden>
        {[40, 90, 150, 210, 280, 340].map((x) => (
          <line key={x} x1={x} y1="20" x2={x - 8} y2="100" stroke="rgba(186,230,253,0.35)" strokeWidth="2" />
        ))}
      </svg>
    ),
  },
  {
    id: 'savanna',
    label: 'Savanna',
    style: {
      background: 'linear-gradient(180deg,#fde68a 0%,#f59e0b 40%,#b45309 75%,#78350f 100%)',
    },
    art: (
      <svg viewBox="0 0 400 120" className="absolute inset-0 h-full w-full" preserveAspectRatio="xMidYMid slice" aria-hidden>
        <circle cx="320" cy="28" r="18" fill="rgba(254,243,199,0.85)" />
        <path d="M0 100c50-25 100-15 150-30s100-10 150-20 60-5 100 5v65H0z" fill="rgba(120,53,15,0.35)" />
      </svg>
    ),
  },
  {
    id: 'glacier',
    label: 'Glacier',
    style: {
      background:
        'radial-gradient(ellipse at 30% 80%, rgba(255,255,255,0.35), transparent 45%), linear-gradient(135deg,#e0f2fe 0%,#7dd3fc 40%,#0284c7 100%)',
    },
  },
  {
    id: 'dusk-wave',
    label: 'Dusk wave',
    style: {
      background:
        'radial-gradient(ellipse at 10% 0%, rgba(251,113,133,0.45), transparent 40%), linear-gradient(120deg,#312e81 0%,#6d28d9 45%,#db2777 100%)',
    },
  },
  {
    id: 'citrus-mist',
    label: 'Citrus mist',
    style: {
      background:
        'radial-gradient(circle at 85% 15%, rgba(254,240,138,0.7), transparent 35%), linear-gradient(125deg,#65a30d 0%,#16a34a 40%,#0f766e 100%)',
    },
  },
  {
    id: 'rainforest',
    label: 'Rainforest',
    style: {
      background: 'linear-gradient(160deg,#14532d 0%,#166534 35%,#047857 70%,#115e59 100%)',
    },
    art: (
      <svg viewBox="0 0 400 120" className="absolute inset-0 h-full w-full" preserveAspectRatio="xMidYMid slice" aria-hidden>
        <ellipse cx="60" cy="90" rx="40" ry="50" fill="rgba(34,197,94,0.35)" />
        <ellipse cx="130" cy="95" rx="35" ry="55" fill="rgba(21,128,61,0.4)" />
        <ellipse cx="340" cy="85" rx="45" ry="55" fill="rgba(20,83,45,0.45)" />
      </svg>
    ),
  },
  {
    id: 'coral-reef',
    label: 'Coral reef',
    style: {
      background:
        'radial-gradient(circle at 25% 70%, rgba(251,113,133,0.4), transparent 40%), linear-gradient(140deg,#155e75 0%,#0e7490 40%,#f472b6 100%)',
    },
  },
  {
    id: 'night-market',
    label: 'Night market',
    style: {
      background:
        'radial-gradient(circle at 20% 30%, rgba(251,191,36,0.35), transparent 30%), radial-gradient(circle at 70% 40%, rgba(248,113,113,0.3), transparent 28%), linear-gradient(150deg,#0f172a 0%,#1e293b 50%,#334155 100%)',
    },
    art: (
      <svg viewBox="0 0 400 120" className="absolute inset-0 h-full w-full" preserveAspectRatio="xMidYMid slice" aria-hidden>
        {[30, 70, 120, 180, 240, 300, 360].map((x, i) => (
          <circle key={x} cx={x} cy={18 + (i % 3) * 8} r={1.5 + (i % 2)} fill="rgba(254,243,199,0.8)" />
        ))}
      </svg>
    ),
  },
];

const avatarMap = Object.fromEntries(AVATARS.map((a) => [a.id, a])) as Record<AvatarId, AvatarPreset>;
const bannerMap = Object.fromEntries(BANNERS.map((b) => [b.id, b])) as Record<BannerId, BannerPreset>;

export function getAvatar(id?: string | null): AvatarPreset {
  if (id && id in avatarMap) return avatarMap[id as AvatarId];
  return avatarMap.ember;
}

export function getBanner(id?: string | null): BannerPreset {
  if (id && id in bannerMap) return bannerMap[id as BannerId];
  return bannerMap.aurora;
}

export function ProfileBanner({
  bannerId,
  className,
  children,
}: {
  bannerId?: string | null;
  className?: string;
  children?: ReactNode;
}) {
  const banner = getBanner(bannerId);
  return (
    <div className={cn('relative overflow-hidden', className)} style={banner.style}>
      {banner.art}
      <div className="absolute inset-0 bg-black/5" aria-hidden />
      {children}
    </div>
  );
}

export function AvatarArt({
  avatarId,
  className,
}: {
  avatarId?: string | null;
  className?: string;
}) {
  const avatar = getAvatar(avatarId);
  return (
    <div
      className={cn('relative overflow-hidden', className)}
      style={{ background: avatar.bg }}
      title={avatar.label}
    >
      {avatar.art}
    </div>
  );
}
