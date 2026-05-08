import React, { useCallback, useEffect, useMemo, useReducer } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  ArrowLeft,
  ArrowRight,
  CheckCircle2,
  Cloud,
  Loader2,
  PartyPopper,
  Rocket,
  Server,
  ShieldCheck,
  XCircle,
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { logger } from '@/shared/utils/logger';
import apiClient from '@/shared/services/apiClient';
import {
  PROVIDER_FIELD_SCHEMAS,
  PROVIDER_LABELS,
  ProviderCredentialForm,
  type CredentialTestStatus,
  type OnboardingProviderType,
  type ProviderCredentialValues,
} from './ProviderCredentialForm';

const STEP_KEYS = ['welcome', 'provider', 'credentials', 'complete'] as const;
type StepKey = (typeof STEP_KEYS)[number];

const STEP_LABELS: Record<StepKey, string> = {
  welcome: 'Welcome',
  provider: 'Choose provider',
  credentials: 'Enter credentials',
  complete: 'Seed templates',
};

const PROVIDER_OPTIONS: ReadonlyArray<{
  type: OnboardingProviderType;
  label: string;
  description: string;
  icon: React.ReactNode;
}> = [
  {
    type: 'localqemu',
    label: 'LocalQemu',
    description: 'Smoke test on the local hypervisor — recommended for first-time setup.',
    icon: <Server className="h-5 w-5" />,
  },
  {
    type: 'aws',
    label: 'Amazon Web Services',
    description: 'EC2 + S3 + Route53 across all AWS regions.',
    icon: <Cloud className="h-5 w-5" />,
  },
  {
    type: 'hetzner',
    label: 'Hetzner Cloud',
    description: 'Cost-efficient EU/US compute with hourly billing.',
    icon: <Cloud className="h-5 w-5" />,
  },
  {
    type: 'digitalocean',
    label: 'DigitalOcean',
    description: 'Droplets + Spaces + Load Balancers in 13+ regions.',
    icon: <Cloud className="h-5 w-5" />,
  },
  {
    type: 'vultr',
    label: 'Vultr',
    description: 'High-frequency compute and bare metal.',
    icon: <Cloud className="h-5 w-5" />,
  },
  {
    type: 'gcp',
    label: 'Google Cloud Platform',
    description: 'Compute Engine + GCS + IAM via service account JSON.',
    icon: <Cloud className="h-5 w-5" />,
  },
  {
    type: 'azure',
    label: 'Microsoft Azure',
    description: 'Virtual Machines + Storage + RBAC via service principal.',
    icon: <Cloud className="h-5 w-5" />,
  },
];

interface SaveResponseEnvelope {
  data?: { id?: string };
  id?: string;
}

interface CompleteResponseEnvelope {
  data?: { onboarding_completed_at?: string | null };
  onboarding_completed_at?: string | null;
}

type SaveStatus = 'idle' | 'saving' | 'saved' | 'error';
type CompleteStatus = 'idle' | 'completing' | 'done' | 'error';

interface WizardState {
  step: StepKey;
  providerType: OnboardingProviderType | null;
  credentials: ProviderCredentialValues;
  credentialsValid: boolean;
  testStatus: CredentialTestStatus;
  saveStatus: SaveStatus;
  saveError: string | null;
  savedCredentialId: string | null;
  completeStatus: CompleteStatus;
  completeError: string | null;
}

type WizardAction =
  | { type: 'NEXT' }
  | { type: 'BACK' }
  | { type: 'SET_PROVIDER'; provider: OnboardingProviderType }
  | { type: 'SET_CREDENTIALS'; values: ProviderCredentialValues; valid: boolean }
  | { type: 'SET_TEST_STATUS'; status: CredentialTestStatus }
  | { type: 'SAVE_START' }
  | { type: 'SAVE_SUCCESS'; id: string | null }
  | { type: 'SAVE_FAILURE'; error: string }
  | { type: 'COMPLETE_START' }
  | { type: 'COMPLETE_SUCCESS' }
  | { type: 'COMPLETE_FAILURE'; error: string };

const initialState: WizardState = {
  step: 'welcome',
  providerType: null,
  credentials: {},
  credentialsValid: false,
  testStatus: 'idle',
  saveStatus: 'idle',
  saveError: null,
  savedCredentialId: null,
  completeStatus: 'idle',
  completeError: null,
};

const stepIndex = (key: StepKey): number => STEP_KEYS.indexOf(key);

