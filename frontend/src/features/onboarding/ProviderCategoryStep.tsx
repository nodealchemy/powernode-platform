import React from 'react';
import { Brain, CheckCircle2, Cloud, GitBranch, Server, XCircle } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import {
  PROVIDER_FIELD_SCHEMAS,
  PROVIDER_LABELS,
  ProviderCredentialForm,
  type CredentialTestStatus,
  type ProviderCategory,
  type ProviderCredentialValues,
  type ProviderTypeSlug,
} from './ProviderCredentialForm';

export type SaveStatus = 'idle' | 'saving' | 'saved' | 'error' | 'skipped';

/** Per-category progress consumed by the provider step. */
export interface CategoryProgress {
  providerType: ProviderTypeSlug | null;
  credentials: ProviderCredentialValues;
  credentialsValid: boolean;
  testStatus: CredentialTestStatus;
  saveStatus: SaveStatus;
  saveError: string | null;
}

interface ProviderOption {
  type: ProviderTypeSlug;
  label: string;
  description: string;
  icon: React.ReactNode;
}

export const PROVIDER_OPTIONS_BY_CATEGORY: Record<ProviderCategory, ReadonlyArray<ProviderOption>> = {
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
      description:
        "Runs on this host via libvirt/virsh — requires libvirt installed locally. New here and don't have libvirt? Start with a hosted provider like Proxmox VE instead.",
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

export const CATEGORY_DESCRIPTIONS: Record<ProviderCategory, { title: string; subtitle: string }> = {
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

export interface ProviderCategoryStepProps {
  category: ProviderCategory;
  progress: CategoryProgress;
  onSelectProvider: (providerType: ProviderTypeSlug) => void;
  onValuesChange: (values: ProviderCredentialValues, valid: boolean) => void;
  onTestStatusChange: (status: CredentialTestStatus) => void;
  onSave: () => Promise<void>;
  /** Test-hook prefix so the onboarding ("first-run") and setup wizards keep distinct ids. */
  testIdPrefix?: string;
}

/**
 * Provider-selection + credential-entry step for one category (ai/cloud/git).
 * Presentational — the caller owns the per-category state and persistence. Shared
 * by FirstRunWizard (testIdPrefix "first-run") and the setup wizard's ProviderStep.
 */
export const ProviderCategoryStep: React.FC<ProviderCategoryStepProps> = ({
  category,
  progress,
  onSelectProvider,
  onValuesChange,
  onTestStatusChange,
  onSave,
  testIdPrefix = 'first-run',
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
    <div className="space-y-4" data-testid={`${testIdPrefix}-${category}-step`}>
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
              data-testid={`${testIdPrefix}-provider-${option.type}`}
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
              data-testid={`${testIdPrefix}-save-btn`}
            >
              {progress.saveStatus === 'saved' ? 'Saved' : 'Save credentials'}
            </Button>

            {progress.saveStatus === 'saved' && (
              <span
                className="flex items-center gap-1 text-xs text-theme-success-fg"
                data-testid={`${testIdPrefix}-save-success`}
              >
                <CheckCircle2 className="h-4 w-4" />
                Stored credentials for {PROVIDER_LABELS[category][progress.providerType]}.
              </span>
            )}

            {progress.saveStatus === 'error' && progress.saveError && (
              <span
                className="flex items-center gap-1 text-xs text-theme-danger-fg"
                data-testid={`${testIdPrefix}-save-error`}
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

export default ProviderCategoryStep;
