import React, { useCallback, useEffect, useMemo, useReducer } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  ArrowLeft,
  ArrowRight,
  Brain,
  CheckCircle2,
  Cloud,
  GitBranch,
  PartyPopper,
  Rocket,
  Server,
  ShieldCheck,
  SkipForward,
  XCircle,
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { logger } from '@/shared/utils/logger';
import { onboardingApi } from './services/onboardingApi';
import {
  PROVIDER_FIELD_SCHEMAS,
  PROVIDER_LABELS,
  ProviderCredentialForm,
  type CredentialTestStatus,
  type ProviderCategory,
  type ProviderCredentialValues,
  type ProviderTypeSlug,
} from './ProviderCredentialForm';

const STEP_KEYS = [
  'welcome',
  'ai_provider',
  'cloud_provider',
  'git_provider',
  'complete',
] as const;
type StepKey = (typeof STEP_KEYS)[number];

const STEP_LABELS: Record<StepKey, string> = {
  welcome: 'Welcome',
  ai_provider: 'AI provider',
  cloud_provider: 'Cloud provider',
  git_provider: 'Git provider',
  complete: 'Seed templates',
};

const CATEGORY_FOR_STEP: Partial<Record<StepKey, ProviderCategory>> = {
  ai_provider: 'ai',
  cloud_provider: 'cloud',
  git_provider: 'git',
};

interface ProviderOption {
  type: ProviderTypeSlug;
  label: string;
  description: string;
  icon: React.ReactNode;
}

