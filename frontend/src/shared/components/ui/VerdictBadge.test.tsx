import { render, screen } from '@testing-library/react';
import { VerdictBadge, VERDICT_PRESENTATION, verdictLabel } from './VerdictBadge';
import { VERDICT_LADDER, type Verdict } from '@/shared/types/platformStatus';

// VerdictBadge (C1) — the one rendering of a component status verdict.
//
// The table is asserted ENTRY BY ENTRY rather than by rendering a couple of
// examples. Spot checks pass just as happily when a verdict is dropped and
// starts rendering as something else, which is the silent regression this
// component exists to prevent.
//
// The EXHAUSTIVENESS half of the guarantee is not tested here and cannot be:
// jest strips types without checking them, so a missing verdict is a `tsc`
// failure (VerdictBadge.tsx's lookup and verdictCoverage.ts's `satisfies`),
// never a red test. What IS tested here is the part types cannot express —
// which variant each verdict actually renders, and that none of them is grey.

describe('VERDICT_PRESENTATION', () => {
  // Each row is a decision about what an operator concludes at a glance. The
  // third column records the reasoning for the ones that had a plausible
  // alternative, so a future change has to argue with it rather than around it.
  const CASES: Array<[Verdict, string, string, string?]> = [
    ['ok', 'success', 'OK'],
    [
      'held',
      'info',
      'Held',
      'Operator intent — cordoned, paused, drained. Calm blue, matching the extension table\'s `paused`. NOT amber: amber is `suspended`/"needs attention", the opposite polarity, and a planned drain that reads as a problem trains an operator to ignore amber.',
    ],
    [
      'progressing',
      'primary',
      'Progressing',
      'In-flight remediation or provisioning, matching the extension table\'s `running`. The one verdict expected to change on its own, so it carries a pulsing dot.',
    ],
    [
      'not_measured',
      'outline',
      'Not measured',
      'An absent measurement is a gap an operator should close, not an inert state. `secondary`/`default` are this design system\'s greys for deleted, archived and disabled things; filing blindness there would hide it. Dashed outline instead.',
    ],
    ['degraded', 'warning', 'Degraded'],
    ['down', 'danger', 'Down'],
  ];

  it.each(CASES)('renders %s with the %s variant', (verdict, variant) => {
    const { container } = render(<VerdictBadge verdict={verdict} />);
    expect(container.querySelector(`.badge-theme-${variant}`)).toBeInTheDocument();
  });

  it.each(CASES)('renders %s with the label %s', (verdict, _variant, label) => {
    render(<VerdictBadge verdict={verdict} />);
    expect(screen.getByText(label)).toBeInTheDocument();
    expect(verdictLabel(verdict)).toBe(label);
  });

  it('covers every verdict in the ladder and nothing else', () => {
    // Equality against the LADDER, not against the table itself: comparing the
    // table to a copy of its own keys is a check that cannot fail. The ladder
    // is derived from the wire union, so this is the arm that notices a verdict
    // added to the union and forgotten here — and the one that notices a stray
    // key added to the table.
    expect(Object.keys(VERDICT_PRESENTATION).sort()).toEqual([...VERDICT_LADDER].sort());
    expect(CASES.map(([verdict]) => verdict).sort()).toEqual([...VERDICT_LADDER].sort());
  });

  it('gives every verdict a variant of its own', () => {
    // Two verdicts sharing a variant would be indistinguishable in the compact
    // dot form, where there is no label to read.
    const variants = Object.values(VERDICT_PRESENTATION).map((entry) => entry.variant);
    expect(new Set(variants).size).toBe(variants.length);
  });

  it('never renders a verdict in the inert greys', () => {
    // The whole table, not just not_measured: `secondary` and `default` mean
    // "deleted, archived, disabled — nobody needs to look". No verdict on this
    // ladder means that, and `not_measured` least of all.
    const greys = ['secondary', 'default'];
    Object.entries(VERDICT_PRESENTATION).forEach(([verdict, entry]) => {
      expect(greys).not.toContain(entry.variant);
      const { container } = render(<VerdictBadge verdict={verdict as Verdict} />);
      expect(container.querySelector('.badge-theme-secondary')).not.toBeInTheDocument();
      expect(container.querySelector('.badge-theme-default')).not.toBeInTheDocument();
    });
  });

  it('gives not_measured a dashed outline rather than a fill', () => {
    // Both arms of the one that matters most: it IS the outline treatment, and
    // it is NOT the grey one. Asserting only the absence of grey would pass for
    // a not_measured rendered bright red.
    const { container } = render(<VerdictBadge verdict="not_measured" />);
    expect(container.querySelector('.badge-theme-outline')).toBeInTheDocument();
    expect(container.querySelector('.border-dashed')).toBeInTheDocument();
    expect(container.querySelector('.badge-theme-secondary')).not.toBeInTheDocument();
  });
});

describe('VerdictBadge', () => {
  it('carries the verdict in its accessible name', () => {
    render(<VerdictBadge verdict="down" />);
    expect(screen.getByRole('img', { name: 'Status: Down' })).toBeInTheDocument();
  });

  it('prefixes the accessible name with the component when given one', () => {
    // Fifty unattributed "Down"s down a grid is not navigable by screen reader.
    render(<VerdictBadge verdict="degraded" labelPrefix="Rails API" />);
    expect(screen.getByRole('img', { name: 'Rails API: Degraded' })).toBeInTheDocument();
  });

  it('drops the label but keeps the accessible name in the compact form', () => {
    const { container } = render(<VerdictBadge verdict="ok" withLabel={false} />);
    expect(screen.queryByText('OK')).not.toBeInTheDocument();
    expect(screen.getByRole('img', { name: 'Status: OK' })).toBeInTheDocument();
    // A compact badge is a dot or it is an empty coloured pill, which reads as
    // a state the backend reported rather than a deliberate abbreviation.
    expect(container.querySelector('.badge-dot')).toBeInTheDocument();
  });

  it('pulses progressing, and only progressing', () => {
    const { container: prog } = render(<VerdictBadge verdict="progressing" />);
    expect(prog.querySelector('.badge-dot-pulse')).toBeInTheDocument();

    const { container: down } = render(<VerdictBadge verdict="down" />);
    expect(down.querySelector('.badge-dot-pulse')).not.toBeInTheDocument();
  });

  it('defaults to the sm size and accepts an override', () => {
    const { container: def } = render(<VerdictBadge verdict="ok" />);
    expect(def.querySelector('.badge-theme-sm')).toBeInTheDocument();

    const { container: lg } = render(<VerdictBadge verdict="ok" size="lg" />);
    expect(lg.querySelector('.badge-theme-lg')).toBeInTheDocument();
  });

  it('exposes the verdict as a data attribute for the page to key on', () => {
    const { container } = render(<VerdictBadge verdict="not_measured" />);
    expect(container.querySelector('[data-verdict="not_measured"]')).toBeInTheDocument();
  });
});
