import React, { useCallback, useEffect, useId, useRef, useState } from 'react';
import { Check, Copy, ShieldAlert } from 'lucide-react';
import { Modal } from './Modal';
import { Button } from './Button';

// IMP-246994888a1f — the platform's one-shot reveal shape, in core.
//
// Some server operations mint material that exists in plaintext for exactly
// one response and is unrecoverable afterwards (a rotated webhook secret, a
// freshly issued token). This renders that moment and nothing else: the values
// live in this component's props for as long as it is mounted, and go nowhere
// else — no browser storage, no logs, no second request. The caller owns the
// value and is responsible for dropping it when onDone fires.

export interface OneShotRevealModalProps {
  /** The fields to reveal. Keys are shown as labels; non-string values are serialized. */
  values: Record<string, unknown>;
  title?: string;
  /** Extra context under the fields, e.g. what the operator must go update. */
  note?: string;
  /** Wording of the acknowledgement that unlocks the only exit. */
  acknowledgeLabel?: string;
  onDone: () => void;
}

// Words a plain capitalize would mangle into "Webhook url" / "Account id".
const ACRONYMS = new Set(['url', 'uri', 'id', 'api', 'ip', 'ssh', 'tls', 'cidr', 'dns']);

const humanize = (key: string): string => {
  const words = key.replace(/[_-]+/g, ' ').trim().split(/\s+/);
  return words
    .map((word, index) => {
      if (ACRONYMS.has(word.toLowerCase())) return word.toUpperCase();
      if (index > 0) return word;
      return word.charAt(0).toUpperCase() + word.slice(1);
    })
    .join(' ');
};

const asText = (value: unknown): string =>
  typeof value === 'string' ? value : JSON.stringify(value);

const FOCUSABLE =
  'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

export const OneShotRevealModal: React.FC<OneShotRevealModalProps> = ({
  values,
  title = 'Shown once',
  note,
  acknowledgeLabel = 'I have saved this somewhere safe',
  onDone,
}) => {
  const [acknowledged, setAcknowledged] = useState(false);
  const [copiedKey, setCopiedKey] = useState<string | null>(null);
  const [copyFailedKey, setCopyFailedKey] = useState<string | null>(null);
  const bodyRef = useRef<HTMLDivElement>(null);
  const copyTimer = useRef<number | undefined>(undefined);
  const labelPrefix = useId();

  // null/undefined slots carry nothing to save and would render "null".
  const entries = Object.entries(values).filter(([, value]) => value !== null && value !== undefined);

  useEffect(() => () => window.clearTimeout(copyTimer.current), []);

  // This dialog has no close chrome, no backdrop dismiss and no Escape, so
  // without containment a keyboard operator tabs straight out of it and onto
  // the surface behind — where the next Approve would overwrite a reveal they
  // have not saved yet. Contain Tab within the dialog the Modal portals.
  const trapFocus = useCallback((event: KeyboardEvent) => {
    if (event.key !== 'Tab') return;
    const dialog = bodyRef.current?.closest('[role="dialog"]');
    if (!dialog) return;
    const focusable = Array.from(dialog.querySelectorAll<HTMLElement>(FOCUSABLE)).filter(
      (el) => el.offsetParent !== null || el === document.activeElement
    );
    if (focusable.length === 0) return;
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    const active = document.activeElement as HTMLElement | null;
    if (!active || !dialog.contains(active)) {
      event.preventDefault();
      first.focus();
    } else if (event.shiftKey && active === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && active === last) {
      event.preventDefault();
      first.focus();
    }
  }, []);

  useEffect(() => {
    document.addEventListener('keydown', trapFocus, true);
    return () => document.removeEventListener('keydown', trapFocus, true);
  }, [trapFocus]);

  const copy = async (key: string, text: string) => {
    window.clearTimeout(copyTimer.current);
    try {
      // No optional chaining: outside a secure context navigator.clipboard is
      // undefined, and a silent no-op here would render the success tick for a
      // copy that never happened — on a value that cannot be shown again.
      await navigator.clipboard.writeText(text);
      setCopyFailedKey(null);
      setCopiedKey(key);
      copyTimer.current = window.setTimeout(() => setCopiedKey(null), 2000);
    } catch {
      // Deliberately not logged: the failure detail would carry the value.
      setCopiedKey(null);
      setCopyFailedKey(key);
    }
  };

  return (
    <Modal
      isOpen
      onClose={onDone}
      title={title}
      icon={<ShieldAlert className="w-6 h-6" />}
      maxWidth="2xl"
      // The value is unrecoverable, so the acknowledged Done button is the only
      // way out: no close chrome, no backdrop dismiss, no Escape.
      showCloseButton={false}
      closeOnBackdrop={false}
      closeOnEscape={false}
      footer={
        <Button variant="primary" onClick={onDone} disabled={!acknowledged}>
          Done
        </Button>
      }
    >
      <div data-testid="one-shot-reveal" ref={bodyRef}>
        <p className="text-sm text-theme-warning-fg mb-4 font-medium">
          This is shown ONCE. It cannot be recovered. Save it now.
        </p>

        {entries.map(([key, value]) => {
          const text = asText(value);
          const labelId = `${labelPrefix}-${key}`;
          return (
            <div key={key} className="mb-4">
              <p id={labelId} className="block text-sm text-theme-secondary mb-1">
                {humanize(key)}
              </p>
              <div className="flex items-center gap-2">
                <code
                  aria-labelledby={labelId}
                  className="flex-1 px-3 py-2 rounded border border-theme bg-theme-surface text-theme-primary font-mono text-sm break-all"
                >
                  {text}
                </code>
                <Button
                  size="sm"
                  variant="outline"
                  data-testid={`one-shot-copy-${key}`}
                  aria-label={`Copy ${humanize(key)}`}
                  onClick={() => { void copy(key, text); }}
                >
                  {copiedKey === key ? <Check size={14} /> : <Copy size={14} />}
                </Button>
              </div>
              {copyFailedKey === key && (
                <p className="mt-1 text-xs text-theme-error-fg" data-testid={`one-shot-copy-failed-${key}`}>
                  Copy failed. Select the value above and copy it manually.
                </p>
              )}
            </div>
          );
        })}

        {note && <p className="text-xs text-theme-tertiary mb-4">{note}</p>}

        <label className="flex items-center gap-2 cursor-pointer">
          <input
            type="checkbox"
            checked={acknowledged}
            onChange={(e) => setAcknowledged(e.target.checked)}
            className="w-4 h-4 rounded border-theme bg-theme-surface"
          />
          <span className="text-sm text-theme-primary">{acknowledgeLabel}</span>
        </label>
      </div>
    </Modal>
  );
};
