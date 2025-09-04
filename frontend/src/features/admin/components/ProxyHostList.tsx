import React, { useState } from 'react';
import { useNotification } from '@/shared/hooks/useNotification';
import proxySettingsApi from '@/shared/services/proxySettingsApi';

interface ProxyHostListProps {
  trustedHosts: string[];
  onHostsChange: (hosts: string[]) => void;
}

const ProxyHostList: React.FC<ProxyHostListProps> = ({ trustedHosts, onHostsChange }) => {
  const { showNotification } = useNotification();
  const showSuccess = (msg: string) => showNotification(msg, 'success');
  const showError = (msg: string) => showNotification(msg, 'error');
  const [newHost, setNewHost] = useState('');
  const [validating, setValidating] = useState(false);
  const [validationResult, setValidationResult] = useState<any>(null);

  const handleAddHost = async () => {
    if (!newHost.trim()) return;

    setValidating(true);
    try {
      // Validate host first
      const result = await proxySettingsApi.validateHost(newHost);
      setValidationResult(result);

      if (result.validation.valid || newHost.includes('*')) {
        // Add to list
        const updatedHosts = [...trustedHosts, newHost];
        onHostsChange(updatedHosts);
        setNewHost('');
        showSuccess(`Added trusted host: ${newHost}`);
      } else {
        showError(`Invalid host: ${result.validation.errors.join(', ')}`);
      }
    } catch (error) {
      showError('Failed to validate host');
    } finally {
      setValidating(false);
    }
  };

  const handleRemoveHost = (host: string) => {
    const updatedHosts = trustedHosts.filter(h => h !== host);
    onHostsChange(updatedHosts);
    showSuccess(`Removed trusted host: ${host}`);
  };

  const getHostBadge = (host: string) => {
    if (host.includes('*')) {
      return (
        <span className="ml-2 px-2 py-1 text-xs bg-theme-info/20 text-theme-info rounded">
          Wildcard
        </span>
      );
    }
    if (host.match(/^\d+\.\d+\.\d+\.\d+$/)) {
      return (
        <span className="ml-2 px-2 py-1 text-xs bg-theme-muted/50 text-theme-secondary rounded">
          IP
        </span>
      );
    }
    if (host === 'localhost' || host === '127.0.0.1') {
      return (
        <span className="ml-2 px-2 py-1 text-xs bg-theme-success/20 text-theme-success rounded">
          Local
        </span>
      );
    }
    return null;
  };

  return (
    <div className="bg-theme-surface rounded-lg p-6">
      <h3 className="text-lg font-medium text-theme-primary mb-4">
        Trusted Host Patterns
      </h3>
      
      {/* Add new host */}
      <div className="flex space-x-2 mb-4">
        <input
          type="text"
          value={newHost}
          onChange={(e) => setNewHost(e.target.value)}
          onKeyPress={(e) => e.key === 'Enter' && handleAddHost()}
          placeholder="example.com or *.example.com"
          className="flex-1 px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-primary focus:border-theme-primary"
        />
        <button
          onClick={handleAddHost}
          disabled={validating || !newHost.trim()}
          className="btn-theme btn-theme-primary"
        >
          {validating ? 'Validating...' : 'Add Host'}
        </button>
      </div>

      {/* Validation result */}
      {validationResult && !validationResult.validation.valid && (
        <div className="mb-4 p-3 bg-theme-error/10 border border-theme-error rounded-md">
          <p className="text-sm text-theme-error">
            Validation failed: {validationResult.validation.errors.join(', ')}
          </p>
        </div>
      )}

      {/* Host list */}
      <div className="space-y-2">
        {trustedHosts.length === 0 ? (
          <p className="text-theme-secondary text-sm">No trusted hosts configured</p>
        ) : (
          trustedHosts.map((host, index) => (
            <div
              key={`${host}-${index}`}
              className="flex items-center justify-between p-3 bg-theme-background rounded-md border border-theme"
            >
              <div className="flex items-center">
                <span className="text-theme-primary font-mono text-sm">{host}</span>
                {getHostBadge(host)}
              </div>
              <button
                onClick={() => handleRemoveHost(host)}
                className="text-theme-error hover:text-theme-error/80 transition-colors"
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
          ))
        )}
      </div>

      {/* Help text */}
      <div className="mt-4 p-3 bg-theme-info/10 border border-theme-info rounded-md">
        <p className="text-sm text-theme-info mb-2">
          <strong>Pattern Examples:</strong>
        </p>
        <ul className="text-sm text-theme-info space-y-1">
          <li>• <code className="font-mono">example.com</code> - Exact domain match</li>
          <li>• <code className="font-mono">*.example.com</code> - Wildcard subdomain (tenant1.example.com)</li>
          <li>• <code className="font-mono">192.168.1.100</code> - IP address</li>
          <li>• <code className="font-mono">localhost</code> - Local development</li>
        </ul>
      </div>
    </div>
  );
};

export default ProxyHostList;