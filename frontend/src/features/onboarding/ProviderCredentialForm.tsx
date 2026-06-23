import React, { useEffect, useMemo, useState } from 'react';
import { AlertCircle, CheckCircle2, Loader2, ShieldCheck, XCircle } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { logger } from '@/shared/utils/logger';
import { onboardingApi } from './services/onboardingApi';

/**
 * Provider categories supported by the unified onboarding wizard.
 *
 * Each category routes to a different credential-create surface:
 *   - ai:    POST /ai/providers + POST /ai/providers/:id/credentials
 *   - cloud: POST /system/provider_credentials (auto-creates provider)
 *   - git:   POST /git/providers + POST /git/providers/:id/credentials
 */
export type ProviderCategory = 'ai' | 'cloud' | 'git';

export type ProviderTypeSlug = string;

export type ProviderCredentialValues = Record<string, string>;

/**
 * Which lifecycle slot a field belongs to:
 *
 *   - `credential` (default) — secret material that lands in
 *     ProviderCredential / Vault (access keys, tokens, passwords).
 *   - `config` — non-secret connection or deployment defaults that live on
 *     Provider.config (endpoint URLs, regions, TLS verification flags). The
 *     extension's ProviderFormModal exposes these on its General tab and
 *     passes `excludeScopes={['config']}` so they don't render again on the
 *     Credentials tab. The onboarding wizard auto-creates a provider from
 *     the credentials payload, so it still shows them.
 */
export type ProviderFieldScope = 'credential' | 'config';

export interface ProviderFieldDef {
  /** Snake_case key used in the credentials payload sent to the server. */
  key: string;
  /** Operator-facing label. */
  label: string;
  /** HTML input type — `password` masks values, `textarea` renders a multiline area. */
  type: 'text' | 'password' | 'textarea';
  /** Default value populated when the form first mounts. */
  defaultValue?: string;
  /** Optional placeholder hint (e.g. "AKIA…"). */
  placeholder?: string;
  /** Helper text shown below the field. */
  helper?: string;
  /** When true, the field is required and validated client-side before "Test". */
  required?: boolean;
  /** When true, the value must parse as JSON before "Test" is enabled. */
  jsonValidate?: boolean;
  /** Lifecycle slot — see ProviderFieldScope. Defaults to 'credential'. */
  scope?: ProviderFieldScope;
}

/**
 * Per-category, per-provider field schemas. Keyed first by category so the
 * wizard's category-step picks the right set, then by provider-type slug.
 *
 * Order within each category matters — fields render top-to-bottom in this order.
 */
