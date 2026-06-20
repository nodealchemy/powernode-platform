import type { SetupStep } from '../services/setupApi';

/** Contract for component-based setup steps (rich UI instead of a field schema). */
export interface SetupStepComponentProps {
  step: SetupStep;
}
