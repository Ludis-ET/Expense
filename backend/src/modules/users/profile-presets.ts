/** Preset ids shared with the frontend catalog. Keep both lists in sync. */

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

export function isAvatarId(value: string): value is AvatarId {
  return (AVATAR_IDS as readonly string[]).includes(value);
}

export function isBannerId(value: string): value is BannerId {
  return (BANNER_IDS as readonly string[]).includes(value);
}

export function randomAvatarId(): AvatarId {
  return AVATAR_IDS[Math.floor(Math.random() * AVATAR_IDS.length)]!;
}

export function randomBannerId(): BannerId {
  return BANNER_IDS[Math.floor(Math.random() * BANNER_IDS.length)]!;
}

/** Deterministic pick for seeds / stable fixtures. */
export function pickAvatarId(seed: number): AvatarId {
  return AVATAR_IDS[Math.abs(seed) % AVATAR_IDS.length]!;
}

export function pickBannerId(seed: number): BannerId {
  return BANNER_IDS[Math.abs(seed) % BANNER_IDS.length]!;
}
