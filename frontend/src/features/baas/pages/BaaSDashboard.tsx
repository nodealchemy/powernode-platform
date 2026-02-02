import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import { useNotifications } from '@/shared/hooks/useNotifications';
import baasApi from '../services/baasApi';
import { TenantOverview } from '../components/TenantOverview';
import type { BaaSTenant, BaaSDashboardStats, BaaSApiKey } from '../types';

export const BaaSDashboard: React.FC = () => {
  const navigate = useNavigate();
  const { showNotification } = useNotifications();
  const [tenant, setTenant] = useState<BaaSTenant | null>(null);
  const [stats, setStats] = useState<BaaSDashboardStats | null>(null);
  const [apiKeys, setApiKeys] = useState<BaaSApiKey[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<'overview' | 'api_keys' | 'settings'>('overview');

  const fetchData = async () => {
    setIsLoading(true);
    try {
      const [tenantResponse, dashboardResponse, keysResponse] = await Promise.all([
        baasApi.getTenant(),
        baasApi.getTenantDashboard(),
        baasApi.getApiKeys(),
      ]);
      setTenant(tenantResponse.data);
      setStats(dashboardResponse.data);
      setApiKeys(keysResponse.data);
    } catch {
      const message = error instanceof Error ? error.message : 'Failed to load BaaS data';
      if (message.includes('not found') || message.includes('401')) {
        showNotification('Set up your BaaS tenant to get started', 'info');
      } else {
        showNotification(message, 'error');
      }
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, []);

  const handleCreateApiKey = async () => {
    try {
      const result = await baasApi.createApiKey({
        name: 'New API Key',
        key_type: 'secret',
        scopes: ['*'],
      });
      showNotification(`API Key created. Key: ${result.data.key}`, 'success');
      fetchData();
    } catch {
      const message = error instanceof Error ? error.message : 'Failed to create API key';
      showNotification(message, 'error');
    }
  };

  const handleRevokeApiKey = async (keyId: string) => {
    try {
      await baasApi.revokeApiKey(keyId);
      showNotification('API key revoked', 'success');
      fetchData();
    } catch {
      const message = error instanceof Error ? error.message : 'Failed to revoke API key';
      showNotification(message, 'error');
    }
  };

  if (isLoading) {
    return (
      <PageContainer title="BaaS Dashboard">
        <div className="flex items-center justify-center h-64">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-primary" />
        </div>
      </PageContainer>
    );
  }

  if (!tenant) {
    return (
      <PageContainer
        title="Billing-as-a-Service"
        actions={[
          {
            label: 'Set Up BaaS',
            onClick: () => navigate('/baas/setup'),
            variant: 'primary',
          },
        ]}
      >
        <div className="text-center py-16 bg-theme-bg-primary rounded-lg border border-theme-border">
          <svg
            className="mx-auto h-16 w-16 text-theme-text-secondary"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"
            />
          </svg>
          <h3 className="mt-4 text-lg font-medium text-theme-text-primary">
            Start Billing Your Customers
          </h3>
          <p className="mt-2 text-theme-text-secondary max-w-md mx-auto">
            Set up Billing-as-a-Service to add subscription billing, invoicing,
            and usage metering to your application.
          </p>
          <Button
            variant="primary"
            className="mt-6"
            onClick={() => navigate('/baas/setup')}
          >
            Get Started
          </Button>
        </div>
      </PageContainer>
    );
  }

  const tabs = [
    { id: 'overview', label: 'Overview' },
    { id: 'api_keys', label: 'API Keys' },
    { id: 'settings', label: 'Settings' },
  ];

  return (
    <PageContainer
      title="BaaS Dashboard"
      actions={[
        {
          label: 'API Docs',
          onClick: () => navigate('/baas/docs'),
          variant: 'outline',
        },
        {
          label: 'Manage Customers',
          onClick: () => navigate('/baas/customers'),
          variant: 'primary',
        },
      ]}
    >
      {/* Tabs */}
      <div className="border-b border-theme-border mb-6">
        <nav className="-mb-px flex space-x-8">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id as typeof activeTab)}
              className={`py-4 px-1 border-b-2 font-medium text-sm ${
                activeTab === tab.id
                  ? 'border-theme-primary text-theme-primary'
                  : 'border-transparent text-theme-text-secondary hover:text-theme-text-primary hover:border-theme-border'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </nav>
      </div>

      {/* Overview Tab */}
      {activeTab === 'overview' && stats && (
        <TenantOverview tenant={tenant} stats={stats} />
      )}

      {/* API Keys Tab */}
      {activeTab === 'api_keys' && (
        <div className="space-y-6">
          <div className="flex justify-between items-center">
            <h3 className="text-lg font-semibold text-theme-text-primary">API Keys</h3>
            <Button variant="primary" onClick={handleCreateApiKey}>
              Create API Key
            </Button>
          </div>

          <div className="bg-theme-bg-primary rounded-lg border border-theme-border overflow-hidden">
            {apiKeys.length === 0 ? (
              <div className="p-8 text-center">
                <p className="text-theme-text-secondary">No API keys yet. Create one to get started.</p>
              </div>
            ) : (
              <table className="w-full">
                <thead className="bg-theme-bg-secondary">
                  <tr>
                    <th className="px-6 py-3 text-left text-xs font-medium text-theme-text-secondary uppercase">
                      Name
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-theme-text-secondary uppercase">
                      Key
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-theme-text-secondary uppercase">
                      Type
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-theme-text-secondary uppercase">
                      Last Used
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-theme-text-secondary uppercase">
                      Status
                    </th>
                    <th className="px-6 py-3 text-right text-xs font-medium text-theme-text-secondary uppercase">
                      Actions
                    </th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-theme-border">
                  {apiKeys.map((key) => (
                    <tr key={key.id}>
                      <td className="px-6 py-4 text-theme-text-primary">{key.name}</td>
                      <td className="px-6 py-4 text-theme-text-secondary font-mono text-sm">
                        {key.key_prefix}...
                      </td>
                      <td className="px-6 py-4">
                        <span className="px-2 py-1 bg-theme-bg-secondary rounded text-xs">
                          {key.key_type}
                        </span>
                      </td>
                      <td className="px-6 py-4 text-theme-text-secondary text-sm">
                        {key.last_used_at
                          ? new Date(key.last_used_at).toLocaleDateString()
                          : 'Never'}
                      </td>
                      <td className="px-6 py-4">
                        <span
                          className={`px-2 py-1 rounded-full text-xs font-medium ${
                            key.status === 'active'
                              ? 'bg-theme-success-background text-theme-success'
                              : 'bg-theme-error-background text-theme-error'
                          }`}
                        >
                          {key.status}
                        </span>
                      </td>
                      <td className="px-6 py-4 text-right">
                        {key.status === 'active' && (
                          <button
                            onClick={() => handleRevokeApiKey(key.id)}
                            className="text-theme-error hover:opacity-80 text-sm"
                          >
                            Revoke
                          </button>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </div>
      )}

      {/* Settings Tab */}
      {activeTab === 'settings' && stats?.billing_config && (
        <div className="space-y-6">
          <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
            <h3 className="text-lg font-semibold text-theme-text-primary mb-4">
              Billing Configuration
            </h3>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-theme-text-secondary mb-1">
                  Invoice Due Days
                </label>
                <p className="text-theme-text-primary">{stats.billing_config.invoice_due_days} days</p>
              </div>
              <div>
                <label className="block text-sm font-medium text-theme-text-secondary mb-1">
                  Default Trial Days
                </label>
                <p className="text-theme-text-primary">{stats.billing_config.default_trial_days} days</p>
              </div>
              <div>
                <label className="block text-sm font-medium text-theme-text-secondary mb-1">
                  Platform Fee
                </label>
                <p className="text-theme-text-primary">{stats.billing_config.platform_fee_percentage}%</p>
              </div>
              <div>
                <label className="block text-sm font-medium text-theme-text-secondary mb-1">
                  Auto Invoice
                </label>
                <p className="text-theme-text-primary">
                  {stats.billing_config.auto_invoice ? 'Enabled' : 'Disabled'}
                </p>
              </div>
            </div>
            <Button variant="outline" className="mt-4" onClick={() => navigate('/baas/settings')}>
              Edit Settings
            </Button>
          </div>

          <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
            <h3 className="text-lg font-semibold text-theme-text-primary mb-4">
              Payment Gateways
            </h3>
            <div className="space-y-4">
              <div className="flex items-center justify-between p-4 bg-theme-bg-secondary rounded-lg">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 bg-theme-primary/10 rounded-lg flex items-center justify-center">
                    <span className="text-theme-primary font-bold">S</span>
                  </div>
                  <div>
                    <p className="font-medium text-theme-text-primary">Stripe</p>
                    <p className="text-sm text-theme-text-secondary">
                      {stats.billing_config.stripe_connected ? 'Connected' : 'Not connected'}
                    </p>
                  </div>
                </div>
                <Button variant="outline" size="sm">
                  {stats.billing_config.stripe_connected ? 'Manage' : 'Connect'}
                </Button>
              </div>
              <div className="flex items-center justify-between p-4 bg-theme-bg-secondary rounded-lg">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 bg-theme-interactive-primary/10 rounded-lg flex items-center justify-center">
                    <span className="text-theme-interactive-primary font-bold">P</span>
                  </div>
                  <div>
                    <p className="font-medium text-theme-text-primary">PayPal</p>
                    <p className="text-sm text-theme-text-secondary">
                      {stats.billing_config.paypal_connected ? 'Connected' : 'Not connected'}
                    </p>
                  </div>
                </div>
                <Button variant="outline" size="sm">
                  {stats.billing_config.paypal_connected ? 'Manage' : 'Connect'}
                </Button>
              </div>
            </div>
          </div>
        </div>
      )}
    </PageContainer>
  );
};

export default BaaSDashboard;
