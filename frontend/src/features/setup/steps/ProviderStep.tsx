import React, { useCallback, useRef, useState } from 'react';
import { logger } from '@/shared/utils/logger';
import { onboardingApi } from '@/features/onboarding/services/onboardingApi';
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
import type { SetupStepComponentProps } from './types';

const COMPONENT_TO_CATEGORY: Record<string, ProviderCategory> = {
  'core/ai_provider': 'ai',
  'core/cloud_provider': 'cloud',
  'core/git_provider': 'git',
};

/**
 * Self-contained provider step for the setup wizard (one of ai/cloud/git). Owns
 * its per-category state + persistence (via the shared onboardingApi) and renders
 * the shared ProviderCategoryStep. The wizard footer's "Continue" advances; the
 * step's own backend completion is credential presence (Setup::StepRegistry), so
 * a configured provider is auto-skipped on the next load.
 */
export const ProviderStep: React.FC<SetupStepComponentProps> = ({ step }) => {
  const category: ProviderCategory =
    (step.category as ProviderCategory) ?? COMPONENT_TO_CATEGORY[step.component ?? ''] ?? 'ai';

  const [providerType, setProviderType] = useState<ProviderTypeSlug | null>(null);
  const [credentials, setCredentials] = useState<ProviderCredentialValues>({});
  const [credentialsValid, setCredentialsValid] = useState(false);
  const [testStatus, setTestStatus] = useState<CredentialTestStatus>('idle');
  const [saveStatus, setSaveStatus] = useState<SaveStatus>('idle');
  const [saveError, setSaveError] = useState<string | null>(null);
  const prevTestRef = useRef<CredentialTestStatus>('idle');

  const onSelectProvider = useCallback((next: ProviderTypeSlug) => {
    // Switching providers wipes half-entered creds so we never POST mismatched data.
    setProviderType(next);
    setCredentials({});
    setCredentialsValid(false);
    setTestStatus('idle');
    prevTestRef.current = 'idle';
    setSaveStatus('idle');
    setSaveError(null);
  }, []);

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
      if (category === 'cloud') {
        await onboardingApi.createCloudCredential({ providerType, credentials });
      } else if (category === 'ai') {
        const providerId = await onboardingApi.createAiProvider({
          providerType,
          name: PROVIDER_LABELS.ai[providerType] ?? providerType,
        });
        if (!providerId) throw new Error('AI provider creation did not return an id');
        await onboardingApi.createAiCredential({ providerId, credentials });
      } else if (category === 'git') {
        const providerId = await onboardingApi.createGitProvider({
          providerType,
          name: PROVIDER_LABELS.git[providerType] ?? providerType,
        });
        if (!providerId) throw new Error('Git provider creation did not return an id');
        await onboardingApi.createGitCredential({ providerId, credentials });
      }
      setSaveStatus('saved');
    } catch (err) {
      logger.error('ProviderStep: failed to persist credentials', err, { category });
      setSaveError(err instanceof Error ? err.message : 'Failed to save credentials. Please retry.');
      setSaveStatus('error');
    }
  }, [providerType, category, credentials]);

  const progress: CategoryProgress = {
    providerType,
    credentials,
    credentialsValid,
    testStatus,
    saveStatus,
    saveError,
  };

  return (
    <ProviderCategoryStep
      category={category}
      progress={progress}
      onSelectProvider={onSelectProvider}
      onValuesChange={onValuesChange}
      onTestStatusChange={onTestStatusChange}
      onSave={onSave}
      testIdPrefix="setup"
    />
  );
};

export default ProviderStep;
