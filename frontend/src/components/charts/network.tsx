'use client';

import { useEffect, useRef, useState } from 'react';

interface GraphNode {
  id: string;
  label: string;
  type: 'member' | 'project';
  status?: string;
}
interface GraphLink {
  source: string;
  target: string;
}

interface Sim {
  x: number;
  y: number;
  vx: number;
  vy: number;
}

const W = 640;
const H = 440;

/** Lightweight force-directed graph: members ↔ projects they collaborate on. */
export function NetworkGraph({ nodes, links }: { nodes: GraphNode[]; links: GraphLink[] }) {
  const posRef = useRef<Map<string, Sim>>(new Map());
  const [, setTick] = useState(0);
  const rafRef = useRef<number>(0);

  useEffect(() => {
    const pos = new Map<string, Sim>();
    nodes.forEach((n, i) => {
      const angle = (i / Math.max(1, nodes.length)) * Math.PI * 2;
      pos.set(n.id, { x: W / 2 + Math.cos(angle) * 120, y: H / 2 + Math.sin(angle) * 120, vx: 0, vy: 0 });
    });
    posRef.current = pos;

    let iterations = 0;
    const step = () => {
      const p = posRef.current;
      // Repulsion between every pair of nodes.
      for (let i = 0; i < nodes.length; i++) {
        for (let j = i + 1; j < nodes.length; j++) {
          const a = p.get(nodes[i].id)!;
          const b = p.get(nodes[j].id)!;
          let dx = a.x - b.x;
          let dy = a.y - b.y;
          let d2 = dx * dx + dy * dy || 0.01;
          const f = 2600 / d2;
          const d = Math.sqrt(d2);
          dx /= d;
          dy /= d;
          a.vx += dx * f;
          a.vy += dy * f;
          b.vx -= dx * f;
          b.vy -= dy * f;
        }
      }
      // Spring attraction along links.
      for (const l of links) {
        const a = p.get(l.source);
        const b = p.get(l.target);
        if (!a || !b) continue;
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        const d = Math.sqrt(dx * dx + dy * dy) || 0.01;
        const f = (d - 90) * 0.02;
        const ux = dx / d;
        const uy = dy / d;
        a.vx += ux * f;
        a.vy += uy * f;
        b.vx -= ux * f;
        b.vy -= uy * f;
      }
      // Centering + damping + integrate.
      for (const n of nodes) {
        const s = p.get(n.id)!;
        s.vx += (W / 2 - s.x) * 0.005;
        s.vy += (H / 2 - s.y) * 0.005;
        s.vx *= 0.82;
        s.vy *= 0.82;
        s.x = Math.max(24, Math.min(W - 24, s.x + s.vx));
        s.y = Math.max(24, Math.min(H - 24, s.y + s.vy));
      }
      setTick((t) => t + 1);
      iterations += 1;
      if (iterations < 240) rafRef.current = requestAnimationFrame(step);
    };
    rafRef.current = requestAnimationFrame(step);
    return () => cancelAnimationFrame(rafRef.current);
  }, [nodes, links]);

  const pos = posRef.current;
  if (!nodes.length) return <p className="py-10 text-center text-sm text-muted">No members or projects yet.</p>;

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full">
      {links.map((l, i) => {
        const a = pos.get(l.source);
        const b = pos.get(l.target);
        if (!a || !b) return null;
        return <line key={i} x1={a.x} y1={a.y} x2={b.x} y2={b.y} stroke="var(--border)" strokeWidth={1.5} />;
      })}
      {nodes.map((n) => {
        const s = pos.get(n.id);
        if (!s) return null;
        const isMember = n.type === 'member';
        const r = isMember ? 9 : 13;
        return (
          <g key={n.id}>
            <circle
              cx={s.x}
              cy={s.y}
              r={r}
              fill={isMember ? 'var(--primary)' : 'var(--accent)'}
              stroke="var(--surface)"
              strokeWidth={2}
            />
            <text x={s.x} y={s.y + r + 11} textAnchor="middle" className="fill-foreground text-[10px]">
              {n.label.length > 18 ? n.label.slice(0, 17) + '…' : n.label}
            </text>
          </g>
        );
      })}
    </svg>
  );
}