const wizardReducer = (state: WizardState, action: WizardAction): WizardState => {
  switch (action.type) {
    case 'NEXT': {
      const idx = stepIndex(state.step);
      if (idx >= STEP_KEYS.length - 1) return state;
      return { ...state, step: STEP_KEYS[idx + 1] };
    }
    case 'BACK': {
      const idx = stepIndex(state.step);
      if (idx <= 0) return state;
      return { ...state, step: STEP_KEYS[idx - 1] };
    }
    case 'SET_PROVIDER': {
      // Switching providers wipes any half-entered credentials so we never
      // accidentally POST aws keys with provider_type=hetzner.
      return {
        ...state,
        providerType: action.provider,
        credentials: {},
        credentialsValid: false,
        testStatus: 'idle',
        saveStatus: 'idle',
        saveError: null,
        savedCredentialId: null,
      };
    }
    case 'SET_CREDENTIALS':
      return {
        ...state,
        credentials: action.values,
        credentialsValid: action.valid,
      };
    case 'SET_TEST_STATUS': {
      // A new test result invalidates any prior save — operator must save again.
      const reset =
        action.status === 'idle' || action.status === 'invalid'
          ? { saveStatus: 'idle' as const, savedCredentialId: null, saveError: null }
          : {};
      return { ...state, testStatus: action.status, ...reset };
    }
    case 'SAVE_START':
      return { ...state, saveStatus: 'saving', saveError: null };
    case 'SAVE_SUCCESS':
      return {
        ...state,
        saveStatus: 'saved',
        savedCredentialId: action.id,
        saveError: null,
      };
    case 'SAVE_FAILURE':
      return { ...state, saveStatus: 'error', saveError: action.error };
    case 'COMPLETE_START':
      return { ...state, completeStatus: 'completing', completeError: null };
    case 'COMPLETE_SUCCESS':
      return { ...state, completeStatus: 'done', completeError: null };
    case 'COMPLETE_FAILURE':
      return { ...state, completeStatus: 'error', completeError: action.error };
    default:
      return state;
  }
};

const canProceed = (state: WizardState): boolean => {
  switch (state.step) {
    case 'welcome':
      return true;
    case 'provider':
      return state.providerType !== null;
    case 'credentials':
      // To move to the final "Seed templates" step we require:
      //   - the BYOC test endpoint accepted the creds (or the provider has no
      //     remote creds — currently only LocalQemu)
      //   - the credential record was saved successfully
      if (state.providerType === 'localqemu') {
        return state.saveStatus === 'saved';
      }
      return state.testStatus === 'valid' && state.saveStatus === 'saved';
    case 'complete':
      return state.completeStatus === 'done';
    default:
      return false;
  }
};

export interface FirstRunWizardProps {
  /** Override the post-onboarding redirect target (defaults to `/new`). */
  postOnboardingPath?: string;
  /** Test hook — invoked when wizard completes successfully. */
  onComplete?: () => void;
}

/**
 * FirstRunWizard — 4-step BYOC onboarding flow rendered at `/onboarding`.
 *
 * Steps (controlled by a `useReducer` state machine):
 *   1. Welcome — short copy + "Get started" CTA.
 *   2. Choose provider — card grid; selection unlocks step 3.
 *   3. Enter credentials — `<ProviderCredentialForm />` with Test + Save.
 *   4. Seed templates — calls `POST /api/v1/onboarding/complete` which kicks
 *      `AccountBootstrapService.seed_templates_for(account)` and stamps
 *      `account.metadata.onboarding_completed_at`. On success → redirect to /new.
 */
