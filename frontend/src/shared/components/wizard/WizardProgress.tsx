import React from 'react';

export interface WizardProgressStep {
  key: string;
  label: string;
  /** Optional small annotation after the label (e.g. "(skipped)", "(configured)"). */
  annotation?: string;
}

interface WizardProgressProps {
  steps: WizardProgressStep[];
  /** Index of the active step; steps at or before it render as "reached". */
  currentIndex: number;
  /** data-testid for the <ol>, so callers can preserve existing test hooks. */
  testId?: string;
}

/**
 * Generic numbered step-progress bar shared by the onboarding and setup wizards
 * (the "extract & share" seam). Presentational only — the caller owns the step
 * list and the current index; this component renders the numbered rail + labels.
 */
export const WizardProgress: React.FC<WizardProgressProps> = ({ steps, currentIndex, testId }) => (
  <ol className="flex flex-wrap items-center gap-x-2 gap-y-3" data-testid={testId}>
    {steps.map((step, idx) => {
      const reached = idx <= currentIndex;
      return (
        <li key={step.key} className="flex items-center gap-2">
          <span
            className={`flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-xs font-semibold ${
              reached
                ? 'bg-theme-interactive-primary text-white'
                : 'bg-theme-background-secondary text-theme-tertiary'
            }`}
            aria-current={idx === currentIndex ? 'step' : undefined}
          >
            {idx + 1}
          </span>
          <span
            className={`hidden whitespace-nowrap text-xs sm:inline ${
              reached ? 'text-theme-primary' : 'text-theme-tertiary'
            }`}
          >
            {step.label}
            {step.annotation && <span className="ml-1 text-theme-tertiary">{step.annotation}</span>}
          </span>
          {idx < steps.length - 1 && (
            <span
              className={`h-0.5 w-8 shrink-0 rounded-full ${
                idx < currentIndex ? 'bg-theme-interactive-primary' : 'bg-theme-background-secondary'
              }`}
            />
          )}
        </li>
      );
    })}
  </ol>
);

export default WizardProgress;