const PROVIDER_OPTIONS_BY_CATEGORY: Record<ProviderCategory, ReadonlyArray<ProviderOption>> = {
  ai: [
    {
      type: 'anthropic',
      label: 'Anthropic Claude',
      description: 'Recommended. Powers the concierge agent and provisioning chat.',
      icon: <Brain className="h-5 w-5" />,
    },
    {
      type: 'openai',
      label: 'OpenAI',
      description: 'GPT-4 / GPT-4o for chat and completions.',
      icon: <Brain className="h-5 w-5" />,
    },
    {
      type: 'ollama',
      label: 'Ollama (self-hosted)',
      description: 'Run open-weight models on your own hardware — no API keys needed.',
      icon: <Brain className="h-5 w-5" />,
    },
    {
      type: 'grok',
      label: 'xAI (Grok)',
      description: 'Grok-3 and Grok-vision via the xAI API.',
      icon: <Brain className="h-5 w-5" />,
    },
  ],
  cloud: [
    {
      type: 'local_qemu',
      label: 'Local KVM/QEMU',
      description: 'Run on the local hypervisor — recommended for first-time setup and on-box workloads.',
      icon: <Server className="h-5 w-5" />,
    },
    {
      type: 'proxmox',
      label: 'Proxmox VE',
      description: 'Spawn VMs + LXC containers on a Proxmox cluster via the PVE API.',
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
  ],
  git: [
    {
      type: 'github',
      label: 'GitHub',
      description: 'Public + private repos via personal access token.',
      icon: <GitBranch className="h-5 w-5" />,
    },
    {
      type: 'gitea',
      label: 'Gitea',
      description: 'Self-hosted Git provider — point at your own server.',
      icon: <GitBranch className="h-5 w-5" />,
    },
    {
      type: 'gitlab',
      label: 'GitLab',
      description: 'Hosted at gitlab.com or your own GitLab server.',
      icon: <GitBranch className="h-5 w-5" />,
    },
  ],
};

const CATEGORY_DESCRIPTIONS: Record<ProviderCategory, { title: string; subtitle: string }> = {
  ai: {
    title: 'Configure an AI provider',
    subtitle:
      'Powers the concierge agent and provisioning chat. You can wire up additional providers later from AI → Providers.',
  },
  cloud: {
    title: 'Connect a cloud provider',
    subtitle:
      'Where the AI will provision compute on your behalf. You can add more clouds later from System → Providers.',
  },
  git: {
    title: 'Connect a Git provider',
    subtitle:
      'Where source code lives for the deploy_app_code skill. Optional — skip if you only need infrastructure provisioning.',
  },
};

type SaveStatus = 'idle' | 'saving' | 'saved' | 'error' | 'skipped';
type CompleteStatus = 'idle' | 'completing' | 'done' | 'error';

interface CategoryProgress {
  providerType: ProviderTypeSlug | null;
  credentials: ProviderCredentialValues;
  credentialsValid: boolean;
  testStatus: CredentialTestStatus;
  saveStatus: SaveStatus;
  saveError: string | null;
  savedCredentialId: string | null;
  preExisting: boolean;
}

interface WizardState {
  step: StepKey;
  categories: Record<ProviderCategory, CategoryProgress>;
  statusLoaded: boolean;
  completeStatus: CompleteStatus;
  completeError: string | null;
}

type WizardAction =
  | { type: 'NEXT' }
  | { type: 'BACK' }
  | { type: 'SKIP_STEP' }
  | { type: 'STATUS_LOADED'; categories: Record<ProviderCategory, { has_credentials: boolean }> }
  | { type: 'SET_PROVIDER'; category: ProviderCategory; providerType: ProviderTypeSlug }
  | { type: 'SET_CREDENTIALS'; category: ProviderCategory; values: ProviderCredentialValues; valid: boolean }
  | { type: 'SET_TEST_STATUS'; category: ProviderCategory; status: CredentialTestStatus }
  | { type: 'SAVE_START'; category: ProviderCategory }
  | { type: 'SAVE_SUCCESS'; category: ProviderCategory; id: string | null }
  | { type: 'SAVE_FAILURE'; category: ProviderCategory; error: string }
  | { type: 'COMPLETE_START' }
  | { type: 'COMPLETE_SUCCESS' }
  | { type: 'COMPLETE_FAILURE'; error: string };

const initialCategoryState: CategoryProgress = {
  providerType: null,
  credentials: {},
  credentialsValid: false,
  testStatus: 'idle',
  saveStatus: 'idle',
  saveError: null,
  savedCredentialId: null,
  preExisting: false,
};

const initialState: WizardState = {
  step: 'welcome',
  categories: {
    ai: { ...initialCategoryState },
    cloud: { ...initialCategoryState },
    git: { ...initialCategoryState },
  },
  statusLoaded: false,
  completeStatus: 'idle',
  completeError: null,
};

const stepIndex = (key: StepKey): number => STEP_KEYS.indexOf(key);

const updateCategory = (
  state: WizardState,
  category: ProviderCategory,
  patch: Partial<CategoryProgress>
): WizardState => ({
  ...state,
  categories: {
    ...state.categories,
    [category]: { ...state.categories[category], ...patch },
  },
});

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
    case 'SKIP_STEP': {
      const category = CATEGORY_FOR_STEP[state.step];
      const idx = stepIndex(state.step);
      const next = idx < STEP_KEYS.length - 1 ? STEP_KEYS[idx + 1] : state.step;
      if (!category) return { ...state, step: next };
      return updateCategory({ ...state, step: next }, category, { saveStatus: 'skipped' });
    }
    case 'STATUS_LOADED': {
      const next = { ...state, statusLoaded: true };
      (Object.keys(action.categories) as ProviderCategory[]).forEach((cat) => {
        if (action.categories[cat].has_credentials) {
          next.categories = {
            ...next.categories,
            [cat]: { ...next.categories[cat], saveStatus: 'skipped', preExisting: true },
          };
        }
      });
      return next;
    }
    case 'SET_PROVIDER': {
      // Switching providers wipes any half-entered credentials so we never
      // accidentally POST aws keys with provider_type=hetzner.
      return updateCategory(state, action.category, {
        providerType: action.providerType,
        credentials: {},
        credentialsValid: false,
        testStatus: 'idle',
        saveStatus: 'idle',
        saveError: null,
        savedCredentialId: null,
      });
    }
    case 'SET_CREDENTIALS':
      return updateCategory(state, action.category, {
        credentials: action.values,
        credentialsValid: action.valid,
      });
    case 'SET_TEST_STATUS': {
      const cat = state.categories[action.category];
      // Only reset save state when test transitions FROM non-idle to idle/invalid
      // (i.e. user edited creds after a previous test). Initial 'idle' from form
      // mount must not clobber a successful save.
      const wasNonIdle = cat.testStatus !== 'idle';
      const isResetting = action.status === 'idle' || action.status === 'invalid';
      const reset = wasNonIdle && isResetting
        ? { saveStatus: 'idle' as SaveStatus, savedCredentialId: null, saveError: null }
        : {};
      return updateCategory(state, action.category, { testStatus: action.status, ...reset });
    }
    case 'SAVE_START':
      return updateCategory(state, action.category, { saveStatus: 'saving', saveError: null });
    case 'SAVE_SUCCESS':
      return updateCategory(state, action.category, {
        saveStatus: 'saved',
        savedCredentialId: action.id,
        saveError: null,
      });
    case 'SAVE_FAILURE':
      return updateCategory(state, action.category, { saveStatus: 'error', saveError: action.error });
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
    case 'ai_provider':
    case 'cloud_provider':
    case 'git_provider': {
      const category = CATEGORY_FOR_STEP[state.step];
      if (!category) return true;
      const cat = state.categories[category];
      // Advance once the category is saved OR explicitly skipped
      // (skip button) OR pre-existing (smart-skip from /onboarding/status).
      return cat.saveStatus === 'saved' || cat.saveStatus === 'skipped' || cat.preExisting;
    }
    case 'complete':
      return state.completeStatus === 'done';
    default:
      return false;
  }
};

