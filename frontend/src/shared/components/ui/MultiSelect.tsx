import React, { useEffect, useId, useMemo, useRef, useState } from 'react';
import { Check, ChevronDown, Search, X } from 'lucide-react';

export interface MultiSelectOption {
  value: string;
  label: string;
  group?: string;
  description?: string;
  // Optional secondary label rendered subtly after the primary label
  // (e.g. "amd64 (x86_64)"). When the user types in the search box, both
  // label and secondaryLabel are matched.
  secondaryLabel?: string;
}

export interface MultiSelectProps {
  options: MultiSelectOption[];
  value: string[];
  onChange: (next: string[]) => void;
  placeholder?: string;
  searchPlaceholder?: string;
  emptyMessage?: string;
  groupOrder?: string[];
  // When set, the chip overflow trims to `maxChips` chips with a
  // "+N more" indicator. Default: 4.
  maxChips?: number;
  className?: string;
  id?: string;
  ariaLabel?: string;
  disabled?: boolean;
}

/**
 * MultiSelect — popover-driven checkbox list with keyboard nav + grouping.
 *
 * Replaces native `<select multiple>` (Ctrl+Click is undiscoverable, mobile
 * is unusable, ARIA is weak). Use `groupBy` to render `<optgroup>`-style
 * headings; otherwise renders a flat list. Search filters by label,
 * value, and secondaryLabel.
 *
 * Keyboard: Up/Down moves focus, Space/Enter toggles, Escape closes,
 * `/` (when popover open and not in search) jumps to the search box.
 */
