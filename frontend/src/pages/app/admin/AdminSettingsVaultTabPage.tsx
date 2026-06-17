import React, { useState, useEffect, useCallback } from 'react';
import { adminSettingsApi } from '@/features/admin/services/adminSettingsApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { SettingsCard } from '@/features/admin/components/settings/SettingsComponents';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { KeyRound, Shield, Activity, Eye, EyeOff, RefreshCw, CheckCircle, XCircle, AlertTriangle } from 'lucide-react';

interface VaultStatus {
  connected: boolean;
  sealed: boolean | null;
  initialized: boolean | null;
  version: string | null;
  cluster_name: string | null;
}

interface VaultConfig {
  vault_addr: string;
  vault_role_id: string;
  vault_secret_id: string;
  configured: boolean;
}

interface KeyOperation {
  action: string;
  wallet_type: string | null;
  chain: string | null;
  created_at: string;
}

interface VaultData {
  status: VaultStatus;
  config: VaultConfig;
  keys: {
    secured_count: number;
    recent_operations: KeyOperation[];
  };
}

export const AdminSettingsVaultTabPage: React.FC = () => {
  const { showNotification } = useNotifications();
  const [data, setData] = useState<VaultData | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [testing, setTesting] = useState(false);
  const [showSecretId, setShowSecretId] = useState(false);
  const [testResult, setTestResult] = useState<{ connected: boolean; latency_ms?: number; error?: string } | null>(null);

  const [vaultAddr, setVaultAddr] = useState('');
  const [roleId, setRoleId] = useState('');
  const [secretId, setSecretId] = useState('');

  const loadConfig = useCallback(async () => {
    setLoading(true);
    try {
      const result = await adminSettingsApi.getVaultConfig();
      if (result.success && result.data) {
        const vaultData = result.data as VaultData;
        setData(vaultData);
        setVaultAddr(vaultData.config?.vault_addr || '');
        setRoleId(vaultData.config?.vault_role_id || '');
        setSecretId(vaultData.config?.vault_secret_id || '');
      }
    } catch {
      showNotification('Failed to load Vault configuration', 'error');
    } finally {
      setLoading(false);
    }
  }, [showNotification]);

  useEffect(() => { loadConfig(); }, [loadConfig]);

  const handleSave = async () => {
    setSaving(true);
    try {
      const result = await adminSettingsApi.updateVaultConfig({
        vault_addr: vaultAddr,
        vault_role_id: roleId,
        vault_secret_id: secretId,
      });
      if (result.success) {
        showNotification('Vault configuration saved. Restart backend to apply.', 'success');
        await loadConfig();
      } else {
        showNotification(result.error || 'Failed to save', 'error');
      }
    } catch {
      showNotification('Failed to save Vault configuration', 'error');
    } finally {
      setSaving(false);
    }
  };

  const handleTest = async () => {
    setTesting(true);
    setTestResult(null);
    try {
      const result = await adminSettingsApi.testVaultConnection();
      if (result.success && result.data) {
        setTestResult(result.data as { connected: boolean; latency_ms?: number; error?: string });
      } else {
        setTestResult({ connected: false, error: result.error || 'Test failed' });
      }
    } catch {
      setTestResult({ connected: false, error: 'Connection test failed' });
    } finally {
      setTesting(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <LoadingSpinner size="md" />
      </div>
    );
  }

  const status = data?.status;
  const keys = data?.keys;
  const isConnected = status?.connected === true;

  return (
    <div className="space-y-6">
      {/* Connection Status */}
      <SettingsCard title="Vault Status" description="HashiCorp Vault connection health and version information">
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className={`w-3 h-3 rounded-full ${isConnected ? 'bg-theme-success' : status?.sealed ? 'bg-theme-warning' : 'bg-theme-danger'}`} />
              <span className="text-sm font-medium text-theme-primary">
                {isConnected ? 'Connected' : status?.sealed ? 'Sealed' : 'Disconnected'}
              </span>
              {status?.version && (
                <span className="text-xs text-theme-secondary bg-theme-surface px-2 py-0.5 rounded">v{status.version}</span>
              )}
            </div>
            <button
              onClick={handleTest}
              disabled={testing}
              className="flex items-center gap-1.5 px-3 py-1.5 text-xs rounded border border-theme bg-theme-surface text-theme-secondary hover:text-theme-primary"
            >
              {testing ? <RefreshCw className="w-3 h-3 animate-spin" /> : <Activity className="w-3 h-3" />}
              Test Connection
            </button>
          </div>

          {testResult && (
            <div className={`flex items-center gap-2 px-3 py-2 rounded text-xs ${
              testResult.connected ? 'bg-theme-success/10 text-theme-success' : 'bg-theme-danger/10 text-theme-danger'
            }`}>
              {testResult.connected ? <CheckCircle className="w-3.5 h-3.5" /> : <XCircle className="w-3.5 h-3.5" />}
              {testResult.connected
                ? `Connected in ${testResult.latency_ms}ms`
                : `Connection failed: ${testResult.error}`
              }
            </div>
          )}

          {status?.cluster_name && (
            <div className="text-xs text-theme-secondary">Cluster: {status.cluster_name}</div>
          )}

          {!data?.config?.configured && (
            <div className="flex items-center gap-2 px-3 py-2 bg-theme-warning/10 text-theme-warning rounded text-xs">
              <AlertTriangle className="w-3.5 h-3.5 flex-shrink-0" />
              Vault is not configured. Set VAULT_ADDR, VAULT_ROLE_ID, and VAULT_SECRET_ID below or in environment variables.
            </div>
          )}
        </div>
      </SettingsCard>

      {/* Connection Settings */}
      <SettingsCard title="Connection Settings" description="Configure the Vault server address and AppRole credentials">
        <form onSubmit={(e) => { e.preventDefault(); handleSave(); }} className="space-y-4">
          <div>
            <label className="block text-xs font-medium text-theme-secondary mb-1">Vault Address</label>
            <input
              type="url"
              value={vaultAddr}
              onChange={(e) => setVaultAddr(e.target.value)}
              placeholder="http://localhost:8200"
              autoComplete="off"
              className="w-full px-3 py-2 text-sm border border-theme rounded bg-theme-surface text-theme-primary"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-theme-secondary mb-1">AppRole Role ID</label>
            <input
              type="text"
              value={roleId}
              onChange={(e) => setRoleId(e.target.value)}
              placeholder="Role ID from vault read auth/approle/role/powernode-app/role-id"
              autoComplete="off"
              className="w-full px-3 py-2 text-sm border border-theme rounded bg-theme-surface text-theme-primary"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-theme-secondary mb-1">AppRole Secret ID</label>
            <div className="relative">
              <input
                type={showSecretId ? 'text' : 'password'}
                value={secretId}
                onChange={(e) => setSecretId(e.target.value)}
                placeholder="Secret ID"
                autoComplete="new-password"
                className="w-full px-3 py-2 pr-10 text-sm border border-theme rounded bg-theme-surface text-theme-primary"
              />
              <button
                type="button"
                onClick={() => setShowSecretId(!showSecretId)}
                className="absolute right-2 top-1/2 -translate-y-1/2 text-theme-secondary hover:text-theme-primary"
              >
                {showSecretId ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
              </button>
            </div>
          </div>
          <button
            type="submit"
            disabled={saving}
            className="flex items-center gap-1.5 px-4 py-2 text-sm rounded bg-theme-interactive-primary text-theme-on-primary"
          >
            {saving ? <RefreshCw className="w-3.5 h-3.5 animate-spin" /> : <Shield className="w-3.5 h-3.5" />}
            {saving ? 'Saving...' : 'Save Configuration'}
          </button>
        </form>
      </SettingsCard>

      {/* Key Management */}
      <SettingsCard title="Key Management" description="Wallet keys stored in Vault and recent key operations">
        <div className="space-y-4">
          <div className="flex items-center gap-3">
            <KeyRound className="w-4 h-4 text-theme-secondary" />
            <span className="text-sm text-theme-primary font-medium">{keys?.secured_count || 0} keys secured</span>
          </div>

          {keys?.recent_operations && keys.recent_operations.length > 0 ? (
            <div className="border border-theme rounded overflow-hidden">
              <table className="w-full text-xs">
                <thead>
                  <tr className="bg-theme-surface-secondary">
                    <th className="text-left px-3 py-2 text-theme-secondary font-medium">Action</th>
                    <th className="text-left px-3 py-2 text-theme-secondary font-medium">Wallet Type</th>
                    <th className="text-left px-3 py-2 text-theme-secondary font-medium">Chain</th>
                    <th className="text-left px-3 py-2 text-theme-secondary font-medium">Time</th>
                  </tr>
                </thead>
                <tbody>
                  {keys.recent_operations.map((op, i) => (
                    <tr key={i} className="border-t border-theme">
                      <td className="px-3 py-2 text-theme-primary">{op.action.replace(/_/g, ' ')}</td>
                      <td className="px-3 py-2 text-theme-secondary">{op.wallet_type || '-'}</td>
                      <td className="px-3 py-2 text-theme-secondary">{op.chain || '-'}</td>
                      <td className="px-3 py-2 text-theme-tertiary">{new Date(op.created_at).toLocaleString()}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <p className="text-xs text-theme-secondary">No key operations recorded yet.</p>
          )}
        </div>
      </SettingsCard>
    </div>
  );
};
