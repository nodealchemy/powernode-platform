import React, { useCallback, useEffect, useMemo, useReducer } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useDispatch, useSelector } from 'react-redux';
import { ArrowRight, CheckCircle2, Rocket, ShieldCheck, SkipForward, XCircle } from 'lucide-react';
import type { AppDispatch, RootState } from '@/shared/services';
import { getCurrentUser, refreshAccessToken } from '@/shared/services/slices/authSlice';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { WizardProgress } from '@/shared/components/wizard/WizardProgress';
import { logger } from '@/shared/utils/logger';
import { SchemaStepForm } from './SchemaStepForm';
import { ExtensionSelectionStep } from './steps/ExtensionSelectionStep';
import { SeedStep } from './steps/SeedStep';
import { ProviderStep } from './steps/ProviderStep';
import type { SetupStepComponentProps } from './steps/types';
import { setupApi, type SetupStep } from './services/setupApi';

// Resolver for component-based steps (rich UI instead of a field schema). A
// step id (e.g. "core/extension_selection") maps to its renderer; unknown ids
// fall through to a generic notice.
const STEP_COMPONENTS: Record<string, React.FC<SetupStepComponentProps>> = {
  'core/extension_selection': ExtensionSelectionStep,
  'core/seed': SeedStep,
  'core/ai_provider': ProviderStep,
  'core/cloud_provider': ProviderStep,
  'core/git_provider': ProviderStep,
};

// Where to land once bootstrap is complete — flows into the existing provider
// onboarding (OnboardingGate) for AI/cloud/git, which Phase 2 folds into the registry.
const POST_SETUP_PATH = '/app/system/provision';

// Local definition of the admin step shown BEFORE any user exists. /setup/steps
// is authenticated, so it cannot be fetched pre-bootstrap; the admin step is
// always step 0 and identical to the backend's core definition.
const ADMIN_STEP: SetupStep = {
  key: 'admin',
  title: 'Administrator',
  description: 'Create the first administrator for this instance.',
  order: 0,
  required: true,
  owner: 'core',
  endpoint: '/api/v1/setup/admin',
  completion: 'user_exists',
  schema: [
    { key: 'name', label: 'Full name', type: 'text', required: false },
    { key: 'email', label: 'Email', type: 'text', required: true, placeholder: 'you@example.com' },
    {
      key: 'password',
      label: 'Password',
      type: 'password',
      required: true,
      helper: 'At least 8 characters, with mixed case, a number and a symbol.',
    },
  ],
  completed: false,
  completed_at: null,
};

type Phase = 'loading' | 'ready' | 'already_complete';

interface SetupState {
  phase: Phase;
  steps: SetupStep[];
  index: number;
  values: Record<string, Record<string, string>>;
  valid: Record<string, boolean>;
  submitting: boolean;
  error: string | null;
}

type SetupAction =
  | { type: 'INIT_ADMIN' }
  | { type: 'INIT_STEPS'; steps: SetupStep[]; index: number }
  | { type: 'INIT_COMPLETE' }
  | { type: 'SET_VALUES'; key: string; values: Record<string, string>; valid: boolean }
  | { type: 'SUBMIT_START' }
  | { type: 'SUBMIT_ERROR'; error: string }
  | { type: 'REPLACE_STEPS'; steps: SetupStep[]; index: number }
  | { type: 'ADVANCE' };

const firstIncomplete = (steps: SetupStep[]): number => {
  const i = steps.findIndex((s) => !s.completed);
  return i === -1 ? Math.max(steps.length - 1, 0) : i;
};

const errorMessage = (err: unknown, fallback: string): string => {
  if (err && typeof err === 'object') {
    const e = err as { response?: { data?: { error?: string } }; message?: string };
    return e.response?.data?.error || e.message || fallback;
  }
  return fallback;
};

const initialState: SetupState = {
  phase: 'loading',
  steps: [],
  index: 0,
  values: {},
  valid: {},
  submitting: false,
  error: null,
};

