import React, { useState, useEffect } from 'react';
import { 
  paymentGatewaysApi, 
  PaymentGatewaysOverview, 
  GatewayDetails, 
  PaymentTransaction,
  WebhookEvent,
  TestConnectionResult
} from '../../services/paymentGatewaysApi';
import Button from '../../components/ui/Button';

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
  config: any;
  status: any;
  stats: any;
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

  // eslint-disable-next-line security/detect-object-injection
  const info = gatewayInfo[gateway];
  const isConfigured = status.status !== 'not_configured';
  // const isConnected = status.status === 'connected';

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
      {isConfigured && (
        <div className="grid grid-cols-2 gap-4 mb-6 p-4 bg-theme-background-secondary rounded-lg">
          <div className="text-center">
            <div className="text-2xl font-bold text-theme-primary">
              {stats.total_transactions.toLocaleString()}
            </div>
            <div className="text-xs text-theme-secondary mt-1">Total Transactions</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-theme-success">
              {paymentGatewaysApi.formatSuccessRate(stats.success_rate)}
            </div>
            <div className="text-xs text-theme-secondary mt-1">Success Rate</div>
          </div>
          <div className="text-center">
            <div className="text-lg font-semibold text-theme-primary">
              {paymentGatewaysApi.formatCurrency(stats.last_30_days.volume)}
            </div>
            <div className="text-xs text-theme-secondary mt-1">30-Day Volume</div>
          </div>
          <div className="text-center">
            <div className="text-lg font-semibold text-theme-primary">
              {stats.last_30_days.transactions.toLocaleString()}
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
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 11-6 0 3 3 0 616 0z" />
            </svg>
            {isConfigured ? 'Reconfigure' : 'Configure'}
          </Button>
          
          {isConfigured && (
            <Button
              onClick={() => onTestConnection(gateway)}
              disabled={testing || !isConfigured}
              variant="primary"
              size="sm"
              loading={testing}
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

interface TransactionTableProps {
  transactions: PaymentTransaction[];
  loading?: boolean;
}

const TransactionTable: React.FC<TransactionTableProps> = ({ transactions, loading = false }) => {
  if (loading) {
    return (
      <div className="space-y-3">
        {[...Array(5)].map((_, i) => (
          <div key={i} className="animate-pulse">
            <div className="h-16 bg-theme-background-secondary rounded-lg"></div>
          </div>
        ))}
      </div>
    );
  }

  if (transactions.length === 0) {
    return (
      <div className="text-center py-12">
        <svg className="w-12 h-12 text-theme-tertiary mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
        </svg>
        <h3 className="text-lg font-medium text-theme-primary mb-2">No transactions yet</h3>
        <p className="text-theme-secondary">Transactions will appear here once you start processing payments.</p>
      </div>
    );
  }

  return (
    <div className="overflow-hidden">
      <div className="space-y-3">
        {transactions.map((transaction) => (
          <div key={transaction.id} className="bg-theme-surface border border-theme rounded-lg p-4 hover:bg-theme-surface-hover transition-colors">
            <div className="flex items-center justify-between">
              <div className="flex items-center space-x-4">
                <div className="flex-shrink-0">
                  <div className="w-10 h-10 bg-theme-background-secondary rounded-full flex items-center justify-center">
                    <svg className="w-5 h-5 text-theme-secondary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 9V7a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2m2 4h10a2 2 0 002-2v-6a2 2 0 00-2-2H9a2 2 0 00-2 2v6a2 2 0 002 2zm7-5a2 2 0 11-4 0 2 2 0 014 0z" />
                    </svg>
                  </div>
                </div>
                <div>
                  <div className="flex items-center space-x-2">
                    <span className="text-sm font-medium text-theme-primary">
                      #{transaction.id.slice(0, 8)}
                    </span>
                    <StatusBadge status={transaction.status} />
                  </div>
                  <div className="flex items-center space-x-4 mt-1 text-sm text-theme-secondary">
                    <span>{paymentGatewaysApi.getPaymentMethodName(transaction.payment_method)}</span>
                    <span>•</span>
                    <span>{new Date(transaction.created_at).toLocaleDateString()}</span>
                  </div>
                </div>
              </div>
              <div className="text-right">
                <div className="text-lg font-semibold text-theme-primary">
                  {paymentGatewaysApi.formatCurrency(transaction.amount, transaction.currency)}
                </div>
                {transaction.gateway_fee !== "0" && (
                  <div className="text-sm text-theme-secondary">
                    Fee: {paymentGatewaysApi.formatCurrency(transaction.gateway_fee, transaction.currency)}
                  </div>
                )}
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};

interface WebhookTableProps {
  webhooks: WebhookEvent[];
  loading?: boolean;
}

const WebhookTable: React.FC<WebhookTableProps> = ({ webhooks, loading = false }) => {
  if (loading) {
    return (
      <div className="space-y-3">
        {[...Array(5)].map((_, i) => (
          <div key={i} className="animate-pulse">
            <div className="h-16 bg-theme-background-secondary rounded-lg"></div>
          </div>
        ))}
      </div>
    );
  }

  if (webhooks.length === 0) {
    return (
      <div className="text-center py-12">
        <svg className="w-12 h-12 text-theme-tertiary mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8.111 16.404a5.5 5.5 0 017.778 0M12 20h.01m-7.08-7.071c3.904-3.905 10.236-3.905 14.141 0M1.394 9.393c5.857-5.857 15.355-5.857 21.213 0" />
        </svg>
        <h3 className="text-lg font-medium text-theme-primary mb-2">No webhook events</h3>
        <p className="text-theme-secondary">Webhook events will appear here when received from payment providers.</p>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      {webhooks.map((webhook) => (
        <div key={webhook.id} className="bg-theme-surface border border-theme rounded-lg p-4 hover:bg-theme-surface-hover transition-colors">
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-4">
              <div className="flex-shrink-0">
                <div className="w-10 h-10 bg-theme-background-secondary rounded-full flex items-center justify-center">
                  <svg className="w-5 h-5 text-theme-secondary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8.111 16.404a5.5 5.5 0 017.778 0M12 20h.01m-7.08-7.071c3.904-3.905 10.236-3.905 14.141 0M1.394 9.393c5.857-5.857 15.355-5.857 21.213 0" />
                  </svg>
                </div>
              </div>
              <div>
                <div className="flex items-center space-x-2">
                  <span className="text-sm font-medium text-theme-primary">
                    {webhook.event_type}
                  </span>
                  <StatusBadge status={webhook.status} />
                </div>
                <div className="flex items-center space-x-4 mt-1 text-sm text-theme-secondary">
                  <span>ID: {webhook.id.slice(0, 8)}</span>
                  <span>•</span>
                  <span>{new Date(webhook.created_at).toLocaleDateString()}</span>
                </div>
              </div>
            </div>
            <div className="text-right text-sm text-theme-secondary">
              {webhook.processed_at ? (
                <span>Processed {new Date(webhook.processed_at).toLocaleDateString()}</span>
              ) : (
                <span>Pending</span>
              )}
            </div>
          </div>
        </div>
      ))}
    </div>
  );
};

const PaymentGatewaysPage: React.FC = () => {
  const [overview, setOverview] = useState<PaymentGatewaysOverview | null>(null);
  const [selectedGateway, setSelectedGateway] = useState<'stripe' | 'paypal' | null>(null);
  const [gatewayDetails, setGatewayDetails] = useState<GatewayDetails | null>(null);
  const [loading, setLoading] = useState(true);
  const [testing, setTesting] = useState<'stripe' | 'paypal' | null>(null);
  const [testResults, setTestResults] = useState<Record<string, TestConnectionResult>>({});
  const [activeTab, setActiveTab] = useState<'overview' | 'transactions' | 'webhooks'>('overview');
  const [showConfigModal, setShowConfigModal] = useState(false);
  const [configGateway, setConfigGateway] = useState<'stripe' | 'paypal' | null>(null);
  const [configForm, setConfigForm] = useState<any>({});
  const [configLoading, setConfigLoading] = useState(false);
  const [configError, setConfigError] = useState<string | null>(null);

  useEffect(() => {
    loadOverview();
  }, []);

  const loadOverview = async () => {
    try {
      setLoading(true);
      const data = await paymentGatewaysApi.getOverview();
      setOverview(data);
    } catch (error) {
      console.error('Error loading payment gateways overview:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleTestConnection = async (gateway: 'stripe' | 'paypal') => {
    try {
      setTesting(gateway);
      const result = await paymentGatewaysApi.testConnection(gateway);
      setTestResults(prev => ({ ...prev, [gateway]: result }));
      
      // Reload overview to get updated status
      await loadOverview();
    } catch (error) {
      console.error(`Error testing ${gateway} connection:`, error);
    } finally {
      setTesting(null);
    }
  };

  const handleViewDetails = async (gateway: 'stripe' | 'paypal') => {
    try {
      setLoading(true);
      const details = await paymentGatewaysApi.getGatewayDetails(gateway);
      setGatewayDetails(details);
      setSelectedGateway(gateway);
      setActiveTab('overview');
    } catch (error) {
      console.error(`Error loading ${gateway} details:`, error);
    } finally {
      setLoading(false);
    }
  };

  const handleBackToOverview = () => {
    setSelectedGateway(null);
    setGatewayDetails(null);
  };

  const handleConfigureGateway = (gateway: 'stripe' | 'paypal') => {
    setConfigGateway(gateway);
    setConfigError(null);
    
    // Initialize form with current configuration
    if (overview) {
      const config = gateway === 'stripe' ? overview.gateways.stripe : overview.gateways.paypal;
      if (gateway === 'stripe') {
        setConfigForm({
          publishable_key: '',
          secret_key: '',
          endpoint_secret: '',
          webhook_tolerance: config.webhook_tolerance || 300,
          enabled: config.enabled,
          test_mode: config.test_mode
        });
      } else if (gateway === 'paypal') {
        setConfigForm({
          client_id: '',
          client_secret: '',
          webhook_id: '',
          mode: config.mode || 'sandbox',
          enabled: config.enabled,
          test_mode: config.test_mode
        });
      }
    }
    
    setShowConfigModal(true);
  };

  const handleSaveConfiguration = async () => {
    if (!configGateway) return;

    try {
      setConfigLoading(true);
      setConfigError(null);

      await paymentGatewaysApi.updateGatewayConfiguration(configGateway, configForm);
      
      // Reload overview to show updated configuration
      await loadOverview();
      
      setShowConfigModal(false);
      setConfigGateway(null);
      setConfigForm({});
    } catch (error: any) {
      setConfigError(error.response?.data?.error || error.message || 'Failed to save configuration');
    } finally {
      setConfigLoading(false);
    }
  };

  const handleCloseConfigModal = () => {
    setShowConfigModal(false);
    setConfigGateway(null);
    setConfigForm({});
    setConfigError(null);
  };

  if (loading && !overview) {
    return (
      <div className="flex items-center justify-center h-96">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-theme-interactive-primary mx-auto mb-4"></div>
          <p className="text-theme-secondary">Loading payment gateways...</p>
        </div>
      </div>
    );
  }

  if (selectedGateway && gatewayDetails) {
    return (
      <div className="space-y-8">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div className="flex items-center space-x-4">
            <Button
              onClick={handleBackToOverview}
              variant="ghost"
              size="sm"
              className="flex items-center gap-2"
            >
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
              </svg>
              Back to Overview
            </Button>
            <div>
              <h1 className="text-3xl font-bold text-theme-primary">
                {gatewayDetails.configuration.name} Gateway
              </h1>
              <div className="flex items-center gap-2 mt-2">
                <StatusBadge status={gatewayDetails.status.status} />
                {gatewayDetails.configuration.test_mode && (
                  <span className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-theme-warning-background text-theme-warning border border-theme-warning">
                    Test Mode
                  </span>
                )}
              </div>
            </div>
          </div>
        </div>

        {/* Tabs */}
        <div className="border-b border-theme">
          <nav className="-mb-px flex space-x-8">
            {(['overview', 'transactions', 'webhooks'] as const).map((tab) => (
              <button
                key={tab}
                onClick={() => setActiveTab(tab)}
                className={`py-3 px-1 border-b-2 font-medium text-sm transition-colors ${
                  activeTab === tab
                    ? 'border-theme-interactive-primary text-theme-interactive-primary'
                    : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme'
                }`}
              >
                {tab.charAt(0).toUpperCase() + tab.slice(1)}
              </button>
            ))}
          </nav>
        </div>

        {/* Tab Content */}
        <div className="space-y-8">
          {activeTab === 'overview' && (
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
              {/* Configuration Card */}
              <div className="bg-theme-surface border border-theme rounded-xl p-6">
                <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 11-6 0 3 3 0 616 0z" />
                  </svg>
                  Configuration
                </h3>
                <div className="space-y-3">
                  <div className="flex justify-between py-2">
                    <span className="text-theme-secondary">Provider</span>
                    <span className="text-theme-primary font-medium">{gatewayDetails.configuration.provider}</span>
                  </div>
                  <div className="flex justify-between py-2">
                    <span className="text-theme-secondary">Status</span>
                    <StatusBadge status={gatewayDetails.status.status} />
                  </div>
                  <div className="flex justify-between py-2">
                    <span className="text-theme-secondary">Test Mode</span>
                    <span className="text-theme-primary font-medium">
                      {gatewayDetails.configuration.test_mode ? 'Enabled' : 'Disabled'}
                    </span>
                  </div>
                  <div className="flex justify-between py-2">
                    <span className="text-theme-secondary">Enabled</span>
                    <span className="text-theme-primary font-medium">
                      {gatewayDetails.configuration.enabled ? 'Yes' : 'No'}
                    </span>
                  </div>
                </div>
              </div>

              {/* Statistics Card */}
              <div className="bg-theme-surface border border-theme rounded-xl p-6">
                <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
                  </svg>
                  Performance Statistics
                </h3>
                <div className="grid grid-cols-2 gap-4">
                  <div className="text-center p-4 bg-theme-background-secondary rounded-lg">
                    <div className="text-2xl font-bold text-theme-interactive-primary">
                      {gatewayDetails.statistics.total_transactions.toLocaleString()}
                    </div>
                    <div className="text-sm text-theme-secondary mt-1">Total Transactions</div>
                  </div>
                  <div className="text-center p-4 bg-theme-background-secondary rounded-lg">
                    <div className="text-2xl font-bold text-theme-success">
                      {paymentGatewaysApi.formatSuccessRate(gatewayDetails.statistics.success_rate)}
                    </div>
                    <div className="text-sm text-theme-secondary mt-1">Success Rate</div>
                  </div>
                  <div className="text-center p-4 bg-theme-background-secondary rounded-lg">
                    <div className="text-xl font-bold text-theme-link">
                      {paymentGatewaysApi.formatCurrency(gatewayDetails.statistics.total_volume)}
                    </div>
                    <div className="text-sm text-theme-secondary mt-1">Total Volume</div>
                  </div>
                  <div className="text-center p-4 bg-theme-background-secondary rounded-lg">
                    <div className="text-xl font-bold text-theme-warning">
                      {gatewayDetails.statistics.last_30_days.transactions.toLocaleString()}
                    </div>
                    <div className="text-sm text-theme-secondary mt-1">30-Day Count</div>
                  </div>
                </div>
              </div>
            </div>
          )}

          {activeTab === 'transactions' && (
            <div className="bg-theme-surface border border-theme rounded-xl p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-6 flex items-center gap-2">
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
                </svg>
                Recent Transactions
              </h3>
              <TransactionTable transactions={gatewayDetails.transactions} loading={loading} />
            </div>
          )}

          {activeTab === 'webhooks' && (
            <div className="bg-theme-surface border border-theme rounded-xl p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-6 flex items-center gap-2">
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8.111 16.404a5.5 5.5 0 017.778 0M12 20h.01m-7.08-7.071c3.904-3.905 10.236-3.905 14.141 0M1.394 9.393c5.857-5.857 15.355-5.857 21.213 0" />
                </svg>
                Recent Webhook Events
              </h3>
              <WebhookTable webhooks={gatewayDetails.webhooks} loading={loading} />
            </div>
          )}
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-8">
      {/* Header */}
      <div>
        <h1 className="text-3xl font-bold text-theme-primary">Payment Gateways</h1>
        <p className="text-theme-secondary mt-2">
          Manage your payment providers and monitor transaction performance. Configure and test your payment integrations.
        </p>
      </div>

      {/* Overview Stats */}
      {overview && (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div className="bg-theme-surface border border-theme rounded-xl p-6 text-center">
            <div className="w-12 h-12 bg-theme-info rounded-lg flex items-center justify-center mx-auto mb-4">
              <svg className="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
              </svg>
            </div>
            <h3 className="text-lg font-semibold text-theme-primary mb-2">Total Transactions</h3>
            <div className="text-3xl font-bold text-theme-interactive-primary mb-1">
              {overview.statistics.overall.total_transactions.toLocaleString()}
            </div>
            <div className="text-sm text-theme-secondary">
              {overview.statistics.overall.successful_transactions.toLocaleString()} successful
            </div>
          </div>
          
          <div className="bg-theme-surface border border-theme rounded-xl p-6 text-center">
            <div className="w-12 h-12 bg-green-500 rounded-lg flex items-center justify-center mx-auto mb-4">
              <svg className="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
            <h3 className="text-lg font-semibold text-theme-primary mb-2">Success Rate</h3>
            <div className="text-3xl font-bold text-theme-success mb-1">
              {paymentGatewaysApi.formatSuccessRate(overview.statistics.overall.success_rate)}
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
            <div className="text-3xl font-bold text-purple-600 mb-1">
              {paymentGatewaysApi.formatCurrency(overview.statistics.overall.total_volume)}
            </div>
            <div className="text-sm text-theme-secondary">All-time processed</div>
          </div>
        </div>
      )}

      {/* Gateway Cards */}
      {overview && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
          <GatewayCard
            gateway="stripe"
            config={overview.gateways.stripe}
            status={overview.status.stripe}
            stats={overview.statistics.stripe}
            onTestConnection={handleTestConnection}
            onViewDetails={handleViewDetails}
            onConfigure={handleConfigureGateway}
            testing={testing === 'stripe'}
          />
          <GatewayCard
            gateway="paypal"
            config={overview.gateways.paypal}
            status={overview.status.paypal}
            stats={overview.statistics.paypal}
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
                    <div className="flex items-start gap-3 p-3 bg-green-50 border border-green-200 rounded-lg">
                      <svg className="w-5 h-5 text-theme-success mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                      </svg>
                      <div>
                        <div className="text-theme-success font-medium">Connection successful</div>
                        <div className="text-theme-success text-sm">Gateway is operational and ready to process payments</div>
                      </div>
                    </div>
                  ) : (
                    <div className="flex items-start gap-3 p-3 bg-red-50 border border-red-200 rounded-lg">
                      <svg className="w-5 h-5 text-red-600 mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                      </svg>
                      <div>
                        <div className="text-red-800 font-medium">Connection failed</div>
                        <div className="text-red-700 text-sm">{result.error}</div>
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

      {/* Recent Transactions */}
      {overview && overview.recent_transactions.length > 0 && (
        <div className="bg-theme-surface border border-theme rounded-xl p-6">
          <h3 className="text-xl font-semibold text-theme-primary mb-6 flex items-center gap-2">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
            </svg>
            Recent Transactions
          </h3>
          <TransactionTable transactions={overview.recent_transactions} loading={loading} />
        </div>
      )}

      {/* Configuration Modal */}
      {showConfigModal && configGateway && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
          <div className="bg-theme-surface border border-theme rounded-xl max-w-2xl w-full max-h-[90vh] overflow-y-auto">
            <div className="p-6">
              <div className="flex items-center justify-between mb-6">
                <h2 className="text-2xl font-bold text-theme-primary">
                  Configure {configGateway === 'stripe' ? 'Stripe' : 'PayPal'}
                </h2>
                <Button
                  onClick={handleCloseConfigModal}
                  variant="ghost"
                  size="sm"
                  className="text-theme-secondary hover:text-theme-primary"
                >
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </Button>
              </div>

              {configError && (
                <div className="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg">
                  <div className="flex items-start gap-3">
                    <svg className="w-5 h-5 text-red-600 mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                    <div>
                      <div className="text-red-800 font-medium">Configuration Error</div>
                      <div className="text-red-700 text-sm mt-1">{configError}</div>
                    </div>
                  </div>
                </div>
              )}

              <div className="space-y-6">
                {configGateway === 'stripe' && (
                  <>
                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Publishable Key
                      </label>
                      <input
                        type="text"
                        value={configForm.publishable_key || ''}
                        onChange={(e) => setConfigForm({...configForm, publishable_key: e.target.value})}
                        className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
                        placeholder="pk_test_..."
                      />
                    </div>
                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Secret Key
                      </label>
                      <input
                        type="password"
                        value={configForm.secret_key || ''}
                        onChange={(e) => setConfigForm({...configForm, secret_key: e.target.value})}
                        className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
                        placeholder="sk_test_..."
                      />
                    </div>
                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Webhook Endpoint Secret
                      </label>
                      <input
                        type="password"
                        value={configForm.endpoint_secret || ''}
                        onChange={(e) => setConfigForm({...configForm, endpoint_secret: e.target.value})}
                        className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
                        placeholder="whsec_..."
                      />
                    </div>
                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Webhook Tolerance (seconds)
                      </label>
                      <input
                        type="number"
                        value={configForm.webhook_tolerance || 300}
                        onChange={(e) => setConfigForm({...configForm, webhook_tolerance: parseInt(e.target.value)})}
                        className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
                        min="1"
                        max="3600"
                      />
                    </div>
                  </>
                )}

                {configGateway === 'paypal' && (
                  <>
                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Client ID
                      </label>
                      <input
                        type="text"
                        value={configForm.client_id || ''}
                        onChange={(e) => setConfigForm({...configForm, client_id: e.target.value})}
                        className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
                        placeholder="PayPal Client ID"
                      />
                    </div>
                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Client Secret
                      </label>
                      <input
                        type="password"
                        value={configForm.client_secret || ''}
                        onChange={(e) => setConfigForm({...configForm, client_secret: e.target.value})}
                        className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
                        placeholder="PayPal Client Secret"
                      />
                    </div>
                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Webhook ID
                      </label>
                      <input
                        type="text"
                        value={configForm.webhook_id || ''}
                        onChange={(e) => setConfigForm({...configForm, webhook_id: e.target.value})}
                        className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
                        placeholder="PayPal Webhook ID"
                      />
                    </div>
                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Mode
                      </label>
                      <select
                        value={configForm.mode || 'sandbox'}
                        onChange={(e) => setConfigForm({...configForm, mode: e.target.value})}
                        className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
                      >
                        <option value="sandbox">Sandbox (Test)</option>
                        <option value="live">Live (Production)</option>
                      </select>
                    </div>
                  </>
                )}

                <div className="flex items-center justify-between pt-6 border-t border-theme">
                  <label className="flex items-center gap-3">
                    <input
                      type="checkbox"
                      checked={configForm.enabled || false}
                      onChange={(e) => setConfigForm({...configForm, enabled: e.target.checked})}
                      className="w-4 h-4 text-theme-interactive-primary border-theme rounded focus:ring-theme-interactive-primary"
                    />
                    <span className="text-sm text-theme-primary">Enable Gateway</span>
                  </label>

                  <div className="flex gap-3">
                    <Button
                      onClick={handleCloseConfigModal}
                      variant="secondary"
                      size="sm"
                    >
                      Cancel
                    </Button>
                    <Button
                      onClick={handleSaveConfiguration}
                      disabled={configLoading}
                      loading={configLoading}
                      variant="primary"
                      size="sm"
                      className="flex items-center gap-2"
                    >
                      <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                      </svg>
                      {configLoading ? 'Saving...' : 'Save Configuration'}
                    </Button>
                  </div>
                </div>

                <div className="p-4 bg-yellow-50 border border-yellow-200 rounded-lg">
                  <div className="flex items-start gap-3">
                    <svg className="w-5 h-5 text-yellow-600 mt-0.5 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
                      <path fillRule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
                    </svg>
                    <div>
                      <h4 className="text-sm font-medium text-yellow-800">Important Security Note</h4>
                      <p className="text-sm text-yellow-700 mt-1">
                        This configuration is stored securely in environment variables and requires server restart to take effect. 
                        For production use, configure these values through your deployment environment.
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default PaymentGatewaysPage;