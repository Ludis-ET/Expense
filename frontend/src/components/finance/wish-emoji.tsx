'use client';

import { useMemo, useState } from 'react';
import { Search } from 'lucide-react';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';

/**
 * A browsable emoji set for wants, grouped so the picker stays scannable.
 * Keywords are what the search box matches on, so "car" finds the bus too.
 */
export const EMOJI_GROUPS: { label: string; items: { e: string; k: string }[] }[] = [
  {
    label: 'Tech',
    items: [
      { e: '📱', k: 'phone mobile iphone' },
      { e: '💻', k: 'laptop computer macbook' },
      { e: '🖥️', k: 'desktop monitor pc screen' },
      { e: '⌨️', k: 'keyboard' },
      { e: '🖱️', k: 'mouse' },
      { e: '🎧', k: 'headphones audio music' },
      { e: '🎮', k: 'game console controller' },
      { e: '📷', k: 'camera photo' },
      { e: '📹', k: 'camcorder video' },
      { e: '⌚', k: 'watch smartwatch' },
      { e: '🖨️', k: 'printer' },
      { e: '🔌', k: 'charger cable power' },
      { e: '🔋', k: 'battery powerbank' },
      { e: '💾', k: 'storage disk drive' },
      { e: '📺', k: 'tv television' },
      { e: '🔊', k: 'speaker sound' },
      { e: '🛜', k: 'wifi internet router' },
      { e: '🤖', k: 'robot ai gadget' },
    ],
  },
  {
    label: 'Travel',
    items: [
      { e: '✈️', k: 'flight plane travel trip' },
      { e: '🏝️', k: 'island beach holiday' },
      { e: '🏔️', k: 'mountain hiking' },
      { e: '🗺️', k: 'map travel' },
      { e: '🧳', k: 'luggage suitcase' },
      { e: '🎒', k: 'backpack bag' },
      { e: '🏕️', k: 'camping tent' },
      { e: '🛳️', k: 'cruise ship boat' },
      { e: '🚗', k: 'car vehicle' },
      { e: '🏍️', k: 'motorbike motorcycle' },
      { e: '🚲', k: 'bike bicycle cycle' },
      { e: '🛵', k: 'scooter moped' },
      { e: '🚌', k: 'bus transport' },
      { e: '🚂', k: 'train rail' },
      { e: '⛽', k: 'fuel petrol gas' },
      { e: '🧭', k: 'compass adventure' },
      { e: '🛂', k: 'passport visa' },
      { e: '🏨', k: 'hotel stay' },
    ],
  },
  {
    label: 'Home',
    items: [
      { e: '🏠', k: 'house home' },
      { e: '🛋️', k: 'sofa couch furniture' },
      { e: '🛏️', k: 'bed mattress' },
      { e: '🪑', k: 'chair desk furniture' },
      { e: '🚿', k: 'shower bathroom' },
      { e: '🧺', k: 'laundry washing' },
      { e: '🧹', k: 'cleaning broom' },
      { e: '🪴', k: 'plant garden' },
      { e: '🕯️', k: 'candle decor' },
      { e: '🖼️', k: 'art frame decor' },
      { e: '🔑', k: 'keys rent deposit' },
      { e: '🧰', k: 'tools diy repair' },
      { e: '🪟', k: 'window' },
      { e: '🚪', k: 'door' },
      { e: '❄️', k: 'ac fridge cooling' },
      { e: '🔥', k: 'heater stove' },
    ],
  },
  {
    label: 'Style',
    items: [
      { e: '👟', k: 'shoes sneakers trainers' },
      { e: '👞', k: 'shoes formal' },
      { e: '👗', k: 'dress clothes' },
      { e: '👕', k: 'shirt tshirt clothes' },
      { e: '👖', k: 'jeans trousers' },
      { e: '🧥', k: 'jacket coat' },
      { e: '🧢', k: 'cap hat' },
      { e: '👜', k: 'handbag purse' },
      { e: '🕶️', k: 'sunglasses' },
      { e: '💍', k: 'ring jewellery' },
      { e: '⌚', k: 'watch' },
      { e: '💄', k: 'makeup beauty' },
      { e: '💇', k: 'haircut salon' },
      { e: '🧴', k: 'skincare lotion' },
      { e: '🧦', k: 'socks' },
      { e: '🧣', k: 'scarf' },
    ],
  },
  {
    label: 'Life',
    items: [
      { e: '📚', k: 'books reading study' },
      { e: '🎓', k: 'education course degree' },
      { e: '🎸', k: 'guitar music instrument' },
      { e: '🎹', k: 'piano keyboard music' },
      { e: '🥁', k: 'drums music' },
      { e: '🎨', k: 'art painting hobby' },
      { e: '🏋️', k: 'gym fitness weights' },
      { e: '⚽', k: 'football sport' },
      { e: '🏀', k: 'basketball sport' },
      { e: '🎾', k: 'tennis sport' },
      { e: '🧘', k: 'yoga wellness' },
      { e: '🚴', k: 'cycling sport' },
      { e: '🎬', k: 'cinema movie film' },
      { e: '🎤', k: 'concert singing music' },
      { e: '🎟️', k: 'ticket event' },
      { e: '🐕', k: 'dog pet' },
      { e: '🐈', k: 'cat pet' },
      { e: '🌱', k: 'growth plant' },
    ],
  },
  {
    label: 'Money',
    items: [
      { e: '💰', k: 'money savings cash' },
      { e: '🏦', k: 'bank' },
      { e: '💳', k: 'card payment' },
      { e: '🧾', k: 'bill receipt invoice' },
      { e: '📈', k: 'invest growth stocks' },
      { e: '🛡️', k: 'insurance safety emergency' },
      { e: '🎁', k: 'gift present' },
      { e: '💝', k: 'gift love donation' },
      { e: '🤝', k: 'wedding family support' },
      { e: '👶', k: 'baby child' },
      { e: '🏥', k: 'health medical hospital' },
      { e: '💊', k: 'medicine pharmacy' },
    ],
  },
  {
    label: 'Food',
    items: [
      { e: '☕', k: 'coffee cafe' },
      { e: '🍔', k: 'burger food fastfood' },
      { e: '🍕', k: 'pizza food' },
      { e: '🍜', k: 'noodles food' },
      { e: '🍰', k: 'cake dessert' },
      { e: '🍫', k: 'chocolate treat' },
      { e: '🥂', k: 'celebration drinks' },
      { e: '🍽️', k: 'restaurant dining' },
      { e: '🛒', k: 'groceries shopping' },
      { e: '🥗', k: 'salad healthy' },
    ],
  },
  {
    label: 'Other',
    items: [
      { e: '✨', k: 'sparkle wish default' },
      { e: '⭐', k: 'star favourite' },
      { e: '❤️', k: 'love heart' },
      { e: '🔮', k: 'someday dream future' },
      { e: '🏆', k: 'trophy goal win' },
      { e: '🎯', k: 'target goal' },
      { e: '🚀', k: 'rocket launch ambition' },
      { e: '🌍', k: 'world global' },
      { e: '🧩', k: 'puzzle hobby' },
      { e: '📦', k: 'package delivery box' },
    ],
  },
];