function reducer(state: SetupState, action: SetupAction): SetupState {
  switch (action.type) {
    case 'INIT_ADMIN':
      return { ...state, phase: 'ready', steps: [ADMIN_STEP], index: 0, submitting: false, error: null };
    case 'INIT_STEPS':
      return { ...state, phase: 'ready', steps: action.steps, index: action.index, submitting: false, error: null };
    case 'INIT_COMPLETE':
      return { ...state, phase: 'already_complete' };
    case 'SET_VALUES':
      return {
        ...state,
        values: { ...state.values, [action.key]: action.values },
        valid: { ...state.valid, [action.key]: action.valid },
      };
    case 'SUBMIT_START':
      return { ...state, submitting: true, error: null };
    case 'SUBMIT_ERROR':
      return { ...state, submitting: false, error: action.error };
    case 'REPLACE_STEPS':
      return { ...state, submitting: false, error: null, steps: action.steps, index: action.index };
    case 'ADVANCE':
      return { ...state, submitting: false, error: null, index: Math.min(state.index + 1, state.steps.length) };
    default:
      return state;
  }
}

/**
 * SetupWizard — registry-driven first-run setup at the public /setup route.
 *
 * Flow:
 *   1. Unauthenticated, no admin yet → show the token-gated admin step (token
 *      from the URL the backend printed to the service console).
 *   2. Creating the admin establishes a session (server sets the refresh cookie);
 *      we restore it via refreshAccessToken/getCurrentUser. isAuthenticated flips,
 *      the load effect re-runs and fetches the now-authorized step list.
 *   3. The remaining core steps (domain, …) are driven generically from
 *      Setup::StepRegistry; each is persisted via /setup/steps/:key.
 *   4. When the last step is done → redirect into the app (existing onboarding).
 */
