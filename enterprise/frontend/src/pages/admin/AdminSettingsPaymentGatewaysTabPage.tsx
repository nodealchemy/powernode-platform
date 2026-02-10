import React, { useState, useEffect } from 'react';
import { useSelector } from 'react-redux';
import {
  paymentGatewaysApi,
  PaymentGatewaysOverview,
  TestConnectionResult,
  PaymentGatewayConfig,
  PaymentGatewayStatus,
  GatewayStats
} from '@/features/business/payment-gateways/services/paymentGatewaysApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { GatewayConfigModal } from '@/features/business/payment-gateways/components/GatewayConfigModal';
import Button from '@/shared/components/ui/Button';
import { RootState } from '@/shared/services';
import { hasPermissions } from '@/shared/utils/permissionUtils';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';

interface StatusBadgeProps {
  status: string;
  text?: string;
}

const StatusBadge: React.FC<StatusBadgeProps> = ({ status, text }) => {
  const colorClass = paymentGatewaysApi.getStatusColor(status);
  const displayText = text || paymentGatewaysApi.getStatusText(status);
  
  const getColorClasses = (color: 'green' | 'yellow' | 'red' | 'gray'): string => {
    switch (color) {
      case 'green':
        return 'bg-theme-success-background text-theme-success border-theme-success ring-theme-success/20';
      case 'yellow':
        return 'bg-theme-warning-background text-theme-warning border-theme-warning ring-theme-warning/20';
      case 'red':
        return 'bg-theme-error-background text-theme-error border-theme-error ring-theme-error/20';
      case 'gray':
      default:
        return 'bg-theme-background-secondary text-theme-secondary border-theme ring-theme-secondary/20';
    }
  };

  return (
    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium border ring-1 ring-inset ${getColorClasses(colorClass)}`}>
      {displayText}
    </span>
  );
};

interface GatewayCardProps {
  gateway: 'stripe' | 'paypal';
  config: PaymentGatewayConfig;
  status: PaymentGatewayStatus;
  stats?: GatewayStats;
  onTestConnection: (gateway: 'stripe' | 'paypal') => void;
  onViewDetails: (gateway: 'stripe' | 'paypal') => void;
  onConfigure: (gateway: 'stripe' | 'paypal') => void;
  testing: boolean;
}

const GatewayCard: React.FC<GatewayCardProps> = ({ 
  gateway, 
  config, 
  status, 
  stats, 
  onTestConnection, 
  onViewDetails,
  onConfigure,
  testing 
}) => {
  const gatewayInfo = {
    stripe: {
      name: 'Stripe',
      logo: '💳',
      color: 'bg-theme-interactive-secondary',
      description: 'Accept credit cards, debit cards, and popular payment methods'
    },
    paypal: {
      name: 'PayPal',
      logo: '🅿️',
      color: 'bg-theme-info', 
      description: 'Accept PayPal payments and other digital wallets'
    }
  };

   
  const info = gatewayInfo[gateway];
  const isConfigured = status.status !== 'not_configured';

  return (
    <div className="bg-theme-surface border border-theme rounded-xl p-6 hover:shadow-lg transition-all duration-200">
      {/* Header */}
      <div className="flex items-start justify-between mb-6">
        <div className="flex items-center space-x-4">
          <div className={`w-12 h-12 ${info.color} rounded-lg flex items-center justify-center text-white text-xl font-bold shadow-lg`}>
            {info.logo}
          </div>
          <div>
            <h3 className="text-lg font-semibold text-theme-primary">{info.name}</h3>
            <p className="text-sm text-theme-secondary mt-1">{info.description}</p>
            <div className="flex items-center gap-2 mt-2">
              <StatusBadge status={status.status} />
              {config.test_mode && (
                <span className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-theme-warning-background text-theme-warning border border-theme-warning">
                  Test Mode
                </span>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Stats Grid */}
      {isConfigured && stats && (
        <div className="grid grid-cols-2 gap-4 mb-6 p-4 bg-theme-background-secondary rounded-lg">
          <div className="text-center">
            <div className="text-2xl font-bold text-theme-primary">
              {(stats.total_transactions || 0).toLocaleString()}
            </div>
            <div className="text-xs text-theme-secondary mt-1">Total Transactions</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-theme-success">
              {paymentGatewaysApi.formatSuccessRate(stats.success_rate || 0)}
            </div>
            <div className="text-xs text-theme-secondary mt-1">Success Rate</div>
          </div>
          <div className="text-center">
            <div className="text-lg font-semibold text-theme-primary">
              {paymentGatewaysApi.formatCurrency(stats.last_30_days?.volume || 0)}
            </div>
            <div className="text-xs text-theme-secondary mt-1">30-Day Volume</div>
          </div>
          <div className="text-center">
            <div className="text-lg font-semibold text-theme-primary">
              {(stats.last_30_days?.transactions || 0).toLocaleString()}
            </div>
            <div className="text-xs text-theme-secondary mt-1">30-Day Count</div>
          </div>
        </div>
      )}

      {/* Actions */}
      <div className="flex items-center justify-between pt-4 border-t border-theme">
        <div className="flex items-center space-x-3">
          <Button
            onClick={() => onConfigure(gateway)}
            variant={isConfigured ? "secondary" : "primary"}
            size="sm"
            className="flex items-center gap-2"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0z" />
            </svg>
            {isConfigured ? 'Reconfigure' : 'Configure'}
          </Button>
          
          {isConfigured && (
            <Button
              onClick={() => onTestConnection(gateway)}
              disabled={testing || !isConfigured}
              variant="primary"
              size="sm"
              className="flex items-center gap-2"
            >
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              {testing ? 'Testing...' : 'Test Connection'}
            </Button>
          )}
        </div>

        {isConfigured && (
          <Button
            onClick={() => onViewDetails(gateway)}
            variant="ghost"
            size="sm"
            className="flex items-center gap-2 text-theme-secondary hover:text-theme-primary"
          >
            <span>View Details</span>
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
            </svg>
          </Button>
        )}
      </div>
    </div>
  );
};

export const AdminSettingsPaymentGatewaysTabPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const { showNotification } = useNotifications();
  const [overview, setOverview] = useState<PaymentGatewaysOverview | null>(null);
  const [loading, setLoading] = useState(true);
  const [testing, setTesting] = useState<'stripe' | 'paypal' | null>(null);
  const [testResults, setTestResults] = useState<Record<string, TestConnectionResult>>({});
  const [configModal, setConfigModal] = useState<{ isOpen: boolean; gateway: 'stripe' | 'paypal' | null }>({ 
    isOpen: false, 
    gateway: null 
  });

  // Check if user has payment gateway management permission
  // Allow access with either payment-specific or general admin settings permissions
  const canManagePaymentGateways = hasPermissions(user, ['admin.settings.payment']) || 
                                   hasPermissions(user, ['admin.settings.read']) ||
                                   hasPermissions(user, ['admin.billing.read']);

  useEffect(() => {
    if (canManagePaymentGateways) {
      loadOverview();
    }
  }, [canManagePaymentGateways]);
  
  // Redirect if user doesn't have permission
  if (!canManagePaymentGateways) {
    return (
      <div className="bg-theme-surface rounded-lg border border-theme p-6">
        <div className="text-center">
          <h2 className="text-xl font-semibold text-theme-primary mb-4">Access Denied</h2>
          <p className="text-theme-secondary mb-4">You don't have permission to access payment gateways settings.</p>
          <p className="text-sm text-theme-tertiary">Required permissions: admin.settings.payment, admin.settings.read, or admin.billing.read</p>
          <div className="mt-4 p-4 bg-theme-background-secondary rounded">
            <p className="text-xs text-theme-tertiary">User permissions: {user?.permissions?.join(', ') || 'None'}</p>
          </div>
        </div>
      </div>
    );
  }

  const loadOverview = async () => {
    try {
      setLoading(true);
      const data = await paymentGatewaysApi.getOverview();
      setOverview(data);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to load payment gateway overview';
      showNotification(errorMessage, 'error');
    } finally {
      setLoading(false);
    }
  };

  const handleTestConnection = async (gateway: 'stripe' | 'paypal') => {
    try {
      setTesting(gateway);
      showNotification(`Starting ${gateway} connection test...`, 'info');
      
      // Use the new async pattern with polling
      const result = await paymentGatewaysApi.testConnectionAndWait(gateway);
      setTestResults(prev => ({ ...prev, [gateway]: result }));
      
      if (result.success) {
        showNotification(`${gateway.charAt(0).toUpperCase() + gateway.slice(1)} connection test successful!`, 'success');
      } else {
        showNotification(`${gateway.charAt(0).toUpperCase() + gateway.slice(1)} connection test failed: ${result.error || 'Unknown error'}`, 'error');
      }
      
      // Reload overview to get updated status
      await loadOverview();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : `Failed to test ${gateway} connection`;
      setTestResults(prev => ({ 
        ...prev, 
        [gateway]: { 
          success: false, 
          gateway, 
          error: errorMessage,
          tested_at: new Date().toISOString()
        } 
      }));
      showNotification(`${gateway.charAt(0).toUpperCase() + gateway.slice(1)} connection test failed: ${errorMessage}`, 'error');
    } finally {
      setTesting(null);
    }
  };

  const handleViewDetails = async (gateway: 'stripe' | 'paypal') => {
    // For simplicity in admin settings, we'll just show a notification
    // In a full implementation, you could show a modal or redirect
    showNotification(`View ${gateway} details - Feature can be expanded to show modal with gateway details`, 'info');
  };

  const handleConfigureGateway = (gateway: 'stripe' | 'paypal') => {
    setConfigModal({ isOpen: true, gateway });
  };

  const handleCloseConfigModal = () => {
    setConfigModal({ isOpen: false, gateway: null });
  };

  const handleConfigurationSaved = () => {
    // Reload overview after configuration changes
    loadOverview();
  };

  if (loading && !overview) {
    return (
      <LoadingSpinner size="lg" className="h-96" message="Loading payment gateways..." />
    );
  }

  return (
    <div className="space-y-6">

      {/* Overview Stats */}
      {overview && overview.statistics?.overall && (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div className="bg-theme-surface border border-theme rounded-xl p-6 text-center">
            <div className="w-12 h-12 bg-theme-info rounded-lg flex items-center justify-center mx-auto mb-4">
              <svg className="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
              </svg>
            </div>
            <h3 className="text-lg font-semibold text-theme-primary mb-2">Total Transactions</h3>
            <div className="text-3xl font-bold text-theme-interactive-primary mb-1">
              {(overview.statistics?.overall?.total_transactions || 0).toLocaleString()}
            </div>
            <div className="text-sm text-theme-secondary">
              {(overview.statistics?.overall?.successful_transactions || 0).toLocaleString()} successful
            </div>
          </div>
          
          <div className="bg-theme-surface border border-theme rounded-xl p-6 text-center">
            <div className="w-12 h-12 bg-theme-success rounded-lg flex items-center justify-center mx-auto mb-4">
              <svg className="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
            <h3 className="text-lg font-semibold text-theme-primary mb-2">Success Rate</h3>
            <div className="text-3xl font-bold text-theme-success mb-1">
              {paymentGatewaysApi.formatSuccessRate(overview.statistics?.overall?.success_rate || 0)}
            </div>
            <div className="text-sm text-theme-secondary">Overall performance</div>
          </div>
          
          <div className="bg-theme-surface border border-theme rounded-xl p-6 text-center">
            <div className="w-12 h-12 bg-theme-interactive-secondary rounded-lg flex items-center justify-center mx-auto mb-4">
              <svg className="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1" />
              </svg>
            </div>
            <h3 className="text-lg font-semibold text-theme-primary mb-2">Total Volume</h3>
            <div className="text-3xl font-bold text-theme-interactive-primary mb-1">
              {paymentGatewaysApi.formatCurrency(overview.statistics?.overall?.total_volume || 0)}
            </div>
            <div className="text-sm text-theme-secondary">All-time processed</div>
          </div>
        </div>
      )}

      {/* Gateway Cards */}
      {overview && overview.gateways && overview.status && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
          <GatewayCard
            gateway="stripe"
            config={overview.gateways.stripe}
            status={overview.status.stripe}
            stats={overview.statistics?.stripe}
            onTestConnection={handleTestConnection}
            onViewDetails={handleViewDetails}
            onConfigure={handleConfigureGateway}
            testing={testing === 'stripe'}
          />
          <GatewayCard
            gateway="paypal"
            config={overview.gateways.paypal}
            status={overview.status.paypal}
            stats={overview.statistics?.paypal}
            onTestConnection={handleTestConnection}
            onViewDetails={handleViewDetails}
            onConfigure={handleConfigureGateway}
            testing={testing === 'paypal'}
          />
        </div>
      )}

      {/* Test Results */}
      {Object.keys(testResults).length > 0 && (
        <div className="space-y-6">
          <h3 className="text-xl font-semibold text-theme-primary">Connection Test Results</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {Object.entries(testResults).map(([gateway, result]) => (
              <div key={gateway} className="bg-theme-surface border border-theme rounded-xl p-6">
                <div className="flex items-center justify-between mb-4">
                  <h4 className="font-semibold text-theme-primary capitalize flex items-center gap-2">
                    <div className={`w-8 h-8 rounded-lg flex items-center justify-center text-white ${gateway === 'stripe' ? 'bg-theme-interactive-secondary' : 'bg-theme-info'}`}>
                      {gateway === 'stripe' ? '💳' : '🅿️'}
                    </div>
                    {gateway} Test Result
                  </h4>
                  <StatusBadge status={result.success ? 'connected' : 'error'} />
                </div>
                <div className="space-y-3">
                  {result.success ? (
                    <div className="flex items-start gap-3 p-3 bg-theme-success-background border border-theme-success-border rounded-lg">
                      <svg className="w-5 h-5 text-theme-success mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                      </svg>
                      <div>
                        <div className="text-theme-success font-medium">Connection successful</div>
                        <div className="text-theme-success text-sm">Gateway is operational and ready to process payments</div>
                      </div>
                    </div>
                  ) : (
                    <div className="flex items-start gap-3 p-3 bg-theme-error-background border border-theme-error-border rounded-lg">
                      <svg className="w-5 h-5 text-theme-error mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                      </svg>
                      <div>
                        <div className="text-theme-error font-medium">Connection failed</div>
                        <div className="text-theme-error text-sm opacity-90">{result.error}</div>
                      </div>
                    </div>
                  )}
                  <div className="text-sm text-theme-secondary">
                    Tested: {new Date(result.tested_at).toLocaleString()}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Configuration Modal */}
      {configModal.gateway && (
        <GatewayConfigModal
          isOpen={configModal.isOpen}
          onClose={handleCloseConfigModal}
          gateway={configModal.gateway}
          currentConfig={overview?.gateways[configModal.gateway]}
          onConfigured={handleConfigurationSaved}
        />
      )}
    </div>
  );
};

export default AdminSettingsPaymentGatewaysTabPage;