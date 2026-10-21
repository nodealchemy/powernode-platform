import React, { useCallback, useEffect, useRef, useState } from 'react';
import { Button } from '@/shared/components/ui/Button';
import { logger } from '@/shared/utils/logger';
import { getErrorMessage, getErrorStatus } from '@/shared/utils/errorHandling';
import { featureRegistry } from '@/shared/services/featureRegistry';
import {
  onboardingApi,
  type AiModelSyncResult,
} from '@/features/onboarding/services/onboardingApi';
import {
  ProviderCategoryStep,
  type CategoryProgress,
  type SaveStatus,
} from '@/features/onboarding/ProviderCategoryStep';
import {
  PROVIDER_LABELS,
  type CredentialTestStatus,
  type ProviderCategory,
  type ProviderCredentialValues,
  type ProviderTypeSlug,
} from '@/features/onboarding/ProviderCredentialForm';
import type { AiProviderCatalogEntry } from '@/shared/types/ai';
import type { SetupStepComponentProps } from './types';
import type { SetupStep } from '../services/setupApi';

const COMPONENT_TO_CATEGORY: Record<string, ProviderCategory> = {
  'core/ai_provider': 'ai',
  'core/cloud_provider': 'cloud',
  'core/git_provider': 'git',
};

// Categories whose credentials core persists itself. Any other category is
// served by the handlers an extension registers for it.
const CORE_SERVED_CATEGORIES: readonly ProviderCategory[] = ['ai', 'git'];

/** A provider the operator has added in this step (persisted when saved). */
interface ProviderEntry {
  key: string;
  providerType: ProviderTypeSlug;
  label: string;
  providerId?: string;
  credentialId?: string | null;
  /** AI only: the server-side model sync run when the credential was saved. */
  modelSync?: AiModelSyncResult | null;
  /** AI only: the account default provider. */
  isDefault?: boolean;
}

const categoryOf = (step: SetupStep): ProviderCategory =>
  (step.category as ProviderCategory) ?? COMPONENT_TO_CATEGORY[step.component ?? ''] ?? 'ai';

/**
 * Whether the setup wizard should show this step. A provider step for a
 * category core does not serve is shown only while an extension has registered
 * handlers for it; without them the category is simply absent.
 */
export const isSetupStepAvailable = (step: SetupStep): boolean => {
  if (step.completion !== 'provider_credentials') return true;
  const category = categoryOf(step);
  return (
    CORE_SERVED_CATEGORIES.includes(category) ||
    featureRegistry.getProviderCategoryHandlers(category) !== undefined
  );
};

/**
 * Self-contained provider step for the setup wizard (one of ai/cloud/git). Owns
 * its per-category state + persistence (via the shared onboardingApi) and renders
 * the shared ProviderCategoryStep. The wizard footer's "Continue" advances; the
 * step's own backend completion is credential presence (Setup::StepRegistry), so
 * a configured provider is auto-skipped on the next load.
 */
