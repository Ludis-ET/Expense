"use client";

import {
  Children,
  Fragment,
  isValidElement,
  useEffect,
  useId,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type KeyboardEvent,
  type ReactNode,
  type SelectHTMLAttributes,
} from "react";
import { createPortal } from "react-dom";
import { Check, ChevronDown } from "lucide-react";
import { cn } from "@/lib/utils";

export interface SelectOption {
  value: string;
  label: ReactNode;
  disabled?: boolean;
  /** Heading this option sits under. Set automatically from <optgroup label>. */
  group?: string;
}

/**
 * Flatten `<option>` children into options, descending into `<optgroup>` and
 * carrying its label down so the menu can render headings. Fragments are
 * walked too, so conditional lists behave.
 */
export function optionsFromChildren(children: ReactNode, group?: string): SelectOption[] {
  const out: SelectOption[] = [];
  Children.forEach(children, (child) => {
    if (
      !isValidElement<{
        value?: string | number;
        disabled?: boolean;
        label?: string;
        children?: ReactNode;
      }>(child)
    )
      return;

    if (child.type === "optgroup") {
      out.push(...optionsFromChildren(child.props.children, child.props.label));
      return;
    }
    // Fragments and arrays: keep walking without changing the group.
    if (typeof child.type !== "string" && !("value" in (child.props ?? {}))) {
      out.push(...optionsFromChildren(child.props?.children, group));
      return;
    }
    if (typeof child.type === "string" && child.type !== "option") return;

    if (child.type === "option" || (child.props && "value" in child.props)) {
      out.push({
        value: String(child.props.value ?? ""),
        label: child.props.children,
        disabled: !!child.props.disabled,
        group,
      });
    }
  });
  return out;
}

type SelectChangeEvent = { target: { value: string } };

interface SelectProps extends Omit<
  SelectHTMLAttributes<HTMLSelectElement>,
  "onChange" | "value"
> {
  value?: string;
  onChange?: (e: SelectChangeEvent) => void;
  options?: SelectOption[];
  placeholder?: string;
  /** `ghost`   minimal chrome for dense headers */
  variant?: "default" | "ghost";
  /** Show a shimmer skeleton instead of the trigger while backend data loads. */
  loading?: boolean;
}

/**
 * Custom select   same usage as native <Select><option/></Select>,
 * with a polished popover menu instead of the OS dropdown.
 */