export const FirstRunWizard: React.FC<FirstRunWizardProps> = ({
  postOnboardingPath = '/new',
  onComplete,
}) => {
  const navigate = useNavigate();
  const [state, dispatch] = useReducer(wizardReducer, initialState);

  const handleCredentialsChange = useCallback(
    (values: ProviderCredentialValues, valid: boolean) => {
      dispatch({ type: 'SET_CREDENTIALS', values, valid });
    },
    []
  );

  const handleTestStatusChange = useCallback((status: CredentialTestStatus) => {
    dispatch({ type: 'SET_TEST_STATUS', status });
  }, []);

  const persistCredentials = useCallback(async () => {
    if (!state.providerType) return;
    dispatch({ type: 'SAVE_START' });
    try {
      const response = await apiClient.post<SaveResponseEnvelope>(
        '/system/provider_credentials',
        {
          provider_id: state.providerType,
          provider_type: state.providerType,
          credentials: state.credentials,
        }
      );
      const envelope = response.data ?? {};
      const inner = envelope.data ?? envelope;
      dispatch({ type: 'SAVE_SUCCESS', id: inner.id ?? null });
    } catch (err) {
      logger.error('FirstRunWizard: failed to persist credentials', err, {
        providerType: state.providerType,
      });
      dispatch({
        type: 'SAVE_FAILURE',
        error:
          err instanceof Error
            ? err.message
            : 'Failed to save credentials. Please retry.',
      });
    }
  }, [state.providerType, state.credentials]);

  const completeOnboarding = useCallback(async () => {
    dispatch({ type: 'COMPLETE_START' });
    try {
      await apiClient.post<CompleteResponseEnvelope>('/onboarding/complete', {
        provider_credential_id: state.savedCredentialId,
        provider_type: state.providerType,
      });
      dispatch({ type: 'COMPLETE_SUCCESS' });
    } catch (err) {
      logger.error('FirstRunWizard: failed to complete onboarding', err);
      dispatch({
        type: 'COMPLETE_FAILURE',
        error:
          err instanceof Error
            ? err.message
            : 'Failed to seed templates. Please retry.',
      });
    }
  }, [state.savedCredentialId, state.providerType]);

  // After the final POST resolves, redirect to the chat surface so the operator
  // lands on something productive instead of a stale wizard.
  useEffect(() => {
    if (state.completeStatus === 'done') {
      onComplete?.();
      navigate(postOnboardingPath, { replace: true });
    }
  }, [state.completeStatus, navigate, postOnboardingPath, onComplete]);

  const advanceDisabled = !canProceed(state);

  const headerSubtitle = useMemo(
    () =>
      `Step ${stepIndex(state.step) + 1} of ${STEP_KEYS.length} · ${STEP_LABELS[state.step]}`,
    [state.step]
  );

  return (
    <div
      className="flex min-h-screen w-full flex-col bg-theme-background text-theme-primary"
      data-testid="first-run-wizard"
    >
      <header className="border-b border-theme bg-theme-surface px-6 py-4">
        <div className="mx-auto flex max-w-3xl items-center gap-3">
          <Rocket className="h-5 w-5 text-theme-interactive-primary" aria-hidden="true" />
          <div className="min-w-0">
            <h1 className="text-base font-semibold">Get Powernode running</h1>
            <p className="text-xs text-theme-secondary">{headerSubtitle}</p>
          </div>
        </div>
      </header>

      <main className="flex-1 px-6 py-6">
        <div className="mx-auto max-w-3xl space-y-5">
          <StepProgress current={state.step} />

          <section
            className="rounded-lg border border-theme bg-theme-surface p-5 shadow-sm"
            data-testid={`first-run-step-${state.step}`}
          >
            {state.step === 'welcome' && <WelcomeStep />}

            {state.step === 'provider' && (
              <ProviderStep
                selected={state.providerType}
                onSelect={(provider) =>
                  dispatch({ type: 'SET_PROVIDER', provider })
                }
              />
            )}

            {state.step === 'credentials' && state.providerType && (
              <CredentialsStep
                providerType={state.providerType}
                values={state.credentials}
                credentialsValid={state.credentialsValid}
                testStatus={state.testStatus}
                saveStatus={state.saveStatus}
                saveError={state.saveError}
                onValuesChange={handleCredentialsChange}
                onTestStatusChange={handleTestStatusChange}
                onSave={persistCredentials}
              />
            )}

            {state.step === 'complete' && (
              <CompleteStep
                providerLabel={
                  state.providerType ? PROVIDER_LABELS[state.providerType] : 'your provider'
                }
                completeStatus={state.completeStatus}
                completeError={state.completeError}
                onSeed={completeOnboarding}
              />
            )}
          </section>

          <div
            className="flex items-center justify-between"
            data-testid="first-run-wizard-footer"
          >
            <Button
              type="button"
              variant="ghost"
              onClick={() => dispatch({ type: 'BACK' })}
              disabled={state.step === 'welcome' || state.completeStatus === 'completing'}
              data-testid="first-run-back-btn"
            >
              <ArrowLeft className="mr-1.5 h-4 w-4" />
              Back
            </Button>

            {state.step === 'complete' ? (
              <Button
                type="button"
                variant="primary"
                onClick={() => navigate(postOnboardingPath, { replace: true })}
                disabled={state.completeStatus !== 'done'}
                data-testid="first-run-finish-btn"
              >
                Open chat
                <ArrowRight className="ml-1.5 h-4 w-4" />
              </Button>
            ) : (
              <Button
                type="button"
                variant="primary"
                onClick={() => dispatch({ type: 'NEXT' })}
                disabled={advanceDisabled}
                data-testid="first-run-next-btn"
              >
                Next
                <ArrowRight className="ml-1.5 h-4 w-4" />
              </Button>
            )}
          </div>
        </div>
      </main>
    </div>
  );
};