export const ProviderStep: React.FC<SetupStepComponentProps> = ({ step }) => {
  const category = categoryOf(step);
  const handlers = CORE_SERVED_CATEGORIES.includes(category)
    ? undefined
    : featureRegistry.getProviderCategoryHandlers(category);

  const [providerType, setProviderType] = useState<ProviderTypeSlug | null>(null);
  const [credentials, setCredentials] = useState<ProviderCredentialValues>({});
  const [credentialsValid, setCredentialsValid] = useState(false);
  const [testStatus, setTestStatus] = useState<CredentialTestStatus>('idle');
  const [saveStatus, setSaveStatus] = useState<SaveStatus>('idle');
  const [saveError, setSaveError] = useState<string | null>(null);
  const prevTestRef = useRef<CredentialTestStatus>('idle');
  const [entries, setEntries] = useState<ProviderEntry[]>([]);
  const [entryError, setEntryError] = useState<string | null>(null);
  const entryCounter = useRef(0);

  // AI provider-type catalog: pre-fills the provider details on type selection.
  const [catalog, setCatalog] = useState<AiProviderCatalogEntry[]>([]);
  const [providerName, setProviderName] = useState('');
  const [apiBaseUrl, setApiBaseUrl] = useState('');

  useEffect(() => {
    if (category !== 'ai') return;
    let cancelled = false;
    onboardingApi
      .getAiProviderCatalog()
      .then((result) => {
        if (!cancelled) setCatalog(result.items);
      })
      .catch(() => {
        // Without the catalog the details stay manual; the server still
        // fills its own defaults for known types.
        if (!cancelled) setCatalog([]);
      });
    return () => {
      cancelled = true;
    };
  }, [category]);

  const onSelectProvider = useCallback(
    (next: ProviderTypeSlug) => {
    // Switching providers wipes half-entered creds so we never POST mismatched data.
    setProviderType(next);
    const entry = category === 'ai' ? catalog.find((c) => c.provider_type === next) : undefined;
    setProviderName(entry?.name ?? '');
    setApiBaseUrl(entry?.api_base_url ?? '');
    // Non-secret credential-form defaults from the catalog. Never a key.
    const seed: ProviderCredentialValues = {};
    if (entry?.default_model) seed.default_model = entry.default_model;
    if (entry && !entry.requires_auth && entry.api_base_url) seed.base_url = entry.api_base_url;
    setCredentials(seed);
    setCredentialsValid(false);
    setTestStatus('idle');
    prevTestRef.current = 'idle';
    setSaveStatus('idle');
    setSaveError(null);
    },
    [category, catalog]
  );

  const onValuesChange = useCallback((values: ProviderCredentialValues, valid: boolean) => {
    setCredentials(values);
    setCredentialsValid(valid);
  }, []);

  const onTestStatusChange = useCallback((status: CredentialTestStatus) => {
    // Editing creds after a test (non-idle → idle/invalid) resets a prior save.
    const wasNonIdle = prevTestRef.current !== 'idle';
    prevTestRef.current = status;
    setTestStatus(status);
    if (wasNonIdle && (status === 'idle' || status === 'invalid')) {
      setSaveStatus('idle');
      setSaveError(null);
    }
  }, []);

  const onSave = useCallback(async () => {
    if (!providerType) return;
    setSaveStatus('saving');
    setSaveError(null);
    try {
      let entry: ProviderEntry = {
        key: `entry-${(entryCounter.current += 1)}`,
        providerType,
        label: providerName.trim() || (PROVIDER_LABELS[category]?.[providerType] ?? providerType),
      };
      if (handlers) {
        const credentialId = await handlers.createCredential({ providerType, credentials });
        entry = { ...entry, credentialId };
      } else if (category === 'ai') {
        const providerId = await onboardingApi.createAiProvider({
          providerType,
          name: providerName.trim() || (PROVIDER_LABELS.ai[providerType] ?? providerType),
          apiBaseUrl: apiBaseUrl.trim() || undefined,
        });
        if (!providerId) throw new Error('AI provider creation did not return an id');
        const created = await onboardingApi.createAiCredential({ providerId, credentials });
        entry = {
          ...entry,
          providerId,
          credentialId: created.id,
          modelSync: created.modelSync,
          isDefault: Boolean(created.modelSync?.default),
        };
      } else if (category === 'git') {
        // base_url configures the Provider record (self-hosted Gitea/GitLab
        // endpoint), not the credential — split it out before sending the rest
        // of the form values as credential material.
        const { base_url, ...gitCredentials } = credentials;
        const providerId = await onboardingApi.createGitProvider({
          providerType,
          name: PROVIDER_LABELS.git[providerType] ?? providerType,
          apiBaseUrl: typeof base_url === 'string' ? base_url : undefined,
        });
        if (!providerId) throw new Error('Git provider creation did not return an id');
        const credentialId = await onboardingApi.createGitCredential({
          providerId,
          credentials: gitCredentials,
        });
        entry = { ...entry, providerId, credentialId };
      }
      setEntries((prev) => {
        // The server re-ranks on a new default: only one entry stays the default.
        const base = entry.isDefault ? prev.map((e) => ({ ...e, isDefault: false })) : prev;
        return [...base, entry];
      });
      setSaveStatus('saved');
    } catch (err) {
      // Never the raw error: an axios error carries the request body, i.e. the
      // plaintext credentials, in config.data.
      logger.error('ProviderStep: failed to persist credentials', undefined, {
        category,
        providerType,
        errorMessage: getErrorMessage(err),
        status: getErrorStatus(err),
      });
      setSaveError(err instanceof Error ? err.message : 'Failed to save credentials. Please retry.');
      setSaveStatus('error');
    }
  }, [providerType, category, credentials, handlers, providerName, apiBaseUrl]);

  const resetForm = useCallback(() => {
    setProviderType(null);
    setCredentials({});
    setCredentialsValid(false);
    setTestStatus('idle');
    prevTestRef.current = 'idle';
    setSaveStatus('idle');
    setSaveError(null);
    setProviderName('');
    setApiBaseUrl('');
  }, []);

  const chooseDefault = useCallback(async (target: ProviderEntry) => {
    if (!target.providerId) return;
    setEntryError(null);
    try {
      await onboardingApi.setAiDefaultProvider(target.providerId);
      setEntries((prev) => prev.map((e) => ({ ...e, isDefault: e.key === target.key })));
    } catch (err) {
      logger.error('ProviderStep: failed to set the default provider', undefined, {
        errorMessage: getErrorMessage(err),
        status: getErrorStatus(err),
      });
      setEntryError('Could not set the default provider. Only a working provider can be the default.');
    }
  }, []);

  const removeEntry = useCallback(
    async (target: ProviderEntry) => {
      setEntryError(null);
      try {
        if (category === 'ai' && target.providerId && target.credentialId) {
          await onboardingApi.deleteAiCredential({
            providerId: target.providerId,
            credentialId: target.credentialId,
          });
        }
        const remaining = entries.filter((e) => e.key !== target.key);
        setEntries(remaining);
        // A removed default hands over to the next working provider.
        const next = remaining.find((e) => e.modelSync?.success);
        if (category === 'ai' && target.isDefault && next) {
          await chooseDefault(next);
        }
      } catch (err) {
        logger.error('ProviderStep: failed to remove a provider entry', undefined, {
          category,
          errorMessage: getErrorMessage(err),
          status: getErrorStatus(err),
        });
        setEntryError('Could not remove that provider. Please retry.');
      }
    },
    [category, entries, chooseDefault]
  );

  // Model choices valid for the selected type, from the catalog.
  const selectedEntry =
    category === 'ai' && providerType ? catalog.find((c) => c.provider_type === providerType) : undefined;
  const fieldOptions = selectedEntry?.models?.length ? { default_model: selectedEntry.models } : undefined;

  const progress: CategoryProgress = {
    providerType,
    credentials,
    credentialsValid,
    testStatus,
    saveStatus,
    saveError,
  };

  return (
    <div className="space-y-4">
      <ProviderCategoryStep
        category={category}
        progress={progress}
        onSelectProvider={onSelectProvider}
        onValuesChange={onValuesChange}
        onTestStatusChange={onTestStatusChange}
        onSave={onSave}
        testIdPrefix="setup"
        testCredentials={handlers?.testCredential}
        fieldOptions={fieldOptions}
        detailsSlot={
          category === 'ai' ? (
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <div className="space-y-1">
                <label htmlFor="setup-provider-name" className="block text-sm font-medium text-theme-primary">
                  Provider name
                </label>
                <input
                  id="setup-provider-name"
                  data-testid="setup-provider-name"
                  className="input-theme w-full"
                  value={providerName}
                  onChange={(e) => setProviderName(e.target.value)}
                />
              </div>
              <div className="space-y-1">
                <label htmlFor="setup-provider-base-url" className="block text-sm font-medium text-theme-primary">
                  API base URL
                </label>
                <input
                  id="setup-provider-base-url"
                  data-testid="setup-provider-base-url"
                  className="input-theme w-full"
                  value={apiBaseUrl}
                  onChange={(e) => setApiBaseUrl(e.target.value)}
                />
              </div>
            </div>
          ) : undefined
        }
      />

      {entries.length > 0 && (
        <section className="space-y-2" data-testid="setup-provider-entries" aria-label="Added providers">
          <h3 className="text-sm font-semibold text-theme-primary">Added providers</h3>
          <ul className="space-y-2">
            {entries.map((entry, index) => {
              const sync = entry.modelSync;
              return (
                <li
                  key={entry.key}
                  className="flex flex-wrap items-center gap-3 rounded-lg border border-theme bg-theme-surface p-3"
                  data-testid={`setup-provider-entry-${index}`}
                >
                  <span className="text-sm font-medium text-theme-primary">{entry.label}</span>
                  {category === 'ai' && sync && (
                    <span
                      className={`text-xs ${sync.success ? 'text-theme-success-fg' : 'text-theme-danger-fg'}`}
                      data-testid={`setup-sync-result-${index}`}
                    >
                      {sync.success
                        ? `${sync.model_count} models synced`
                        : `Model sync failed: ${sync.error ?? 'unknown error'}`}
                    </span>
                  )}
                  {category === 'ai' && sync?.success && (
                    <label className="flex items-center gap-1 text-xs text-theme-secondary">
                      <input
                        type="radio"
                        name="setup-default-provider"
                        checked={Boolean(entry.isDefault)}
                        onChange={() => {
                          void chooseDefault(entry);
                        }}
                        data-testid={`setup-default-${index}`}
                      />
                      Default
                    </label>
                  )}
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    className="ml-auto"
                    onClick={() => {
                      void removeEntry(entry);
                    }}
                    data-testid={`setup-provider-remove-${index}`}
                  >
                    Remove
                  </Button>
                </li>
              );
            })}
          </ul>
          {entryError && (
            <p className="text-xs text-theme-danger-fg" data-testid="setup-entry-error">
              {entryError}
            </p>
          )}
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={resetForm}
            data-testid="setup-add-another"
          >
            Add another provider
          </Button>
        </section>
      )}
    </div>
  );
};

export default ProviderStep;