export const PROVIDER_FIELD_SCHEMAS: Record<ProviderCategory, Record<ProviderTypeSlug, ProviderFieldDef[]>> = {
  ai: {
    anthropic: [
      {
        key: 'api_key',
        label: 'API Key',
        type: 'password',
        placeholder: 'sk-ant-…',
        helper: 'Generated under console.anthropic.com → Settings → API Keys.',
        required: true,
      },
      {
        key: 'default_model',
        label: 'Default Model',
        type: 'text',
        defaultValue: 'claude-sonnet-4-6',
        helper: 'Model id used by the concierge agent for chat.',
        required: false,
      },
    ],
    openai: [
      {
        key: 'api_key',
        label: 'API Key',
        type: 'password',
        placeholder: 'sk-…',
        required: true,
      },
      {
        key: 'organization_id',
        label: 'Organization ID',
        type: 'text',
        placeholder: 'org-… (optional)',
        required: false,
      },
      {
        key: 'default_model',
        label: 'Default Model',
        type: 'text',
        defaultValue: 'gpt-4o',
        required: false,
      },
    ],
    ollama: [
      {
        key: 'base_url',
        label: 'Ollama Base URL',
        type: 'text',
        defaultValue: 'http://localhost:11434',
        helper: 'Self-hosted Ollama instance — no remote credentials needed.',
        required: false,
      },
      {
        key: 'default_model',
        label: 'Default Model',
        type: 'text',
        defaultValue: 'llama3',
        required: false,
      },
    ],
    grok: [
      {
        key: 'api_key',
        label: 'API Key',
        type: 'password',
        placeholder: 'xai-…',
        helper: 'Generated under console.x.ai → API Keys.',
        required: true,
      },
      {
        key: 'default_model',
        label: 'Default Model',
        type: 'text',
        defaultValue: 'grok-3',
        helper: 'e.g. grok-3, grok-3-mini-fast, grok-vision.',
        required: false,
      },
    ],
  },
  cloud: {
    aws: [
      {
        key: 'access_key_id',
        label: 'Access Key ID',
        type: 'text',
        placeholder: 'AKIA…',
        required: true,
      },
      {
        key: 'secret_access_key',
        label: 'Secret Access Key',
        type: 'password',
        required: true,
      },
      {
        key: 'region',
        label: 'Default Region',
        type: 'text',
        defaultValue: 'us-east-1',
        required: true,
        scope: 'config',
      },
    ],
    hetzner: [
      {
        key: 'api_token',
        label: 'API Token',
        type: 'password',
        placeholder: 'Generated under Hetzner Cloud Console → Security',
        required: true,
      },
    ],
    digitalocean: [
      {
        key: 'personal_access_token',
        label: 'Personal Access Token',
        type: 'password',
        placeholder: 'dop_v1_…',
        required: true,
      },
    ],
    vultr: [
      {
        key: 'api_key',
        label: 'API Key',
        type: 'password',
        required: true,
      },
    ],
    gcp: [
      {
        key: 'service_account_json',
        label: 'Service Account JSON',
        type: 'textarea',
        placeholder: '{ "type": "service_account", … }',
        helper: 'Paste the full JSON key downloaded from IAM → Service Accounts.',
        required: true,
        jsonValidate: true,
      },
    ],
    azure: [
      {
        key: 'tenant_id',
        label: 'Tenant ID',
        type: 'text',
        required: true,
      },
      {
        key: 'client_id',
        label: 'Client ID',
        type: 'text',
        required: true,
      },
      {
        key: 'client_secret',
        label: 'Client Secret',
        type: 'password',
        required: true,
      },
      {
        key: 'subscription_id',
        label: 'Subscription ID',
        type: 'text',
        required: true,
        scope: 'config',
      },
    ],
    local_qemu: [
      {
        key: 'libvirt_uri',
        label: 'Libvirt Connection URI',
        type: 'text',
        defaultValue: 'qemu:///system',
        helper: 'Connects to your local KVM/QEMU hypervisor — no remote credentials needed.',
        required: false,
      },
    ],
    proxmox: [
      {
        key: 'endpoint_url',
        label: 'PVE API Endpoint',
        type: 'text',
        placeholder: 'https://pve.example.com:8006',
        helper: 'Base URL of the Proxmox VE REST API. Include scheme and port.',
        required: true,
        scope: 'config',
      },
      {
        key: 'access_key',
        label: 'API Token ID',
        type: 'text',
        placeholder: 'root@pam!powernode',
        helper: 'PVE token identity in the form USER@REALM!TOKENNAME.',
        required: true,
      },
      {
        key: 'secret_key',
        label: 'API Token Secret',
        type: 'password',
        placeholder: '00000000-0000-0000-0000-000000000000',
        helper: 'UUID secret shown once at token creation in the PVE web UI.',
        required: true,
      },
      {
        key: 'verify_ssl',
        label: 'Verify TLS certificate',
        type: 'text',
        defaultValue: 'true',
        helper: 'Set to "false" for PVE installs with a self-signed certificate. Stored as a string in config.',
        required: false,
        scope: 'config',
      },
    ],
  },
  git: {
    github: [
      {
        key: 'personal_access_token',
        label: 'Personal Access Token',
        type: 'password',
        placeholder: 'ghp_…',
        helper: 'Fine-grained PAT with repo + workflow scopes.',
        required: true,
      },
    ],
    gitea: [
      {
        key: 'base_url',
        label: 'Gitea Base URL',
        type: 'text',
        placeholder: 'https://git.example.com',
        required: true,
      },
      {
        key: 'access_token',
        label: 'Access Token',
        type: 'password',
        required: true,
      },
    ],
    gitlab: [
      {
        key: 'base_url',
        label: 'GitLab Base URL',
        type: 'text',
        defaultValue: 'https://gitlab.com',
        required: false,
      },
      {
        key: 'access_token',
        label: 'Personal Access Token',
        type: 'password',
        placeholder: 'glpat-…',
        required: true,
      },
    ],
  },
};

