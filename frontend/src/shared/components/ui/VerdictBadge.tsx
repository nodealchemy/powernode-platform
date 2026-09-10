import React from 'react';
import { Badge } from '@/shared/components/ui/Badge';
import type { Verdict } from '@/shared/types/platformStatus';

// VerdictBadge — the ONE rendering of a component status verdict (design §4.1,
// §6). Every card, rail row, rollup header and drawer title on the status page
// draws its verdict through this, so an operator never has to learn that amber
// means one thing on the grid and another in the drawer.
//
// ── WHY THERE IS NO DEFAULT BRANCH ─────────────────────────────────────────
//
// `VERDICT_PRESENTATION` is declared `as const` with NO type annotation, and
// the component indexes it with a `Verdict`. Both halves of that are load
// bearing:
//
//   - `as const` (rather than `: Record<Verdict, VerdictPresentation>`) makes
//     the table's key type the literal union of the verdicts ACTUALLY MAPPED.
//     Annotating it would have made the record's type the declaration instead
//     of the data, and a `?? fallback` on the lookup would then have compiled
//     happily while rendering a brand-new verdict as whatever the fallback is.
//   - indexing it with `Verdict` means a verdict in the union with no entry
//     here is a compile error AT THIS LINE, not a grey pill in production.
//
// `verdictCoverage.ts` states the same requirement once more as a named
// `satisfies`, so the failure has a readable diagnostic rather than only an
// index-signature complaint. Its header explains why it is a plain `.ts` and
// not a spec — the short version is jest, not tsconfig; read it there rather
// than repeating a half-true summary here.
//
// ── WHY `not_measured` IS NOT GREY ─────────────────────────────────────────
//
// `secondary` and `default` are this design system's INERT greys — deleted,
// archived, cancelled, disabled. `not_measured` is none of those: it means the
// sweep could not obtain a reading, which is a gap an operator should close,
// and it sorts ABOVE `progressing` in the ladder for that reason. Rendering it
// grey would file blindness alongside the things nobody needs to look at. It
// gets a dashed outline instead — visibly unlike every filled verdict, and
// visibly unlike the inert palette. `VerdictVariant` below makes that a
// compile error rather than a convention.

/**
 * The Badge variants a verdict may use — every one EXCEPT the inert greys.
 *
 * Expressed as a type rather than only as a rule in the header and a sweep in
 * the spec (C1 review F2). The whole argument for this component is that a rule
 * the compiler enforces beats a rule a test enforces, and "no verdict is grey"
 * was the one rule left to the test. Now a grey verdict fails at the table,
 * where the fix goes, and the spec keeps its own job: saying WHICH variant each
 * verdict gets, which no type can express.
 *
 * Derived from `Badge`'s own union by subtraction, so a variant added to Badge
 * becomes available here automatically and one removed from Badge stops
 * compiling here.
 */
export type VerdictVariant = Exclude<
  NonNullable<React.ComponentProps<typeof Badge>['variant']>,
  'secondary' | 'default'
>;

/** How one verdict draws itself. */
export interface VerdictPresentation {
  /** Never `secondary` or `default`: those are the inert greys — see the header. */
  variant: VerdictVariant;
  /** Operator-facing text. Also the accessible name. */
  label: string;
  /** Leading dot. Always drawn in the compact (`withLabel={false}`) form. */
  dot?: boolean;
  /** Pulses the dot. Only meaningful with `dot`. */
  pulse?: boolean;
  /** Extra classes. Colourless utilities only — colour comes from the variant. */
  className?: string;
}

export type VerdictBadgeSize = NonNullable<React.ComponentProps<typeof Badge>['size']>;

/**
 * One deliberate treatment per verdict. Every choice below is a decision about
 * what an operator should conclude at a glance, and each is repeated in
 * `VerdictBadge.test.tsx` so it cannot be changed silently.
 */
export const VERDICT_PRESENTATION = {
  // Serving. The only green on the page — nothing else earns it.
  ok: { variant: 'success', label: 'OK' },

  // OPERATOR INTENT: cordoned, paused, drained, on hold. Calm blue, matching
  // the extension's existing `paused`, which is the same concept. Emphatically
  // NOT amber: amber is `suspended`/"needs attention", the opposite polarity,
  // and a planned drain that reads as a problem trains an operator to ignore
  // amber.
  held: { variant: 'info', label: 'Held' },

  // In-flight remediation or provisioning. Saturated primary, matching the
  // extension's `running`, with a pulsing dot so "work is happening" is
  // readable without the label — this is the one verdict expected to change on
  // its own.
  progressing: { variant: 'primary', label: 'Progressing', dot: true, pulse: true },

  // ABSENT MEASUREMENT. Dashed outline: distinct from every filled verdict and
  // from the inert greys. `badge-theme-outline` is transparent with the
  // interactive-primary colour for both text and border, so it is theme-aware
  // in both light and dark without a hardcoded colour, and `border-dashed` is
  // a colourless utility layered on top.
  not_measured: {
    variant: 'outline',
    label: 'Not measured',
    className: 'border-dashed',
  },

  // Serving but impaired.
  degraded: { variant: 'warning', label: 'Degraded' },

  // Total loss of the thing.
  down: { variant: 'danger', label: 'Down' },
} as const;

/** The operator-facing text for a verdict. */
export function verdictLabel(verdict: Verdict): string {
  return VERDICT_PRESENTATION[verdict].label;
}

export interface VerdictBadgeProps {
  verdict: Verdict;
  size?: VerdictBadgeSize;
  /**
   * Render the label text. `false` gives the compact form — a coloured dot
   * whose verdict lives in the accessible name only, for dense rows where the
   * verdict is already stated by the column. Defaults to `true`.
   */
  withLabel?: boolean;
  /**
   * Prefix for the accessible name, e.g. the component's display name, so a
   * screen reader hears "Rails API: Down" rather than six unattributed
   * "Down"s down a grid.
   */
  labelPrefix?: string;
  className?: string;
}

export const VerdictBadge: React.FC<VerdictBadgeProps> = ({
  verdict,
  size = 'sm',
  withLabel = true,
  labelPrefix,
  className,
}) => {
  // No `??` and no default entry: an unmapped verdict fails to compile here.
  const presentation: VerdictPresentation = VERDICT_PRESENTATION[verdict];
  const accessibleName = labelPrefix
    ? `${labelPrefix}: ${presentation.label}`
    : `Status: ${presentation.label}`;

  return (
    // role="img" + aria-label rather than letting the pill text speak for
    // itself: in the compact form there IS no text, and in the labelled form
    // the prefix is what makes one of fifty badges identifiable. aria-label on
    // role="img" replaces the subtree, so the label is never announced twice.
    <span
      role="img"
      aria-label={accessibleName}
      title={presentation.label}
      data-verdict={verdict}
      className="inline-flex"
    >
      <Badge
        variant={presentation.variant}
        size={size}
        // The compact form is a dot or it is an empty pill, which reads as a
        // state the backend reported rather than as a deliberate abbreviation.
        dot={presentation.dot ?? !withLabel}
        pulse={presentation.pulse ?? false}
        className={[presentation.className, className].filter(Boolean).join(' ')}
      >
        {withLabel ? presentation.label : null}
      </Badge>
    </span>
  );
};

export default VerdictBadge;