export const SetupWizard: React.FC = () => {
  const navigate = useNavigate();
  const dispatch = useDispatch<AppDispatch>();
  const [searchParams] = useSearchParams();
  const token = searchParams.get('token') ?? '';
  const isAuthenticated = useSelector((s: RootState) => s.auth.isAuthenticated);
  const [state, dispatchLocal] = useReducer(reducer, initialState);

  // Decide the initial view: authenticated → drive the registry steps; otherwise
  // probe /setup/status to show either the admin step or an "already done" notice.
  // Re-runs when isAuthenticated flips (post-admin), pulling the authorized steps.
  useEffect(() => {
    let cancelled = false;
    const load = async () => {
      try {
        if (isAuthenticated) {
          const steps = await setupApi.getSteps();
          if (cancelled) return;
          dispatchLocal({ type: 'INIT_STEPS', steps, index: firstIncomplete(steps) });
          return;
        }
        const status = await setupApi.getStatus();
        if (cancelled) return;
        dispatchLocal(status.bootstrap_complete ? { type: 'INIT_COMPLETE' } : { type: 'INIT_ADMIN' });
      } catch (err) {
        logger.error('SetupWizard: failed to load setup state', err);
        // Fail toward letting the operator attempt the admin step.
        if (!cancelled) dispatchLocal({ type: 'INIT_ADMIN' });
      }
    };
    void load();
    return () => {
      cancelled = true;
    };
  }, [isAuthenticated]);

  const currentStep = state.steps[state.index];

  const onValuesChange = useCallback(
    (values: Record<string, string>, valid: boolean) => {
      if (!currentStep) return;
      dispatchLocal({ type: 'SET_VALUES', key: currentStep.key, values, valid });
    },
    [currentStep?.key]
  );

  const submitAdmin = useCallback(async () => {
    const values = state.values.admin ?? {};
    dispatchLocal({ type: 'SUBMIT_START' });
    try {
      await setupApi.createAdmin({
        token,
        name: values.name,
        email: values.email,
        password: values.password,
      });
    } catch (err) {
      dispatchLocal({ type: 'SUBMIT_ERROR', error: errorMessage(err, 'Failed to create administrator.') });
      return;
    }
    try {
      // Restore the freshly-created session; isAuthenticated flips → steps load.
      await dispatch(refreshAccessToken()).unwrap();
      await dispatch(getCurrentUser(true)).unwrap();
    } catch (err) {
      logger.error('SetupWizard: admin created but session restore failed', err);
      navigate('/login', { replace: true });
    }
  }, [state.values, token, dispatch, navigate]);

  const submitStep = useCallback(
    async (step: SetupStep) => {
      const values = state.values[step.key] ?? {};
      dispatchLocal({ type: 'SUBMIT_START' });
      try {
        await setupApi.submitStep(step.key, values);
        const steps = await setupApi.getSteps();
        const nextIdx = Math.min(state.index + 1, steps.length);
        dispatchLocal({ type: 'REPLACE_STEPS', steps, index: nextIdx });
        if (nextIdx >= steps.length) {
          navigate(POST_SETUP_PATH, { replace: true });
        }
      } catch (err) {
        dispatchLocal({ type: 'SUBMIT_ERROR', error: errorMessage(err, 'Failed to save this step.') });
      }
    },
    [state.values, state.index, navigate]
  );

  const skipStep = useCallback(() => {
    const nextIdx = state.index + 1;
    if (nextIdx >= state.steps.length) {
      navigate(POST_SETUP_PATH, { replace: true });
    } else {
      dispatchLocal({ type: 'ADVANCE' });
    }
  }, [state.index, state.steps.length, navigate]);

  const progressSteps = useMemo(
    () =>
      state.steps.map((s) => ({
        key: s.key,
        label: s.title,
        annotation: s.completed ? '(done)' : undefined,
      })),
    [state.steps]
  );

  if (state.phase === 'loading') {
    return <LoadingSpinner message="Loading setup…" />;
  }

  if (state.phase === 'already_complete') {
    return (
      <CenteredNotice
        icon={<CheckCircle2 className="h-6 w-6 text-theme-success-fg" />}
        title="Setup is already complete"
        body="An administrator already exists for this instance."
        action={
          <Button type="button" variant="primary" onClick={() => navigate('/login', { replace: true })}>
            Go to sign in
          </Button>
        }
      />
    );
  }

  const isAdminStep = currentStep?.key === 'admin';
  const isSchemaStep = Boolean(currentStep?.schema && currentStep.schema.length > 0);
  // Provider steps (ai/cloud/git) self-persist via ProviderStep; their completion
  // is credential presence, so the footer just advances (no submitStep stamp).
  const isProviderStep = currentStep?.completion === 'provider_credentials';
  const stepValid = currentStep ? Boolean(state.valid[currentStep.key]) : false;
  const adminBlockedNoToken = isAdminStep && !token;

  return (
    <div
      className="flex min-h-screen w-full flex-col bg-theme-background text-theme-primary"
      data-testid="setup-wizard"
    >
      <header className="border-b border-theme bg-theme-surface px-6 py-4">
        <div className="mx-auto flex max-w-2xl items-center gap-3">
          <Rocket className="h-5 w-5 text-theme-interactive-primary" aria-hidden="true" />
          <div className="min-w-0">
            <h1 className="text-base font-semibold">Set up Powernode</h1>
            <p className="text-xs text-theme-secondary">
              Step {state.index + 1} of {state.steps.length} · {currentStep?.title}
            </p>
          </div>
        </div>
      </header>

      <main className="flex-1 px-6 py-6">
        <div className="mx-auto max-w-2xl space-y-5">
          <WizardProgress steps={progressSteps} currentIndex={state.index} testId="setup-step-progress" />

          <section
            className="rounded-lg border border-theme bg-theme-surface p-5 shadow-sm"
            data-testid={`setup-step-${currentStep?.key ?? 'none'}`}
          >
            {currentStep && (
              <div className="space-y-4">
                <div className="flex items-start gap-3">
                  <ShieldCheck className="mt-0.5 h-6 w-6 text-theme-interactive-primary" aria-hidden="true" />
                  <div>
                    <h2 className="text-lg font-semibold">{currentStep.title}</h2>
                    {currentStep.description && (
                      <p className="mt-1 text-sm text-theme-secondary">{currentStep.description}</p>
                    )}
                  </div>
                </div>

                {adminBlockedNoToken && (
                  <p
                    className="rounded-md border border-theme bg-theme-background-secondary p-3 text-xs text-theme-secondary"
                    data-testid="setup-token-missing"
                  >
                    This page needs the one-time setup link printed to the server console at first
                    boot (it contains a <code>?token=…</code>). Open that URL to continue.
                  </p>
                )}

                {isSchemaStep && currentStep.schema ? (
                  <SchemaStepForm
                    fields={currentStep.schema}
                    values={state.values[currentStep.key] ?? {}}
                    onChange={onValuesChange}
                    idPrefix={`setup-${currentStep.key}`}
                    disabled={state.submitting || adminBlockedNoToken}
                  />
                ) : currentStep.component && STEP_COMPONENTS[currentStep.component] ? (
                  React.createElement(STEP_COMPONENTS[currentStep.component], { step: currentStep })
                ) : (
                  <p className="text-sm text-theme-secondary">
                    This step is configured elsewhere and has no fields here.
                  </p>
                )}

                {state.error && (
                  <span
                    className="flex items-center gap-1 text-xs text-theme-danger-fg"
                    data-testid="setup-step-error"
                  >
                    <XCircle className="h-4 w-4" />
                    {state.error}
                  </span>
                )}
              </div>
            )}
          </section>

          <div className="flex items-center justify-end gap-2" data-testid="setup-wizard-footer">
            {currentStep && !currentStep.required && !isAdminStep && !isProviderStep && (
              <Button
                type="button"
                variant="ghost"
                size="sm"
                onClick={skipStep}
                disabled={state.submitting}
                data-testid="setup-skip-btn"
              >
                <SkipForward className="mr-1.5 h-3.5 w-3.5" />
                Skip
              </Button>
            )}

            {isAdminStep ? (
              <Button
                type="button"
                variant="primary"
                onClick={() => {
                  void submitAdmin();
                }}
                disabled={state.submitting || adminBlockedNoToken || !stepValid}
                loading={state.submitting}
                data-testid="setup-admin-create-btn"
              >
                Create administrator
                <ArrowRight className="ml-1.5 h-4 w-4" />
              </Button>
            ) : isProviderStep ? (
              <Button
                type="button"
                variant="primary"
                onClick={skipStep}
                disabled={state.submitting}
                data-testid="setup-continue-btn"
              >
                Continue
                <ArrowRight className="ml-1.5 h-4 w-4" />
              </Button>
            ) : (
              currentStep && (
                <Button
                  type="button"
                  variant="primary"
                  onClick={() => {
                    void submitStep(currentStep);
                  }}
                  disabled={state.submitting || (isSchemaStep && !stepValid)}
                  loading={state.submitting}
                  data-testid="setup-save-btn"
                >
                  {isSchemaStep ? 'Save & continue' : 'Continue'}
                  <ArrowRight className="ml-1.5 h-4 w-4" />
                </Button>
              )
            )}
          </div>
        </div>
      </main>
    </div>
  );
};

interface CenteredNoticeProps {
  icon: React.ReactNode;
  title: string;
  body: string;
  action?: React.ReactNode;
}

const CenteredNotice: React.FC<CenteredNoticeProps> = ({ icon, title, body, action }) => (
  <div
    className="flex min-h-screen w-full items-center justify-center bg-theme-background px-6 text-theme-primary"
    data-testid="setup-wizard-notice"
  >
    <div className="max-w-md space-y-3 rounded-lg border border-theme bg-theme-surface p-6 text-center shadow-sm">
      <div className="flex justify-center">{icon}</div>
      <h2 className="text-lg font-semibold">{title}</h2>
      <p className="text-sm text-theme-secondary">{body}</p>
      {action && <div className="pt-1">{action}</div>}
    </div>
  </div>
);

export default SetupWizard;