export const PROVIDER_LABELS: Record<ProviderCategory, Record<ProviderTypeSlug, string>> = {
  ai: {
    anthropic: 'Anthropic Claude',
    openai: 'OpenAI',
    ollama: 'Ollama (self-hosted)',
    grok: 'xAI (Grok)',
  },
  cloud: {
    aws: 'Amazon Web Services',
    hetzner: 'Hetzner Cloud',
    digitalocean: 'DigitalOcean',
    vultr: 'Vultr',
    gcp: 'Google Cloud Platform',
    azure: 'Microsoft Azure',
    local_qemu: 'Local KVM/QEMU',
    proxmox: 'Proxmox VE',
  },
  git: {
    github: 'GitHub',
    gitea: 'Gitea',
    gitlab: 'GitLab',
  },
};

export type CredentialTestStatus = 'idle' | 'testing' | 'valid' | 'invalid';

export interface ProviderCredentialFormProps {
  /** Provider category — selects the schema set. */
  category: ProviderCategory;
  /** Provider type slug within the category (e.g. 'aws' under 'cloud'). */
  providerType: ProviderTypeSlug;
  /**
   * Optional provider_id sent in the test/save payload. When the wizard is
   * used in first-run mode no Provider record exists yet, so we fall back
   * to the provider type slug; the cloud surface accepts either form.
   */
  providerId?: string;
  /** Initial credential values (e.g., when editing an existing record). */
  initialValues?: ProviderCredentialValues;
  /** Called whenever any field changes — parent caches values for save. */
  onChange?: (values: ProviderCredentialValues, isValid: boolean) => void;
  /** Notified when the credential test transitions; useful for save-button gating. */
  onTestStatusChange?: (status: CredentialTestStatus) => void;
  /**
   * Optional override for the "Test credentials" endpoint. Defaults to the
   * cloud-provider test endpoint; AI and Git categories don't currently
   * expose a parallel test surface, so the wizard hides the button there.
   */
  testEndpoint?: string;
  /** Compact form variant suppresses the description block. */
  compact?: boolean;
  /** Hide the "Test credentials" CTA — useful when the parent renders its own. */
  hideTestButton?: boolean;
  /**
   * Hide fields whose `scope` matches any value in this array. Default behavior
   * (omitted) renders every field in the schema. The system extension's
   * ProviderFormModal passes `['config']` here so connection/region defaults
   * already collected on its General tab don't appear again on the Credentials
   * tab. The onboarding wizard omits this prop because it auto-creates a
   * provider from the credentials payload and needs every field.
   */
  excludeScopes?: ProviderFieldScope[];
  className?: string;
}

const isJsonParsable = (value: string): boolean => {
  try {
    JSON.parse(value);
    return true;
  } catch {
    return false;
  }
};

const computeValidity = (
  fields: ProviderFieldDef[],
  values: ProviderCredentialValues
): { isValid: boolean; errors: Record<string, string> } => {
  const errors: Record<string, string> = {};
  fields.forEach((field) => {
    const raw = (values[field.key] ?? '').trim();
    if (field.required && raw.length === 0) {
      errors[field.key] = `${field.label} is required.`;
      return;
    }
    if (raw.length > 0 && field.jsonValidate && !isJsonParsable(raw)) {
      errors[field.key] = 'Value must be valid JSON.';
    }
  });
  return { isValid: Object.keys(errors).length === 0, errors };
};

const buildInitialValues = (
  fields: ProviderFieldDef[],
  initial: ProviderCredentialValues | undefined
): ProviderCredentialValues => {
  const seed: ProviderCredentialValues = {};
  fields.forEach((field) => {
    seed[field.key] = initial?.[field.key] ?? field.defaultValue ?? '';
  });
  return seed;
};

