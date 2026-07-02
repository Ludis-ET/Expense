import { Fragment, type ReactNode } from 'react';

// Inline: **bold**, *italic*, `code`. React escapes text, so this is XSS-safe.
function inline(text: string): ReactNode[] {
  const tokens = text.split(/(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`)/g).filter(Boolean);
  return tokens.map((t, i) => {
    if (t.startsWith('**') && t.endsWith('**')) return <strong key={i}>{t.slice(2, -2)}</strong>;
    if (t.startsWith('*') && t.endsWith('*')) return <em key={i}>{t.slice(1, -1)}</em>;
    if (t.startsWith('`') && t.endsWith('`'))
      return (
        <code key={i} className="rounded bg-surface-muted px-1 py-0.5 text-[0.85em]">
          {t.slice(1, -1)}
        </code>
      );
    return <Fragment key={i}>{t}</Fragment>;
  });
}

const cells = (row: string) =>
  row
    .replace(/^\||\|$/g, '')
    .split('|')
    .map((c) => c.trim());

/** Minimal GitHub-flavoured Markdown renderer (headings, lists, tables, quotes). */
export function Markdown({ content }: { content: string }) {
  const lines = content.replace(/\r\n/g, '\n').split('\n');
  const blocks: ReactNode[] = [];
  let i = 0;
  let key = 0;

  while (i < lines.length) {
    const line = lines[i];

    if (!line.trim()) {
      i++;
      continue;
    }

    // Headings
    const h = /^(#{1,4})\s+(.*)$/.exec(line);
    if (h) {
      const level = h[1].length;
      const cls = ['text-2xl font-bold mt-6 mb-3', 'text-xl font-bold mt-6 mb-2', 'text-lg font-semibold mt-5 mb-2', 'text-base font-semibold mt-4 mb-1'][level - 1];
      blocks.push(
        <p key={key++} className={cls}>
          {inline(h[2])}
        </p>,
      );
      i++;
      continue;
    }

    // Horizontal rule
    if (/^---+$/.test(line.trim())) {
      blocks.push(<hr key={key++} className="my-5 border-border" />);
      i++;
      continue;
    }

    // Table
    if (line.includes('|') && i + 1 < lines.length && /^\s*\|?[-:\s|]+\|?\s*$/.test(lines[i + 1])) {
      const header = cells(line);
      i += 2;
      const rows: string[][] = [];
      while (i < lines.length && lines[i].includes('|')) {
        rows.push(cells(lines[i]));
        i++;
      }
      blocks.push(
        <div key={key++} className="my-4 overflow-x-auto">
          <table className="w-full border-collapse text-sm">
            <thead>
              <tr className="border-b border-border text-left">
                {header.map((c, j) => (
                  <th key={j} className="px-3 py-2 font-semibold">
                    {inline(c)}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((r, ri) => (
                <tr key={ri} className="border-b border-border last:border-0">
                  {r.map((c, ci) => (
                    <td key={ci} className="px-3 py-2">
                      {inline(c)}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>,
      );
      continue;
    }

    // Blockquote
    if (line.startsWith('>')) {
      blocks.push(
        <blockquote key={key++} className="my-3 border-l-2 border-primary pl-4 text-muted">
          {inline(line.replace(/^>\s?/, ''))}
        </blockquote>,
      );
      i++;
      continue;
    }

    // Unordered list
    if (/^\s*[-*]\s+/.test(line)) {
      const items: string[] = [];
      while (i < lines.length && /^\s*[-*]\s+/.test(lines[i])) {
        items.push(lines[i].replace(/^\s*[-*]\s+/, ''));
        i++;
      }
      blocks.push(
        <ul key={key++} className="my-3 list-disc space-y-1 pl-5">
          {items.map((it, j) => (
            <li key={j}>{inline(it)}</li>
          ))}
        </ul>,
      );
      continue;
    }

    // Ordered list
    if (/^\s*\d+\.\s+/.test(line)) {
      const items: string[] = [];
      while (i < lines.length && /^\s*\d+\.\s+/.test(lines[i])) {
        items.push(lines[i].replace(/^\s*\d+\.\s+/, ''));
        i++;
      }
      blocks.push(
        <ol key={key++} className="my-3 list-decimal space-y-1 pl-5">
          {items.map((it, j) => (
            <li key={j}>{inline(it)}</li>
          ))}
        </ol>,
      );
      continue;
    }

    // Paragraph
    blocks.push(
      <p key={key++} className="my-2 leading-relaxed">
        {inline(line)}
      </p>,
    );
    i++;
  }

  return <div className="text-sm">{blocks}</div>;
}
