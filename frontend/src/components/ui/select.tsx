"use client";

import {
  Children,
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
}

function optionsFromChildren(children: ReactNode): SelectOption[] {
  const out: SelectOption[] = [];
  Children.forEach(children, (child) => {
    if (
      !isValidElement<{
        value?: string | number;
        disabled?: boolean;
        children?: ReactNode;
      }>(child)
    )
      return;
    if (typeof child.type === "string" && child.type !== "option") return;
    if (child.type === "option" || (child.props && "value" in child.props)) {
      out.push({
        value: String(child.props.value ?? ""),
        label: child.props.children,
        disabled: !!child.props.disabled,
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
    const el = listRef.current.querySelector<HTMLElement>(
      `[data-index="${activeIndex}"]`,
    );
    el?.scrollIntoView({ block: "nearest" });
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
              "overflow-auto rounded-xl border border-border bg-surface p-1.5 shadow-[var(--shadow-elevated)]",
              "origin-top animate-in",
            )}
          >
            {options.length === 0 ? (
              <li className="px-3 py-2 text-sm text-muted">No options</li>
            ) : (
              options.map((opt, i) => {
                const isSelected = opt.value === value;
                const isActive = i === activeIndex;
                return (
                  <li
                    key={`${opt.value}-${i}`}
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

      {menu}
    </div>
  );
}