interface StepProgressProps {
  current: StepKey;
}

const StepProgress: React.FC<StepProgressProps> = ({ current }) => {
  const currentIdx = stepIndex(current);
  return (
    <ol className="flex items-center gap-2" data-testid="first-run-step-progress">
      {STEP_KEYS.map((key, idx) => {
        const reached = idx <= currentIdx;
        return (
          <li key={key} className="flex flex-1 items-center gap-2">
            <span
              className={`flex h-6 w-6 items-center justify-center rounded-full text-xs font-semibold ${
                reached
                  ? 'bg-theme-interactive-primary text-white'
                  : 'bg-theme-background-secondary text-theme-tertiary'
              }`}
              aria-current={idx === currentIdx ? 'step' : undefined}
            >
              {idx + 1}
            </span>
            <span
              className={`hidden text-xs sm:inline ${
                reached ? 'text-theme-primary' : 'text-theme-tertiary'
              }`}
            >
              {STEP_LABELS[key]}
            </span>
            {idx < STEP_KEYS.length - 1 && (
              <span
                className={`h-0.5 flex-1 rounded-full ${
                  idx < currentIdx
                    ? 'bg-theme-interactive-primary'
                    : 'bg-theme-background-secondary'
                }`}
              />
            )}
          </li>
        );
      })}
    </ol>
  );
};

const WelcomeStep: React.FC = () => (
  <div className="space-y-3" data-testid="first-run-welcome">
    <div className="flex items-start gap-3">
      <ShieldCheck className="mt-0.5 h-6 w-6 text-theme-interactive-primary" />
      <div>
        <h2 className="text-lg font-semibold">Bring your own cloud</h2>
        <p className="mt-1 text-sm text-theme-secondary">
          Powernode provisions infrastructure on your behalf using credentials you supply.
          We&apos;ll walk you through three quick steps:
        </p>
      </div>
    </div>
    <ol className="list-decimal space-y-1 pl-6 text-sm text-theme-secondary">
      <li>Choose a cloud provider.</li>
      <li>Paste a least-privilege API key — we test it before saving.</li>
      <li>Seed a starter template library so the AI has something to plan against.</li>
    </ol>
    <p className="text-xs text-theme-tertiary">
      Credentials are encrypted at rest by Rails attribute encryption and never written to logs.
    </p>
  </div>
);

interface ProviderStepProps {
  selected: OnboardingProviderType | null;
  onSelect: (provider: OnboardingProviderType) => void;
}

const ProviderStep: React.FC<ProviderStepProps> = ({ selected, onSelect }) => (
  <div className="space-y-3" data-testid="first-run-provider-step">
    <div>
      <h2 className="text-lg font-semibold">Pick a provider</h2>
      <p className="mt-1 text-sm text-theme-secondary">
        You can add more providers later from System → Providers.
      </p>
    </div>
    <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
      {PROVIDER_OPTIONS.map((option) => {
        const isActive = selected === option.type;
        return (
          <button
            key={option.type}
            type="button"
            onClick={() => onSelect(option.type)}
            className={`flex items-start gap-3 rounded-lg border p-3 text-left transition-colors ${
              isActive
                ? 'border-theme-interactive-primary bg-theme-interactive-primary/10'
                : 'border-theme bg-theme-surface hover:border-theme-interactive-primary/40'
            }`}
            data-testid={`first-run-provider-${option.type}`}
            aria-pressed={isActive}
          >
            <span
              className={`flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-md ${
                isActive
                  ? 'bg-theme-interactive-primary/20 text-theme-interactive-primary'
                  : 'bg-theme-background-secondary text-theme-secondary'
              }`}
            >
              {option.icon}
            </span>
            <div className="min-w-0">
              <p className="text-sm font-medium text-theme-primary">{option.label}</p>
              <p className="mt-0.5 text-xs text-theme-secondary">{option.description}</p>
            </div>
            {isActive && (
              <CheckCircle2
                className="ml-auto h-4 w-4 flex-shrink-0 text-theme-interactive-primary"
                aria-hidden="true"
              />
            )}
          </button>
        );
      })}
    </div>
  </div>
);

interface CredentialsStepProps {
  providerType: OnboardingProviderType;
  values: ProviderCredentialValues;
  credentialsValid: boolean;
  testStatus: CredentialTestStatus;
  saveStatus: SaveStatus;
  saveError: string | null;
  onValuesChange: (values: ProviderCredentialValues, valid: boolean) => void;
  onTestStatusChange: (status: CredentialTestStatus) => void;
  onSave: () => Promise<void>;
}

