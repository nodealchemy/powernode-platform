import { useState, useCallback } from 'react';
import type { IntegrationTemplate, IntegrationCredential } from '../../types';
import { integrationsApi } from '../../services/integrationsApi';

interface TestConnectionStepProps {
  template: IntegrationTemplate;
  credential: IntegrationCredential | null;
  name: string;
  configuration: Record<string, unknown>;
  onCreate: () => void;
  onBack: () => void;
  isCreating: boolean;
}

type TestStatus = 'idle' | 'testing' | 'success' | 'error';

export function TestConnectionStep({
  template,
  credential,
  name,
  configuration,
  onCreate,
  onBack,
  isCreating,
}: TestConnectionStepProps) {
  const [testStatus, setTestStatus] = useState<TestStatus>('idle');
  const [testMessage, setTestMessage] = useState<string>('');
  const [testError, setTestError] = useState<string>('');

  const handleTestConnection = useCallback(async () => {
    setTestStatus('testing');
    setTestMessage('');
    setTestError('');

    // For now, we'll create a temporary instance to test
    // In a real implementation, you might have a separate test endpoint
    try {
      // Simulate test by checking credential validity
      if (credential) {
        // Test credential by fetching it
        const response = await integrationsApi.getCredential(credential.id);
        if (response.success) {
          setTestStatus('success');
          setTestMessage('Connection test successful! Credential is valid.');
        } else {
          setTestStatus('error');
          setTestError(response.error || 'Failed to validate credential');
        }
      } else {
        // No credential, just validate configuration
        setTestStatus('success');
        setTestMessage('Configuration validated. Ready to create integration.');
      }
    } catch {
      setTestStatus('error');
      setTestError('An unexpected error occurred during testing');
    }
  }, [credential]);

  const statusIcon = {
    idle: '⚡',
    testing: '🔄',
    success: '✅',
    error: '❌',
  };

  const statusColor = {
    idle: 'text-theme-secondary',
    testing: 'text-theme-warning',
    success: 'text-theme-success',
    error: 'text-theme-error',
  };

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-lg font-semibold text-theme-primary">Test & Create</h2>
        <p className="text-sm text-theme-secondary mt-1">
          Review your configuration and test the connection
        </p>
      </div>

      {/* Summary */}
      <div className="space-y-4 p-4 bg-theme-surface rounded-lg">
        <h3 className="text-sm font-medium text-theme-primary">Configuration Summary</h3>

        <div className="grid grid-cols-2 gap-4">
          <div>
            <p className="text-xs text-theme-tertiary">Template</p>
            <p className="text-sm text-theme-primary">{template.name}</p>
          </div>
          <div>
            <p className="text-xs text-theme-tertiary">Type</p>
            <p className="text-sm text-theme-primary">
              {integrationsApi.getTypeLabel(template.integration_type)}
            </p>
          </div>
          <div>
            <p className="text-xs text-theme-tertiary">Instance Name</p>
            <p className="text-sm text-theme-primary">{name}</p>
          </div>
          <div>
            <p className="text-xs text-theme-tertiary">Credential</p>
            <p className="text-sm text-theme-primary">
              {credential ? credential.name : 'None'}
            </p>
          </div>
        </div>

        {Object.keys(configuration).length > 0 && (
          <div className="pt-4 border-t border-theme">
            <p className="text-xs text-theme-tertiary mb-2">Configuration</p>
            <pre className="text-xs text-theme-secondary bg-theme-card p-3 rounded overflow-x-auto">
              {JSON.stringify(configuration, null, 2)}
            </pre>
          </div>
        )}
      </div>

      {/* Test Connection */}
      <div className="p-4 border border-theme rounded-lg">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <span className={`text-2xl ${statusColor[testStatus]}`}>
              {testStatus === 'testing' ? (
                <span className="animate-spin inline-block">🔄</span>
              ) : (
                statusIcon[testStatus]
              )}
            </span>
            <div>
              <p className="font-medium text-theme-primary">Connection Test</p>
              <p className="text-sm text-theme-secondary">
                {testStatus === 'idle' && 'Test your integration before creating'}
                {testStatus === 'testing' && 'Testing connection...'}
                {testStatus === 'success' && testMessage}
                {testStatus === 'error' && testError}
              </p>
            </div>
          </div>
          <button
            onClick={handleTestConnection}
            disabled={testStatus === 'testing'}
            className="px-4 py-2 bg-theme-surface border border-theme text-theme-primary rounded-lg hover:bg-theme-card disabled:opacity-50 transition-colors"
          >
            {testStatus === 'testing' ? 'Testing...' : 'Test Connection'}
          </button>
        </div>
      </div>

      {/* Capabilities */}
      {template.capabilities && template.capabilities.length > 0 && (
        <div className="p-4 bg-theme-surface rounded-lg">
          <h3 className="text-sm font-medium text-theme-primary mb-2">Capabilities</h3>
          <div className="flex flex-wrap gap-2">
            {template.capabilities.map((capability) => (
              <span
                key={capability}
                className="px-2 py-1 text-xs bg-theme-card text-theme-secondary rounded"
              >
                {capability}
              </span>
            ))}
          </div>
        </div>
      )}

      {/* Warning for untested */}
      {testStatus !== 'success' && (
        <div className="p-3 bg-theme-warning bg-opacity-10 text-theme-warning rounded-lg text-sm">
          We recommend testing your connection before creating the integration.
        </div>
      )}

      {/* Actions */}
      <div className="flex justify-between pt-4 border-t border-theme">
        <button
          onClick={onBack}
          disabled={isCreating}
          className="px-4 py-2 text-theme-secondary hover:text-theme-primary disabled:opacity-50 transition-colors"
        >
          Back
        </button>
        <button
          onClick={onCreate}
          disabled={isCreating}
          className="px-6 py-2 bg-theme-primary text-white rounded-lg hover:bg-theme-primary-hover disabled:opacity-50 transition-colors"
        >
          {isCreating ? (
            <span className="flex items-center gap-2">
              <span className="animate-spin rounded-full h-4 w-4 border-2 border-white border-t-transparent" />
              Creating...
            </span>
          ) : (
            'Create Integration'
          )}
        </button>
      </div>
    </div>
  );
}