export interface FirstRunWizardProps {
  /** Override the post-onboarding redirect target (defaults to /app/system/provision). */
  postOnboardingPath?: string;
  /** Test hook — invoked when wizard completes successfully. */
  onComplete?: () => void;
}

/**
 * FirstRunWizard — multi-category onboarding flow rendered at /app/onboarding.
 *
 * Steps (controlled by a `useReducer` state machine):
 *   1. Welcome — short copy + "Get started" CTA.
 *   2. AI provider — required for chat. Smart-skipped if Ai::ProviderCredential
 *      already exists for the account.
 *   3. Cloud provider — required for provisioning. Smart-skipped if
 *      System::ProviderCredential already exists.
 *   4. Git provider — optional. Smart-skipped if Devops::GitProviderCredential
 *      already exists.
 *   5. Seed templates — calls POST /api/v1/onboarding/complete which kicks
 *      AccountBootstrapService.seed_templates_for(account) and stamps
 *      account.metadata.onboarding_completed_at. On success → redirect to
 *      postOnboardingPath.
 *
 * Per-category "save" delegates to a per-category POST flow:
 *   - cloud: single POST /system/provider_credentials (auto-creates provider)
 *   - ai:    POST /ai/providers, then POST /ai/providers/:id/credentials
 *   - git:   POST /git/providers, then POST /git/providers/:id/credentials
 */