/**
 * ProviderCredentialForm — dynamic per-(category, provider) credential entry.
 *
 * Renders a field schema selected by `(category, providerType)`, validates
 * required fields client-side, and wires a "Test credentials" CTA that calls
 * the cloud-category test endpoint when applicable.
 *
 * The component is controlled by the parent via `onChange` so the
 * FirstRunWizard can persist values between steps. The internal `testStatus`
 * is also lifted via `onTestStatusChange` so the wizard can require a green
 * check before "Save" for categories that support testing.
 */
export const ProviderCredentialForm: React.FC<ProviderCredentialFormProps> = ({
  category,
  providerType,
  providerId,
  initialValues,
  onChange,
  onTestStatusChange,
  testEndpoint = '/system/provider_credentials/test',
  compact = false,
  hideTestButton = false,
  excludeScopes,
  className = '',
}) => {
  // Memoize against a string key so callers can pass a fresh array literal
  // (e.g. `excludeScopes={['config']}`) on every render without invalidating
  // the dep arrays of downstream useMemo/useEffect blocks.
  const excludeKey = (excludeScopes ?? []).join(',');
  const fields = useMemo(() => {
    const raw = PROVIDER_FIELD_SCHEMAS[category]?.[providerType] ?? [];
    if (excludeKey.length === 0) return raw;
    const excluded = new Set(excludeKey.split(',') as ProviderFieldScope[]);
    // Fields without an explicit `scope` default to 'credential' — non-secret
    // config fields opt out by tagging themselves `scope: 'config'`. Exclude-list
    // semantics (not include-list) so existing schemas keep working without
    // retagging every single field.
    return raw.filter((field) => !excluded.has(field.scope ?? 'credential'));
  }, [category, providerType, excludeKey]);
  const providerLabel = PROVIDER_LABELS[category]?.[providerType] ?? providerType;

  const [values, setValues] = useState<ProviderCredentialValues>(() =>
    buildInitialValues(fields, initialValues)
  );
  const [touched, setTouched] = useState<Record<string, boolean>>({});
  const [testStatus, setTestStatus] = useState<CredentialTestStatus>('idle');
  const [testMessage, setTestMessage] = useState<string | null>(null);

  // Reset values + status whenever the schema (category/provider) changes — guards
  // against stale credentials from a previously-selected provider polluting the
  // new payload.
  useEffect(() => {
    setValues(buildInitialValues(fields, initialValues));
    setTouched({});
    setTestStatus('idle');
    setTestMessage(null);
  }, [category, providerType]);

  const { isValid, errors } = useMemo(() => computeValidity(fields, values), [fields, values]);

  // Bubble up validity + values whenever they change.
  useEffect(() => {
    onChange?.(values, isValid);
  }, [values, isValid, onChange]);

  useEffect(() => {
    onTestStatusChange?.(testStatus);
  }, [testStatus, onTestStatusChange]);

  const handleChange = (key: string, next: string) => {
    setValues((prev) => ({ ...prev, [key]: next }));
    if (testStatus !== 'idle') {
      setTestStatus('idle');
      setTestMessage(null);
    }
  };

  const handleBlur = (key: string) => {
    setTouched((prev) => ({ ...prev, [key]: true }));
  };

  const handleTest = async () => {
    if (!isValid) {
      const allTouched: Record<string, boolean> = {};
      fields.forEach((f) => {
        allTouched[f.key] = true;
      });
      setTouched(allTouched);
      return;
    }
    setTestStatus('testing');
    setTestMessage(null);
    try {
      const inner = await onboardingApi.testCredentials({
        endpoint: testEndpoint,
        providerId: providerId ?? providerType,
        providerType,
        category,
        credentials: values,
      });
      if (inner.valid) {
        setTestStatus('valid');
        setTestMessage(null);
      } else {
        setTestStatus('invalid');
        setTestMessage(inner.error ?? 'Credentials were rejected by the provider.');
      }
    } catch (err) {
      logger.error('ProviderCredentialForm: credential test failed', err, {
        category,
        providerType,
      });
      setTestStatus('invalid');
      setTestMessage(
        err instanceof Error ? err.message : 'Failed to reach the credential test endpoint.'
      );
    }
  };

  const renderField = (field: ProviderFieldDef): React.ReactElement => {
    const fieldId = `provider-cred-${category}-${providerType}-${field.key}`;
    const errorMsg = touched[field.key] ? errors[field.key] : undefined;
    const commonProps = {
      id: fieldId,
      name: field.key,
      value: values[field.key] ?? '',
      onBlur: () => handleBlur(field.key),
      'data-testid': `provider-cred-field-${field.key}`,
      placeholder: field.placeholder,
      'aria-invalid': errorMsg ? true : undefined,
      'aria-describedby': field.helper ? `${fieldId}-helper` : undefined,
    } as const;
    const baseClass = `input-theme w-full ${errorMsg ? 'error' : ''}`.trim();

    return (
      <div key={field.key} className="space-y-1">
        <label
          htmlFor={fieldId}
          className="block text-sm font-medium text-theme-primary"
        >
          {field.label}
          {field.required && <span className="ml-1 text-theme-danger-fg">*</span>}
        </label>

        {field.type === 'textarea' ? (
          <textarea
            {...commonProps}
            rows={6}
            onChange={(e) => handleChange(field.key, e.target.value)}
            className={`${baseClass} font-mono text-xs`}
          />
        ) : (
          <input
            {...commonProps}
            type={field.type}
            autoComplete={field.type === 'password' ? 'new-password' : 'off'}
            onChange={(e) => handleChange(field.key, e.target.value)}
            className={baseClass}
          />
        )}

        {field.helper && (
          <p
            id={`${fieldId}-helper`}
            className="text-xs text-theme-tertiary"
          >
            {field.helper}
          </p>
        )}

        {errorMsg && (
          <p
            className="flex items-center gap-1 text-xs text-theme-danger-fg"
            data-testid={`provider-cred-error-${field.key}`}
          >
            <AlertCircle className="h-3 w-3" />
            {errorMsg}
          </p>
        )}
      </div>
    );
  };

  return (
    <form
      className={`space-y-4 ${className}`.trim()}
      data-testid={`provider-credential-form-${category}-${providerType}`}
      onSubmit={(event) => event.preventDefault()}
      autoComplete="off"
    >
      {!compact && (
        <div className="flex items-start gap-2 rounded-lg border border-theme bg-theme-info-fg/10 px-3 py-2 text-xs text-theme-secondary">
          <ShieldCheck className="mt-0.5 h-4 w-4 flex-shrink-0 text-theme-info-fg" />
          <span>
            Credentials are stored encrypted at rest using Rails attribute encryption and
            never leave your account. Use a least-privilege key whenever possible.
          </span>
        </div>
      )}

      <div className="space-y-3">{fields.map(renderField)}</div>

      {!hideTestButton && (
        <div className="flex flex-wrap items-center gap-3">
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={handleTest}
            disabled={!isValid || testStatus === 'testing'}
            data-testid="provider-cred-test-btn"
          >
            {testStatus === 'testing' ? (
              <>
                <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />
                Testing…
              </>
            ) : (
              'Test credentials'
            )}
          </Button>

          {testStatus === 'valid' && (
            <span
              className="flex items-center gap-1 text-xs text-theme-success-fg"
              data-testid="provider-cred-test-success"
            >
              <CheckCircle2 className="h-4 w-4" />
              Credentials accepted by {providerLabel}.
            </span>
          )}

          {testStatus === 'invalid' && (
            <span
              className="flex items-center gap-1 text-xs text-theme-danger-fg"
              data-testid="provider-cred-test-error"
            >
              <XCircle className="h-4 w-4" />
              {testMessage ?? 'Credential test failed.'}
            </span>
          )}
        </div>
      )}
    </form>
  );
};

export default ProviderCredentialForm;