export const MultiSelect: React.FC<MultiSelectProps> = ({
  options,
  value,
  onChange,
  placeholder = 'Select…',
  searchPlaceholder = 'Search…',
  emptyMessage = 'No matches',
  groupOrder,
  maxChips = 4,
  className = '',
  id,
  ariaLabel,
  disabled = false,
}) => {
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState('');
  const [activeIndex, setActiveIndex] = useState(0);

  const containerRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const searchRef = useRef<HTMLInputElement>(null);
  const listRef = useRef<HTMLUListElement>(null);
  const fieldId = useId();
  const listboxId = `${id ?? fieldId}-listbox`;

  // ── Filter + group ─────────────────────────────────────────────────
  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return options;
    return options.filter(
      (o) =>
        o.label.toLowerCase().includes(q) ||
        o.value.toLowerCase().includes(q) ||
        (o.secondaryLabel?.toLowerCase().includes(q) ?? false) ||
        (o.description?.toLowerCase().includes(q) ?? false)
    );
  }, [options, search]);

  const groups = useMemo(() => {
    const map = new Map<string, MultiSelectOption[]>();
    filtered.forEach((o) => {
      const key = o.group ?? '';
      if (!map.has(key)) map.set(key, []);
      map.get(key)!.push(o);
    });
    const keys = Array.from(map.keys());
    if (groupOrder && groupOrder.length > 0) {
      keys.sort((a, b) => {
        const ai = groupOrder.indexOf(a);
        const bi = groupOrder.indexOf(b);
        if (ai === -1 && bi === -1) return a.localeCompare(b);
        if (ai === -1) return 1;
        if (bi === -1) return -1;
        return ai - bi;
      });
    } else {
      keys.sort();
    }
    return keys.map((k) => ({ name: k, options: map.get(k)! }));
  }, [filtered, groupOrder]);

  // Flat list for keyboard navigation (groups concatenated in render order)
  const flat = useMemo(() => groups.flatMap((g) => g.options), [groups]);

  // ── State sync when opening / option set changes ───────────────────
  useEffect(() => {
    if (open) {
      setActiveIndex(0);
      // Defer focus so popover paints first
      const t = setTimeout(() => searchRef.current?.focus(), 0);
      return () => clearTimeout(t);
    }
    setSearch('');
  }, [open]);

  // Close on click outside
  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => {
      if (!containerRef.current?.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', onDown);
    return () => document.removeEventListener('mousedown', onDown);
  }, [open]);

  // ── Selection helpers ───────────────────────────────────────────────
  const selectedSet = useMemo(() => new Set(value), [value]);
  const isSelected = (v: string) => selectedSet.has(v);

  const toggle = (v: string) => {
    if (disabled) return;
    onChange(isSelected(v) ? value.filter((x) => x !== v) : [...value, v]);
  };

  const removeChip = (v: string) => {
    if (disabled) return;
    onChange(value.filter((x) => x !== v));
  };

  // ── Keyboard nav ────────────────────────────────────────────────────
  const onKeyDown = (e: React.KeyboardEvent) => {
    if (disabled) return;

    if (!open) {
      if (e.key === 'Enter' || e.key === ' ' || e.key === 'ArrowDown') {
        e.preventDefault();
        setOpen(true);
      }
      return;
    }

    if (e.key === 'Escape') {
      e.preventDefault();
      setOpen(false);
      triggerRef.current?.focus();
      return;
    }
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setActiveIndex((i) => Math.min(i + 1, Math.max(flat.length - 1, 0)));
      return;
    }
    if (e.key === 'ArrowUp') {
      e.preventDefault();
      setActiveIndex((i) => Math.max(i - 1, 0));
      return;
    }
    if ((e.key === 'Enter' || e.key === ' ') && document.activeElement !== searchRef.current) {
      e.preventDefault();
      const opt = flat[activeIndex];
      if (opt) toggle(opt.value);
      return;
    }
    if (e.key === 'Enter' && document.activeElement === searchRef.current && flat.length > 0) {
      e.preventDefault();
      const opt = flat[activeIndex];
      if (opt) toggle(opt.value);
      return;
    }
  };

  // ── Render ──────────────────────────────────────────────────────────
  const chipsToShow = value.slice(0, maxChips);
  const overflow = value.length - chipsToShow.length;

  const labelFor = (v: string) => options.find((o) => o.value === v)?.label ?? v;

  return (
    <div ref={containerRef} className={`relative ${className}`} onKeyDown={onKeyDown}>
      <button
        type="button"
        ref={triggerRef}
        onClick={() => !disabled && setOpen((o) => !o)}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={listboxId}
        aria-label={ariaLabel}
        disabled={disabled}
        className={`w-full min-h-[2.25rem] flex flex-wrap items-center gap-1 px-2 py-1.5 rounded border border-theme bg-theme-background text-left text-theme-primary focus:outline-none focus:border-theme-focus disabled:opacity-50`}
      >
        {value.length === 0 ? (
          <span className="text-theme-tertiary text-sm">{placeholder}</span>
        ) : (
          <>
            {chipsToShow.map((v) => (
              <span
                key={v}
                className="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-theme-focus/10 text-theme-primary border border-theme"
              >
                {labelFor(v)}
                <button
                  type="button"
                  onClick={(e) => {
                    e.stopPropagation();
                    removeChip(v);
                  }}
                  aria-label={`Remove ${labelFor(v)}`}
                  className="text-theme-tertiary hover:text-theme-primary"
                >
                  <X className="w-3 h-3" />
                </button>
              </span>
            ))}
            {overflow > 0 && (
              <span className="px-2 py-0.5 text-xs rounded-full bg-theme-background-secondary text-theme-secondary">
                +{overflow} more
              </span>
            )}
          </>
        )}
        <ChevronDown className="w-4 h-4 text-theme-tertiary ml-auto flex-shrink-0" />
      </button>

      {open && (
        <div
          className="absolute z-30 mt-1 w-full bg-theme-surface border border-theme rounded-lg shadow-lg max-h-80 overflow-hidden flex flex-col"
          role="dialog"
          aria-label={ariaLabel ? `${ariaLabel} options` : 'Options'}
        >
          <div className="p-2 border-b border-theme bg-theme-background-secondary">
            <div className="relative">
              <Search className="absolute left-2 top-1/2 -translate-y-1/2 w-4 h-4 text-theme-tertiary" />
              <input
                ref={searchRef}
                type="text"
                value={search}
                onChange={(e) => {
                  setSearch(e.target.value);
                  setActiveIndex(0);
                }}
                placeholder={searchPlaceholder}
                className="w-full pl-7 pr-2 py-1 text-sm rounded border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus"
              />
            </div>
          </div>

          <ul
            ref={listRef}
            id={listboxId}
            role="listbox"
            aria-multiselectable="true"
            className="flex-1 overflow-y-auto py-1"
          >
            {flat.length === 0 && (
              <li className="px-3 py-2 text-sm text-theme-tertiary">{emptyMessage}</li>
            )}
            {flat.length > 0 &&
              groups.map((group) => (
                <React.Fragment key={group.name || '__none__'}>
                  {group.name && (
                    <li
                      role="presentation"
                      className="px-3 py-1 text-xs font-semibold uppercase tracking-wider text-theme-tertiary bg-theme-background-secondary/50"
                    >
                      {group.name}
                    </li>
                  )}
                  {group.options.map((opt) => {
                    const idx = flat.findIndex((o) => o.value === opt.value);
                    const active = idx === activeIndex;
                    const selected = isSelected(opt.value);
                    return (
                      <li
                        key={opt.value}
                        role="option"
                        aria-selected={selected}
                        title={opt.description}
                        onMouseEnter={() => setActiveIndex(idx)}
                        onClick={() => toggle(opt.value)}
                        className={`px-3 py-1.5 text-sm cursor-pointer flex items-start gap-2 ${
                          active ? 'bg-theme-surface-hover' : ''
                        }`}
                      >
                        <span
                          className={`mt-0.5 w-4 h-4 rounded border flex items-center justify-center flex-shrink-0 ${
                            selected
                              ? 'bg-theme-focus border-theme-focus text-white'
                              : 'border-theme bg-theme-background'
                          }`}
                          aria-hidden="true"
                        >
                          {selected && <Check className="w-3 h-3" />}
                        </span>
                        <span className="flex-1 min-w-0">
                          <span className="text-theme-primary">{opt.label}</span>
                          {opt.secondaryLabel && (
                            <span className="ml-1 text-xs text-theme-tertiary">
                              ({opt.secondaryLabel})
                            </span>
                          )}
                          {opt.description && (
                            <span className="block text-xs text-theme-secondary truncate">
                              {opt.description}
                            </span>
                          )}
                        </span>
                      </li>
                    );
                  })}
                </React.Fragment>
              ))}
          </ul>
        </div>
      )}
    </div>
  );
};

export default MultiSelect;