export const FirstRunWizard: React.FC<FirstRunWizardProps> = ({
  postOnboardingPath = '/app/system/provision',
  onComplete,
}) => {
  const navigate = useNavigate();
  const [state, dispatch] = useReducer(wizardReducer, initialState);

  // Smart-skip prefetch — fire once on mount. Categories that already have
  // credentials get marked 'skipped' so the wizard auto-advances past them.
  useEffect(() => {
    let cancelled = false;
    const loadStatus = async () => {
      try {
        const cats = await onboardingApi.getStatus();
        if (cancelled) return;
        dispatch({
          type: 'STATUS_LOADED',
          categories: {
            ai: { has_credentials: !!cats.ai?.has_credentials },
            cloud: { has_credentials: !!cats.cloud?.has_credentials },
            git: { has_credentials: !!cats.git?.has_credentials },
          },
        });
      } catch (err) {
        logger.error('FirstRunWizard: failed to load onboarding status', err);
        // Non-fatal — wizard still works, user just doesn't get smart-skip.
        dispatch({
          type: 'STATUS_LOADED',
          categories: {
            ai: { has_credentials: false },
            cloud: { has_credentials: false },
            git: { has_credentials: false },
          },
        });
      }
    };
    void loadStatus();
    return () => {
      cancelled = true;
    };
  }, []);

  // Auto-advance past pre-existing categories. Watches step + category state;
  // when on a provider step that's already 'skipped' (smart-skip), bump NEXT.
  useEffect(() => {
    if (!state.statusLoaded) return;
    const category = CATEGORY_FOR_STEP[state.step];
    if (!category) return;
    if (state.categories[category].preExisting) {
      // Defer to next tick so the dispatch lands cleanly.
      const t = window.setTimeout(() => dispatch({ type: 'NEXT' }), 0);
      return () => window.clearTimeout(t);
    }
    return undefined;
  }, [state.step, state.statusLoaded, state.categories]);

  // Compute current category once per render so handlers can close over a stable
  // value. Without this, inline arrow callbacks in JSX have a new identity each
  // render → ProviderCredentialForm's useEffect re-fires onChange → dispatch →
  // wizard re-renders → new arrow → infinite loop.
  const activeCategory = CATEGORY_FOR_STEP[state.step];

  const handleCredentialsChange = useCallback(
    (values: ProviderCredentialValues, valid: boolean) => {
      if (!activeCategory) return;
      dispatch({ type: 'SET_CREDENTIALS', category: activeCategory, values, valid });
    },
    [activeCategory]
  );

  const handleTestStatusChange = useCallback(
    (status: CredentialTestStatus) => {
      if (!activeCategory) return;
      dispatch({ type: 'SET_TEST_STATUS', category: activeCategory, status });
    },
    [activeCategory]
  );


  const persistCredentials = useCallback(
    async (category: ProviderCategory) => {
      const cat = state.categories[category];
      if (!cat.providerType) return;
      dispatch({ type: 'SAVE_START', category });
      try {
        let credentialId: string | null = null;

        if (category === 'cloud') {
          // Single POST — backend auto-creates the provider.
          credentialId = await onboardingApi.createCloudCredential({
            providerType: cat.providerType,
            credentials: cat.credentials,
          });
        } else if (category === 'ai') {
          // Two-step: create provider, then create credential under it.
          const providerId = await onboardingApi.createAiProvider({
            providerType: cat.providerType,
            name: PROVIDER_LABELS.ai[cat.providerType] ?? cat.providerType,
          });
          if (!providerId) throw new Error('AI provider creation did not return an id');
          credentialId = await onboardingApi.createAiCredential({
            providerId,
            credentials: cat.credentials,
          });
        } else if (category === 'git') {
          const providerId = await onboardingApi.createGitProvider({
            providerType: cat.providerType,
            name: PROVIDER_LABELS.git[cat.providerType] ?? cat.providerType,
          });
          if (!providerId) throw new Error('Git provider creation did not return an id');
          credentialId = await onboardingApi.createGitCredential({
            providerId,
            credentials: cat.credentials,
          });
        }

        dispatch({ type: 'SAVE_SUCCESS', category, id: credentialId });
      } catch (err) {
        logger.error('FirstRunWizard: failed to persist credentials', err, { category });
        dispatch({
          type: 'SAVE_FAILURE',
          category,
          error: err instanceof Error ? err.message : 'Failed to save credentials. Please retry.',
        });
      }
    },
    [state.categories]
  );

  const completeOnboarding = useCallback(async () => {
    dispatch({ type: 'COMPLETE_START' });
    try {
      // Surface whichever credential closed the loop most recently — used
      // by the backend's audit trail (metadata.last_provider_credential_id).
      const lastCategoryWithCredential = (['cloud', 'ai', 'git'] as ProviderCategory[])
        .map((c) => state.categories[c])
        .find((c) => c.savedCredentialId);
      await onboardingApi.complete({
        providerCredentialId: lastCategoryWithCredential?.savedCredentialId ?? null,
        providerType: lastCategoryWithCredential?.providerType ?? null,
      });
      dispatch({ type: 'COMPLETE_SUCCESS' });
    } catch (err) {
      logger.error('FirstRunWizard: failed to complete onboarding', err);
      dispatch({
        type: 'COMPLETE_FAILURE',
        error: err instanceof Error ? err.message : 'Failed to seed templates. Please retry.',
      });
    }
  }, [state.categories]);

  // After the final POST resolves, redirect to the chat surface.
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

  const currentCategory = CATEGORY_FOR_STEP[state.step];

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
          <StepProgress current={state.step} categories={state.categories} />

          <section
            className="rounded-lg border border-theme bg-theme-surface p-5 shadow-sm"
            data-testid={`first-run-step-${state.step}`}
          >
            {state.step === 'welcome' && <WelcomeStep />}

            {currentCategory && (
              <CategoryStep
                category={currentCategory}
                progress={state.categories[currentCategory]}
                onSelectProvider={(providerType) =>
                  dispatch({ type: 'SET_PROVIDER', category: currentCategory, providerType })
                }
                onValuesChange={handleCredentialsChange}
                onTestStatusChange={handleTestStatusChange}
                onSave={() => persistCredentials(currentCategory)}
              />
            )}

            {state.step === 'complete' && (
              <CompleteStep
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

            <div className="flex items-center gap-2">
              {currentCategory && state.categories[currentCategory].saveStatus !== 'saved' && (
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  onClick={() => dispatch({ type: 'SKIP_STEP' })}
                  data-testid="first-run-skip-btn"
                >
                  <SkipForward className="mr-1.5 h-3.5 w-3.5" />
                  Skip
                </Button>
              )}

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
        </div>
      </main>
    </div>
  );
};

interface StepProgressProps {
  current: StepKey;
  categories: WizardState['categories'];
}

const StepProgress: React.FC<StepProgressProps> = ({ current, categories }) => {
  const currentIdx = stepIndex(current);
  return (
    <ol className="flex items-center gap-2" data-testid="first-run-step-progress">
      {STEP_KEYS.map((key, idx) => {
        const reached = idx <= currentIdx;
        const category = CATEGORY_FOR_STEP[key];
        const skipped = category && categories[category].saveStatus === 'skipped';
        const preExisting = category && categories[category].preExisting;
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
              {(skipped || preExisting) && (
                <span className="ml-1 text-theme-tertiary">{preExisting ? '(configured)' : '(skipped)'}</span>
              )}
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
        <h2 className="text-lg font-semibold">Connect your providers</h2>
        <p className="mt-1 text-sm text-theme-secondary">
          Powernode talks to your AI, cloud, and Git providers using credentials you supply.
          We&apos;ll walk you through each one — skip any you don&apos;t need yet.
        </p>
      </div>
    </div>
    <ol className="list-decimal space-y-1 pl-6 text-sm text-theme-secondary">
      <li>AI provider — powers the concierge agent and provisioning chat.</li>
      <li>Cloud provider — where the AI provisions infrastructure on your behalf.</li>
      <li>Git provider — for the deploy_app_code skill (optional).</li>
      <li>Seed templates so the AI has something to plan against.</li>
    </ol>
    <p className="text-xs text-theme-tertiary">
      Credentials are encrypted at rest by Rails attribute encryption and never written to logs.
    </p>
  </div>
);

interface CategoryStepProps {
  category: ProviderCategory;
  progress: CategoryProgress;
  onSelectProvider: (providerType: ProviderTypeSlug) => void;
  onValuesChange: (values: ProviderCredentialValues, valid: boolean) => void;
  onTestStatusChange: (status: CredentialTestStatus) => void;
  onSave: () => Promise<void>;
}

const CategoryStep: React.FC<CategoryStepProps> = ({
  category,
  progress,
  onSelectProvider,
  onValuesChange,
  onTestStatusChange,
  onSave,
}) => {
  const options = PROVIDER_OPTIONS_BY_CATEGORY[category];
  const meta = CATEGORY_DESCRIPTIONS[category];
  // Cloud is the only category that exposes a test endpoint today.
  const supportsTest = category === 'cloud';
  // local_qemu inside cloud doesn't need credentials at all.
  const requiresTest = supportsTest && progress.providerType !== 'local_qemu';

  const saveDisabled =
    !progress.providerType ||
    !progress.credentialsValid ||
    progress.saveStatus === 'saving' ||
    (requiresTest && progress.testStatus !== 'valid');

  return (
    <div className="space-y-4" data-testid={`first-run-${category}-step`}>
      <div>
        <h2 className="text-lg font-semibold">{meta.title}</h2>
        <p className="mt-1 text-sm text-theme-secondary">{meta.subtitle}</p>
      </div>

      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        {options.map((option) => {
          const isActive = progress.providerType === option.type;
          return (
            <button
              key={option.type}
              type="button"
              onClick={() => onSelectProvider(option.type)}
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

      {progress.providerType && PROVIDER_FIELD_SCHEMAS[category]?.[progress.providerType] && (
        <>
          <ProviderCredentialForm
            category={category}
            providerType={progress.providerType}
            initialValues={progress.credentials}
            onChange={onValuesChange}
            onTestStatusChange={onTestStatusChange}
            hideTestButton={!requiresTest}
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
              loading={progress.saveStatus === 'saving'}
              data-testid="first-run-save-btn"
            >
              {progress.saveStatus === 'saved' ? 'Saved' : 'Save credentials'}
            </Button>

            {progress.saveStatus === 'saved' && (
              <span
                className="flex items-center gap-1 text-xs text-theme-success"
                data-testid="first-run-save-success"
              >
                <CheckCircle2 className="h-4 w-4" />
                Stored credentials for {PROVIDER_LABELS[category][progress.providerType]}.
              </span>
            )}

            {progress.saveStatus === 'error' && progress.saveError && (
              <span
                className="flex items-center gap-1 text-xs text-theme-danger"
                data-testid="first-run-save-error"
              >
                <XCircle className="h-4 w-4" />
                {progress.saveError}
              </span>
            )}
          </div>
        </>
      )}
    </div>
  );
};

interface CompleteStepProps {
  completeStatus: CompleteStatus;
  completeError: string | null;
  onSeed: () => Promise<void>;
}

const CompleteStep: React.FC<CompleteStepProps> = ({ completeStatus, completeError, onSeed }) => (
  <div className="space-y-3" data-testid="first-run-complete">
    <div className="flex items-start gap-3">
      <PartyPopper className="mt-0.5 h-6 w-6 text-theme-interactive-primary" />
      <div>
        <h2 className="text-lg font-semibold">Almost there</h2>
        <p className="mt-1 text-sm text-theme-secondary">
          We&apos;ll seed a starter template library so the AI has something to plan against,
          then drop you into the chat.
        </p>
      </div>
    </div>

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
      {completeStatus === 'done' ? (
        <>
          <CheckCircle2 className="mr-1.5 h-4 w-4" />
          Seeded
        </>
      ) : (
        'Seed templates'
      )}
    </Button>

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
);

export default FirstRunWizard;