const ALL = EMOJI_GROUPS.flatMap((g) => g.items.map((i) => ({ ...i, group: g.label })));

export const DEFAULT_WISH_EMOJI = '✨';

/** Searchable, grouped emoji picker. */
export function WishEmojiPicker({
  value,
  onChange,
}: {
  value: string;
  onChange: (emoji: string) => void;
}) {
  const [q, setQ] = useState('');
  const term = q.trim().toLowerCase();

  const groups = useMemo(() => {
    if (!term) return EMOJI_GROUPS;
    const hits = ALL.filter((i) => i.k.includes(term) || i.e === term);
    if (hits.length === 0) return [];
    return [{ label: `${hits.length} match${hits.length === 1 ? '' : 'es'}`, items: hits }];
  }, [term]);

  return (
    <div className="rounded-xl border border-border">
      <div className="relative border-b border-border p-2">
        <Search className="pointer-events-none absolute left-4 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted" />
        <Input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="Search emoji: phone, trip, gym…"
          className="h-9 pl-8 text-xs"
          aria-label="Search emoji"
        />
      </div>

      <div className="max-h-52 overflow-y-auto p-2">
        {groups.length === 0 ? (
          <p className="px-1 py-6 text-center text-xs text-muted">
            No emoji matches &quot;{q}&quot;.
          </p>
        ) : (
          groups.map((g) => (
            <div key={g.label} className="mb-2 last:mb-0">
              <p className="mb-1 px-1 text-[10px] font-semibold uppercase tracking-widest text-muted">
                {g.label}
              </p>
              <div className="flex flex-wrap gap-1">
                {g.items.map((i, idx) => (
                  <button
                    key={`${i.e}-${idx}`}
                    type="button"
                    title={i.k.split(' ')[0]}
                    onClick={() => onChange(i.e)}
                    className={cn(
                      'flex h-9 w-9 items-center justify-center rounded-lg text-lg transition-all hover:scale-110',
                      value === i.e
                        ? 'bg-primary/15 ring-2 ring-primary'
                        : 'bg-surface-muted hover:bg-surface-muted/70',
                    )}
                  >
                    {i.e}
                  </button>
                ))}
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
