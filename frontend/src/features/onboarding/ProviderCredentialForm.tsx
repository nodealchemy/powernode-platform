import React, { useEffect, useMemo, useState } from 'react';
import { AlertCircle, CheckCircle2, Loader2, ShieldCheck, XCircle } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { logger } from '@/shared/utils/logger';
import apiClient from '@/shared/services/apiClient';

/**
 * Provider type slugs supported by M2 BYOC.
 *
 * Slice C / the Rails `ProviderCredentialsController#test` endpoint accepts
 * either a Provider record UUID or — during first-run onboarding when no
 * Provider exists yet — the slug surfaced here.
 */
export type OnboardingProviderType =
  | 'aws'
  | 'hetzner'
  | 'digitalocean'
  | 'vultr'
  | 'gcp'
  | 'azure'
  | 'localqemu';

export type ProviderCredentialValues = Record<string, string>;

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
}

/**
 * Per-provider credential field schemas. Mirrors the BYOC contract documented in
 * `docs/m1_selfserve_acceptance.md` and the Slice C `CredentialValidationService`.
 *
 * Order matters — fields render top-to-bottom in this order.
 */
export const PROVIDER_FIELD_SCHEMAS: Record<OnboardingProviderType, ProviderFieldDef[]> = {
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
    },
  ],
  localqemu: [
    {
      key: 'libvirt_uri',
      label: 'Libvirt Connection URI',
      type: 'text',
      defaultValue: 'qemu:///system',
      helper: 'Local QEMU/KVM is the default smoke-test provider — no remote credentials needed.',
      required: false,
    },
  ],
};

export const PROVIDER_LABELS: Record<OnboardingProviderType, string> = {
  aws: 'Amazon Web Services',
  hetzner: 'Hetzner Cloud',
  digitalocean: 'DigitalOcean',
  vultr: 'Vultr',
  gcp: 'Google Cloud Platform',
  azure: 'Microsoft Azure',
  localqemu: 'LocalQemu (smoke test)',
};

interface TestResponseEnvelope {
  data?: { valid?: boolean; error?: string };
  valid?: boolean;
  error?: string;
}

export type CredentialTestStatus = 'idle' | 'testing' | 'valid' | 'invalid';

export interface ProviderCredentialFormProps {
  /** Provider type slug — selects the field schema. */
  providerType: OnboardingProviderType;
  /**
   * Optional provider_id sent in the test/save payload. When the wizard is used
   * in first-run mode no Provider record exists yet, so we fall back to the
   * provider type slug; Slice C accepts either form.
   */
  providerId?: string;
  /** Initial credential values (e.g., when editing an existing record). */
  initialValues?: ProviderCredentialValues;
  /** Called whenever any field changes — parent caches values for save. */
  onChange?: (values: ProviderCredentialValues, isValid: boolean) => void;
  /** Notified when the credential test transitions; useful for save-button gating. */
  onTestStatusChange?: (status: CredentialTestStatus) => void;
  /** Optional override for the "Test credentials" endpoint (defaults to BYOC contract). */
  testEndpoint?: string;
  /** Compact form variant suppresses the description block. */
  compact?: boolean;
  /** Hide the "Test credentials" CTA — useful when the parent renders its own. */
  hideTestButton?: boolean;
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
 * ProviderCredentialForm — dynamic per-provider credential entry component.
 *
 * Renders a field schema selected by `providerType`, validates required fields
 * client-side, and wires a "Test credentials" CTA that calls the BYOC
 * `POST /api/v1/system/provider_credentials/test` endpoint owned by Slice C.
 *
 * The component is controlled by the parent via `onChange` so the FirstRunWizard
 * can persist values between steps. The internal `testStatus` is also lifted via
 * `onTestStatusChange` so the wizard can require a green check before "Save".
 */
export const ProviderCredentialForm: React.FC<ProviderCredentialFormProps> = ({
  providerType,
  providerId,
  initialValues,
  onChange,
  onTestStatusChange,
  testEndpoint = '/system/provider_credentials/test',
  compact = false,
  hideTestButton = false,
  className = '',
}) => {
  const fields = PROVIDER_FIELD_SCHEMAS[providerType];

  const [values, setValues] = useState<ProviderCredentialValues>(() =>
    buildInitialValues(fields, initialValues)
  );
  const [touched, setTouched] = useState<Record<string, boolean>>({});
  const [testStatus, setTestStatus] = useState<CredentialTestStatus>('idle');
  const [testMessage, setTestMessage] = useState<string | null>(null);

  // Reset values + status whenever the schema (provider) changes — guards against
  // stale credentials from a previously-selected provider polluting the new payload.
  useEffect(() => {
    setValues(buildInitialValues(fields, initialValues));
    setTouched({});
    setTestStatus('idle');
    setTestMessage(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [providerType]);

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
    // Any edit invalidates a previous green check — operator must re-test.
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
      // Mark every field as touched so the inline errors render.
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
      const response = await apiClient.post<TestResponseEnvelope>(testEndpoint, {
        provider_id: providerId ?? providerType,
        provider_type: providerType,
        credentials: values,
      });
      const envelope = response.data ?? {};
      const inner = envelope.data ?? envelope;
      if (inner.valid) {
        setTestStatus('valid');
        setTestMessage(null);
      } else {
        setTestStatus('invalid');
        setTestMessage(inner.error ?? 'Credentials were rejected by the provider.');
      }
    } catch (err) {
      logger.error('ProviderCredentialForm: credential test failed', err, {
        providerType,
      });
      setTestStatus('invalid');
      setTestMessage(
        err instanceof Error ? err.message : 'Failed to reach the credential test endpoint.'
      );
    }
  };

  const renderField = (field: ProviderFieldDef): React.ReactElement => {
    const fieldId = `provider-cred-${providerType}-${field.key}`;
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
          {field.required && <span className="ml-1 text-theme-danger">*</span>}
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
            className="flex items-center gap-1 text-xs text-theme-danger"
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
    <div
      className={`space-y-4 ${className}`.trim()}
      data-testid={`provider-credential-form-${providerType}`}
    >
      {!compact && (
        <div className="flex items-start gap-2 rounded-lg border border-theme bg-theme-info/10 px-3 py-2 text-xs text-theme-secondary">
          <ShieldCheck className="mt-0.5 h-4 w-4 flex-shrink-0 text-theme-info" />
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
              className="flex items-center gap-1 text-xs text-theme-success"
              data-testid="provider-cred-test-success"
            >
              <CheckCircle2 className="h-4 w-4" />
              Credentials accepted by {PROVIDER_LABELS[providerType]}.
            </span>
          )}

          {testStatus === 'invalid' && (
            <span
              className="flex items-center gap-1 text-xs text-theme-danger"
              data-testid="provider-cred-test-error"
            >
              <XCircle className="h-4 w-4" />
              {testMessage ?? 'Credential test failed.'}
            </span>
          )}
        </div>
      )}
    </div>
  );
};

export default ProviderCredentialForm;