const CredentialsStep: React.FC<CredentialsStepProps> = ({
  providerType,
  values,
  credentialsValid,
  testStatus,
  saveStatus,
  saveError,
  onValuesChange,
  onTestStatusChange,
  onSave,
}) => {
  // LocalQemu has no remote credentials so we don't require a green test
  // before save. For remote providers we gate save on a successful test.
  const requiresTest = providerType !== 'localqemu';
  const saveDisabled =
    !credentialsValid ||
    saveStatus === 'saving' ||
    (requiresTest && testStatus !== 'valid');

  // A schema with at least one field; LocalQemu has only the libvirt URI.
  const fieldCount = PROVIDER_FIELD_SCHEMAS[providerType].length;

  return (
    <div className="space-y-4" data-testid="first-run-credentials-step">
      <div>
        <h2 className="text-lg font-semibold">
          Connect to {PROVIDER_LABELS[providerType]}
        </h2>
        <p className="mt-1 text-sm text-theme-secondary">
          {requiresTest
            ? 'Paste your credentials, run the test, then save.'
            : 'LocalQemu uses your local hypervisor — no remote credentials are sent.'}
        </p>
      </div>

      <ProviderCredentialForm
        providerType={providerType}
        initialValues={values}
        onChange={onValuesChange}
        onTestStatusChange={onTestStatusChange}
      />

      <div className="flex flex-wrap items-center gap-3 border-t border-theme pt-3">
        <Button
          type="button"
          variant="primary"
          size="sm"
          onClick={() => {
            void onSave();
          }}
          disabled={saveDisabled}
          loading={saveStatus === 'saving'}
          data-testid="first-run-save-btn"
        >
          {saveStatus === 'saved' ? 'Saved' : 'Save credentials'}
        </Button>

        {saveStatus === 'saved' && (
          <span
            className="flex items-center gap-1 text-xs text-theme-success"
            data-testid="first-run-save-success"
          >
            <CheckCircle2 className="h-4 w-4" />
            Stored {fieldCount === 1 ? 'value' : 'credentials'} for{' '}
            {PROVIDER_LABELS[providerType]}.
          </span>
        )}

        {saveStatus === 'error' && saveError && (
          <span
            className="flex items-center gap-1 text-xs text-theme-danger"
            data-testid="first-run-save-error"
          >
            <XCircle className="h-4 w-4" />
            {saveError}
          </span>
        )}
      </div>
    </div>
  );
};

interface CompleteStepProps {
  providerLabel: string;
  completeStatus: CompleteStatus;
  completeError: string | null;
  onSeed: () => Promise<void>;
}

const CompleteStep: React.FC<CompleteStepProps> = ({
  providerLabel,
  completeStatus,
  completeError,
  onSeed,
}) => (
  <div className="space-y-4" data-testid="first-run-complete-step">
    <div className="flex items-start gap-3">
      <PartyPopper className="mt-0.5 h-6 w-6 text-theme-success" />
      <div>
        <h2 className="text-lg font-semibold">Almost there</h2>
        <p className="mt-1 text-sm text-theme-secondary">
          Powernode will seed a starter template library for {providerLabel} so the AI has
          stacks to plan against. This usually takes a few seconds.
        </p>
      </div>
    </div>

    <div className="flex flex-wrap items-center gap-3">
      <Button
        type="button"
        variant="primary"
        onClick={() => {
          void onSeed();
        }}
        disabled={completeStatus === 'completing' || completeStatus === 'done'}
        loading={completeStatus === 'completing'}
        data-testid="first-run-seed-btn"
      >
        {completeStatus === 'done' ? 'Templates seeded' : 'Seed starter templates'}
      </Button>

      {completeStatus === 'completing' && (
        <span
          className="flex items-center gap-1 text-xs text-theme-secondary"
          data-testid="first-run-seed-pending"
        >
          <Loader2 className="h-3.5 w-3.5 animate-spin" />
          Seeding…
        </span>
      )}

      {completeStatus === 'done' && (
        <span
          className="flex items-center gap-1 text-xs text-theme-success"
          data-testid="first-run-seed-success"
        >
          <CheckCircle2 className="h-4 w-4" />
          You&apos;re ready — opening chat…
        </span>
      )}

      {completeStatus === 'error' && completeError && (
        <span
          className="flex items-center gap-1 text-xs text-theme-danger"
          data-testid="first-run-seed-error"
        >
          <XCircle className="h-4 w-4" />
          {completeError}
        </span>
      )}
    </div>
  </div>
);

export default FirstRunWizard;