export function Select({
  className,
  children,
  value = "",
  onChange,
  options: optionsProp,
  disabled,
  required,
  id,
  name,
  placeholder,
  "aria-label": ariaLabel,
  variant = "default",
  loading = false,
}: SelectProps) {
  const generatedId = useId();
  const selectId = id ?? generatedId;
  const rootRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const listRef = useRef<HTMLUListElement>(null);
  const [open, setOpen] = useState(false);
  const [activeIndex, setActiveIndex] = useState(0);
  const [menuStyle, setMenuStyle] = useState<CSSProperties>({});
  const [mounted, setMounted] = useState(false);

  useEffect(() => setMounted(true), []);

  const options = useMemo(
    () => (optionsProp?.length ? optionsProp : optionsFromChildren(children)),
    [optionsProp, children],
  );

  const selected = options.find((o) => o.value === value);
  const display =
    selected?.label ??
    placeholder ??
    (options[0] && options[0].value === "" ? options[0].label : null) ??
    "Select…";

  useLayoutEffect(() => {
    if (!open || !triggerRef.current) return;
    const update = () => {
      const rect = triggerRef.current!.getBoundingClientRect();
      const spaceBelow = window.innerHeight - rect.bottom;
      const openUp = spaceBelow < 240 && rect.top > spaceBelow;
      setMenuStyle({
        position: "fixed",
        left: rect.left,
        width: Math.max(rect.width, 160),
        zIndex: 100,
        ...(openUp
          ? {
              bottom: window.innerHeight - rect.top + 6,
              maxHeight: Math.min(240, rect.top - 12),
            }
          : {
              top: rect.bottom + 6,
              maxHeight: Math.min(240, spaceBelow - 12),
            }),
      });
    };
    update();
    window.addEventListener("resize", update);
    window.addEventListener("scroll", update, true);
    return () => {
      window.removeEventListener("resize", update);
      window.removeEventListener("scroll", update, true);
    };
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const idx = Math.max(
      0,
      options.findIndex((o) => o.value === value && !o.disabled),
    );
    setActiveIndex(idx);
    const onDoc = (e: MouseEvent) => {
      const t = e.target as Node;
      if (rootRef.current?.contains(t) || listRef.current?.contains(t)) return;
      setOpen(false);
    };
    const onKey = (e: globalThis.KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    document.addEventListener("mousedown", onDoc);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDoc);
      document.removeEventListener("keydown", onKey);
    };
  }, [open, options, value]);

  useEffect(() => {
    if (!open || !listRef.current) return;
    const list = listRef.current;
    const el = list.querySelector<HTMLElement>(`[data-index="${activeIndex}"]`);
    if (!el) return;
    const top = el.offsetTop;
    const bottom = top + el.offsetHeight;
    const viewTop = list.scrollTop;
    const viewBottom = viewTop + list.clientHeight;
    if (top < viewTop) {
      list.scrollTop = Math.max(0, top - 6);
    } else if (bottom > viewBottom) {
      list.scrollTop = Math.max(0, bottom - list.clientHeight + 6);
    }
  }, [activeIndex, open]);

  function commit(next: string) {
    onChange?.({ target: { value: next } });
    setOpen(false);
  }

  function onTriggerKey(e: KeyboardEvent) {
    if (disabled) return;
    if (e.key === "ArrowDown" || e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      setOpen(true);
    }
  }

  function onListKey(e: KeyboardEvent) {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setActiveIndex((i) => {
        let n = i;
        for (let s = 0; s < options.length; s++) {
          n = (n + 1) % options.length;
          if (!options[n]?.disabled) return n;
        }
        return i;
      });
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setActiveIndex((i) => {
        let n = i;
        for (let s = 0; s < options.length; s++) {
          n = (n - 1 + options.length) % options.length;
          if (!options[n]?.disabled) return n;
        }
        return i;
      });
    } else if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      const opt = options[activeIndex];
      if (opt && !opt.disabled) commit(opt.value);
    } else if (e.key === "Escape") {
      e.preventDefault();
      setOpen(false);
    }
  }

  const menu =
    open && mounted
      ? createPortal(
          <ul
            ref={listRef}
            id={`${selectId}-list`}
            role="listbox"
            tabIndex={-1}
            onKeyDown={onListKey}
            style={menuStyle}
            className={cn(
              "overflow-auto rounded-xl border border-border bg-surface p-1.5",
              "origin-top animate-in",
            )}
          >
            {options.length === 0 ? (
              <li className="px-3 py-2 text-sm text-muted">No options</li>
            ) : (
              options.map((opt, i) => {
                const isSelected = opt.value === value;
                const isActive = i === activeIndex;
                // A heading whenever the group changes, so grouped menus read
                // like the native <optgroup> they came from.
                const startsGroup = !!opt.group && opt.group !== options[i - 1]?.group;
                return (
                  <Fragment key={`${opt.value}-${i}`}>
                    {startsGroup && (
                      <li
                        role="presentation"
                        className={cn(
                          "px-3 pb-1 text-[10px] font-semibold uppercase tracking-widest text-muted",
                          i > 0 && "mt-1 border-t border-border pt-2",
                        )}
                      >
                        {opt.group}
                      </li>
                    )}
                    <li
                      role="option"
                      aria-selected={isSelected}
                      data-index={i}
                      aria-disabled={opt.disabled || undefined}
                      className={cn(
                        "flex cursor-pointer items-center gap-2 rounded-lg px-3 py-2 text-sm transition-colors",
                        opt.disabled && "pointer-events-none opacity-40",
                        isSelected && "bg-primary/10 font-medium text-primary",
                        !isSelected && isActive && "bg-surface-muted",
                        !isSelected && !isActive && "hover:bg-surface-muted",
                      )}
                      onMouseEnter={() => setActiveIndex(i)}
                      onClick={() => !opt.disabled && commit(opt.value)}
                    >
                      <span className="min-w-0 flex-1 truncate">{opt.label}</span>
                      {isSelected && (
                        <Check className="h-4 w-4 shrink-0 text-primary" />
                      )}
                    </li>
                  </Fragment>
                );
              })
            )}
          </ul>,
          document.body,
        )
      : null;

  return (
    <div ref={rootRef} className={cn("relative w-full", className)}>
      <input
        type="text"
        tabIndex={-1}
        aria-hidden
        name={name}
        id={selectId}
        value={value}
        required={required}
        disabled={disabled}
        readOnly
        className="pointer-events-none absolute h-0 w-0 opacity-0"
        onChange={() => undefined}
      />

      {loading ? (
        <div
          aria-hidden
          style={{ boxShadow: 'var(--shadow-elevated)' }}
          className={cn(
            "relative overflow-hidden border border-border bg-surface",
            variant === "default" && "h-10 rounded-xl",
            variant === "ghost" && "h-8 rounded-lg",
          )}
        >
          {/* shimmer sweep */}
          <div
            className="absolute inset-0 -translate-x-full animate-shimmer"
            style={{
              backgroundImage:
                'linear-gradient(90deg, transparent 0%, rgba(255,255,255,0.4) 50%, transparent 100%)',
            }}
          />
          {/* content placeholder row */}
          <div className="flex h-full items-center gap-2 px-3.5">
            <div className="h-2.5 w-24 rounded-full bg-surface-muted/80" />
            <div className="ml-auto flex gap-1">
              <span className="h-1.5 w-1.5 animate-bounce-dot rounded-full bg-muted/50 [animation-delay:0ms]" />
              <span className="h-1.5 w-1.5 animate-bounce-dot rounded-full bg-muted/50 [animation-delay:120ms]" />
              <span className="h-1.5 w-1.5 animate-bounce-dot rounded-full bg-muted/50 [animation-delay:240ms]" />
            </div>
          </div>
        </div>
      ) : (
        <button
          ref={triggerRef}
          type="button"
          disabled={disabled}
          aria-haspopup="listbox"
          aria-expanded={open}
          aria-label={ariaLabel}
          aria-controls={`${selectId}-list`}
          onClick={() => !disabled && setOpen((o) => !o)}
          onKeyDown={onTriggerKey}
          className={cn(
            "flex w-full items-center justify-between gap-2 text-left text-sm text-foreground transition-all duration-200",
            "focus:outline-none disabled:pointer-events-none disabled:opacity-50",
            variant === "default" &&
              cn(
                "h-10 rounded-xl border border-border bg-surface px-3.5 shadow-sm hover:border-primary/30",
                "focus:ring-2 focus:ring-ring/50 focus:border-ring",
                open && "border-ring ring-2 ring-ring/50",
              ),
            variant === "ghost" &&
              cn(
                "h-8 rounded-lg border-0 bg-transparent px-1.5 font-semibold tabular-nums shadow-none hover:bg-transparent",
                "focus:ring-0",
              ),
            !selected && value === "" && "text-muted",
          )}
        >
          <span className="min-w-0 flex-1 truncate">{display}</span>
          <ChevronDown
            className={cn(
              "h-4 w-4 shrink-0 text-muted transition-transform duration-200",
              open && "rotate-180",
            )}
          />
        </button>
      )}

      {menu}
    </div>
  );
}
