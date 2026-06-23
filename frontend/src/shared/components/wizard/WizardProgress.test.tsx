import { render, screen } from '@testing-library/react';
import { WizardProgress, type WizardProgressStep } from './WizardProgress';

// Regression coverage for the shared step rail (IMP-8918d631354c). Guards the
// numbered rail, reached/active styling, annotations, connector count, and the
// flex-wrap behavior that fixed steps running off-screen with many steps.
const STEPS: WizardProgressStep[] = [
  { key: 'admin', label: 'Administrator' },
  { key: 'domain', label: 'Domain' },
  { key: 'email', label: 'Email', annotation: '(done)' },
  { key: 'seed', label: 'Seed' },
];

const ACTIVE_CIRCLE = 'bg-theme-interactive-primary';
const MUTED_CIRCLE = 'bg-theme-background-secondary';

const circles = (c: HTMLElement) => Array.from(c.querySelectorAll('span.w-6'));
const connectors = (c: HTMLElement) => Array.from(c.querySelectorAll('span.w-8'));

describe('WizardProgress', () => {
  it('renders one numbered item per step', () => {
    const { container } = render(<WizardProgress steps={STEPS} currentIndex={1} />);
    expect(container.querySelectorAll('li')).toHaveLength(STEPS.length);
    ['1', '2', '3', '4'].forEach((n) => expect(screen.getByText(n)).toBeInTheDocument());
  });

  it('renders each step label and any annotation', () => {
    render(<WizardProgress steps={STEPS} currentIndex={1} />);
    STEPS.forEach((s) => expect(screen.getByText(s.label)).toBeInTheDocument());
    expect(screen.getByText('(done)')).toBeInTheDocument();
  });

  it('styles steps at or before currentIndex as reached and later steps as muted', () => {
    const { container } = render(<WizardProgress steps={STEPS} currentIndex={1} />);
    const cs = circles(container);
    // reached: indices 0,1
    expect(cs[0].className).toContain(ACTIVE_CIRCLE);
    expect(cs[1].className).toContain(ACTIVE_CIRCLE);
    // not reached: indices 2,3
    expect(cs[2].className).toContain(MUTED_CIRCLE);
    expect(cs[3].className).toContain(MUTED_CIRCLE);
  });

  it('marks only the active step with aria-current="step"', () => {
    const { container } = render(<WizardProgress steps={STEPS} currentIndex={2} />);
    const current = container.querySelectorAll('[aria-current="step"]');
    expect(current).toHaveLength(1);
    expect(current[0]).toHaveTextContent('3'); // currentIndex 2 -> number 3
  });

  it('renders steps.length - 1 connector segments', () => {
    const { container } = render(<WizardProgress steps={STEPS} currentIndex={0} />);
    expect(connectors(container)).toHaveLength(STEPS.length - 1);
  });

  it('wraps the rail so many steps stay on-screen (no horizontal overflow)', () => {
    render(<WizardProgress steps={STEPS} currentIndex={0} testId="rail" />);
    const ol = screen.getByTestId('rail');
    expect(ol.tagName).toBe('OL');
    expect(ol.className).toContain('flex-wrap');
  });
});
