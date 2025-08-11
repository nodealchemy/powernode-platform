import React, { useState, useEffect } from 'react';
import { 
  paymentGatewaysApi, 
  PaymentGatewaysOverview, 
  GatewayDetails, 
  PaymentTransaction,
  WebhookEvent,
  TestConnectionResult
} from '../../services/paymentGatewaysApi';

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
        return 'bg-theme-success text-theme-success border-theme-success';
      case 'yellow':
        return 'bg-theme-warning text-theme-warning border-theme-warning';
      case 'red':
        return 'bg-theme-error text-theme-error border-theme-error';
      case 'gray':
      default:
        return 'bg-theme-background-tertiary text-theme-secondary border-theme';
    }
  };

  return (
    <span className={`px-2 py-1 text-xs rounded-full border ${getColorClasses(colorClass)}`}>
      {displayText}
    </span>
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
            <div className="h-12 bg-theme-background-tertiary rounded"></div>
          </div>
        ))}
      </div>
    );
  }

  return (
    <div className="overflow-x-auto">
      <table className="min-w-full divide-y divide-theme">
        <thead className="bg-theme-background-secondary">
          <tr>
            <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">
              Transaction
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">
              Amount
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">
              Method
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">
              Status
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">
              Date
            </th>
          </tr>
        </thead>
        <tbody className="bg-theme-surface divide-y divide-theme">
          {transactions.map((transaction) => (
            <tr key={transaction.id} className="hover:bg-theme-surface-hover">
              <td className="px-6 py-4 whitespace-nowrap">
                <div className="text-sm font-medium text-theme-primary">
                  #{transaction.id.slice(0, 8)}
                </div>
                <div className="text-sm text-theme-secondary">
                  Invoice: {transaction.invoice_id?.slice(0, 8)}
                </div>
              </td>
              <td className="px-6 py-4 whitespace-nowrap">
                <div className="text-sm font-medium text-theme-primary">
                  {paymentGatewaysApi.formatCurrency(transaction.amount, transaction.currency)}
                </div>
                {transaction.gateway_fee !== "0" && (
                  <div className="text-sm text-theme-secondary">
                    Fee: {paymentGatewaysApi.formatCurrency(transaction.gateway_fee, transaction.currency)}
                  </div>
                )}
              </td>
              <td className="px-6 py-4 whitespace-nowrap">
                <span className="text-sm text-theme-primary">
                  {paymentGatewaysApi.getPaymentMethodName(transaction.payment_method)}
                </span>
              </td>
              <td className="px-6 py-4 whitespace-nowrap">
                <StatusBadge status={transaction.status} />
              </td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-secondary">
                {new Date(transaction.created_at).toLocaleDateString()}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
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
            <div className="h-12 bg-theme-background-tertiary rounded"></div>
          </div>
        ))}
      </div>
    );
  }

  return (
    <div className="overflow-x-auto">
      <table className="min-w-full divide-y divide-theme">
        <thead className="bg-theme-background-secondary">
          <tr>
            <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">
              Event
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">
              Status
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">
              Processed
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">
              Created
            </th>
          </tr>
        </thead>
        <tbody className="bg-theme-surface divide-y divide-theme">
          {webhooks.map((webhook) => (
            <tr key={webhook.id} className="hover:bg-theme-surface-hover">
              <td className="px-6 py-4 whitespace-nowrap">
                <div className="text-sm font-medium text-theme-primary">
                  {webhook.event_type}
                </div>
                <div className="text-sm text-theme-secondary">
                  ID: {webhook.id.slice(0, 8)}
                </div>
              </td>
              <td className="px-6 py-4 whitespace-nowrap">
                <StatusBadge status={webhook.status} />
              </td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-secondary">
                {webhook.processed_at ? new Date(webhook.processed_at).toLocaleDateString() : '-'}
              </td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-secondary">
                {new Date(webhook.created_at).toLocaleDateString()}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
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
  
  return (
    <div className="card-theme p-6">
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center space-x-3">
          <div className="w-12 h-12 bg-theme-background-secondary rounded-lg flex items-center justify-center">
            <span className="text-lg font-semibold text-theme-secondary">
              {gateway === 'stripe' ? 'S' : 'P'}
            </span>
          </div>
          <div>
            <h3 className="text-lg font-semibold text-theme-primary">{config.name}</h3>
            <div className="flex items-center space-x-2">
              <StatusBadge status={status.status} />
              {config.test_mode && (
                <span className="px-2 py-1 text-xs bg-theme-info text-theme-info rounded-full">
                  Test Mode
                </span>
              )}
            </div>
          </div>
        </div>
        <div className="flex space-x-2">
          <button
            onClick={() => onConfigure(gateway)}
            className="btn-theme btn-theme-success text-white"
          >
            Configure
          </button>
          <button
            onClick={() => onTestConnection(gateway)}
            disabled={testing || status.status === 'not_configured'}
            className="btn-theme btn-theme-primary"
          >
            {testing ? 'Testing...' : 'Test'}
          </button>
          <button
            onClick={() => onViewDetails(gateway)}
            className="btn-theme btn-theme-secondary btn-theme-sm"
          >
            Details
          </button>
        </div>
      </div>

      <div className="space-y-3 text-sm">
        <div className="flex justify-between">
          <span className="text-theme-secondary">Status:</span>
          <span className="text-theme-primary">{status.message}</span>
        </div>
        <div className="flex justify-between">
          <span className="text-theme-secondary">Total Transactions:</span>
          <span className="text-theme-primary">{stats.total_transactions.toLocaleString()}</span>
        </div>
        <div className="flex justify-between">
          <span className="text-theme-secondary">Success Rate:</span>
          <span className="text-theme-primary">{paymentGatewaysApi.formatSuccessRate(stats.success_rate)}</span>
        </div>
        <div className="flex justify-between">
          <span className="text-theme-secondary">30-Day Volume:</span>
          <span className="text-theme-primary">
            {paymentGatewaysApi.formatCurrency(stats.last_30_days.volume)}
          </span>
        </div>
      </div>
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
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-theme-link"></div>
      </div>
    );
  }

  if (selectedGateway && gatewayDetails) {
    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div className="flex items-center space-x-4">
            <button
              onClick={handleBackToOverview}
              className="btn-theme btn-theme-secondary btn-theme-sm"
            >
              ← Back
            </button>
            <h1 className="text-2xl font-bold text-theme-primary">
              {gatewayDetails.configuration.name} Gateway
            </h1>
            <StatusBadge status={gatewayDetails.status.status} />
          </div>
        </div>

        {/* Gateway Details Tabs */}
        <div className="border-b border-theme">
          <nav className="-mb-px flex space-x-8">
            {(['overview', 'transactions', 'webhooks'] as const).map((tab) => (
              <button
                key={tab}
                onClick={() => setActiveTab(tab)}
                className={`py-2 px-1 border-b-2 font-medium text-sm ${
                  activeTab === tab
                    ? 'border-theme-focus text-theme-link'
                    : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme'
                }`}
              >
                {tab.charAt(0).toUpperCase() + tab.slice(1)}
              </button>
            ))}
          </nav>
        </div>

        {/* Tab Content */}
        <div className="space-y-6">
          {activeTab === 'overview' && (
            <>
              {/* Configuration Info */}
              <div className="card-theme p-6">
                <h3 className="text-lg font-semibold text-theme-primary mb-4">Configuration</h3>
                <div className="grid grid-cols-2 gap-4 text-sm">
                  <div className="flex justify-between">
                    <span className="text-theme-secondary">Provider:</span>
                    <span className="text-theme-primary">{gatewayDetails.configuration.provider}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-theme-secondary">Status:</span>
                    <StatusBadge status={gatewayDetails.status.status} />
                  </div>
                  <div className="flex justify-between">
                    <span className="text-theme-secondary">Test Mode:</span>
                    <span className="text-theme-primary">
                      {gatewayDetails.configuration.test_mode ? 'Yes' : 'No'}
                    </span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-theme-secondary">Enabled:</span>
                    <span className="text-theme-primary">
                      {gatewayDetails.configuration.enabled ? 'Yes' : 'No'}
                    </span>
                  </div>
                </div>
              </div>

              {/* Statistics */}
              <div className="card-theme p-6">
                <h3 className="text-lg font-semibold text-theme-primary mb-4">Statistics</h3>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                  <div className="text-center">
                    <div className="text-2xl font-bold text-theme-interactive-primary">
                      {gatewayDetails.statistics.total_transactions.toLocaleString()}
                    </div>
                    <div className="text-sm text-theme-secondary">Total Transactions</div>
                  </div>
                  <div className="text-center">
                    <div className="text-2xl font-bold text-theme-success">
                      {paymentGatewaysApi.formatSuccessRate(gatewayDetails.statistics.success_rate)}
                    </div>
                    <div className="text-sm text-theme-secondary">Success Rate</div>
                  </div>
                  <div className="text-center">
                    <div className="text-2xl font-bold text-theme-link">
                      {paymentGatewaysApi.formatCurrency(gatewayDetails.statistics.total_volume)}
                    </div>
                    <div className="text-sm text-theme-secondary">Total Volume</div>
                  </div>
                  <div className="text-center">
                    <div className="text-2xl font-bold text-theme-info">
                      {gatewayDetails.statistics.last_30_days.transactions.toLocaleString()}
                    </div>
                    <div className="text-sm text-theme-secondary">30-Day Transactions</div>
                  </div>
                </div>
              </div>
            </>
          )}

          {activeTab === 'transactions' && (
            <div className="card-theme p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4">Recent Transactions</h3>
              <TransactionTable transactions={gatewayDetails.transactions} loading={loading} />
            </div>
          )}

          {activeTab === 'webhooks' && (
            <div className="card-theme p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4">Recent Webhook Events</h3>
              <WebhookTable webhooks={gatewayDetails.webhooks} loading={loading} />
            </div>
          )}
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-theme-primary">Payment Gateways</h1>
      </div>

      {/* Overview Stats */}
      {overview && (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div className="card-theme p-6">
            <h3 className="text-lg font-semibold text-theme-primary mb-2">Total Transactions</h3>
            <div className="text-3xl font-bold text-theme-interactive-primary">
              {overview.statistics.overall.total_transactions.toLocaleString()}
            </div>
            <div className="text-sm text-theme-secondary">
              {overview.statistics.overall.successful_transactions} successful
            </div>
          </div>
          <div className="card-theme p-6">
            <h3 className="text-lg font-semibold text-theme-primary mb-2">Success Rate</h3>
            <div className="text-3xl font-bold text-theme-success">
              {paymentGatewaysApi.formatSuccessRate(overview.statistics.overall.success_rate)}
            </div>
            <div className="text-sm text-theme-secondary">Overall performance</div>
          </div>
          <div className="card-theme p-6">
            <h3 className="text-lg font-semibold text-theme-primary mb-2">Total Volume</h3>
            <div className="text-3xl font-bold text-theme-link">
              {paymentGatewaysApi.formatCurrency(overview.statistics.overall.total_volume)}
            </div>
            <div className="text-sm text-theme-secondary">All-time processed</div>
          </div>
        </div>
      )}

      {/* Gateway Cards */}
      {overview && (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
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
        <div className="space-y-4">
          <h3 className="text-lg font-semibold text-theme-primary">Connection Test Results</h3>
          {Object.entries(testResults).map(([gateway, result]) => (
            <div key={gateway} className="card-theme p-6">
              <div className="flex items-center justify-between mb-3">
                <h4 className="font-medium text-theme-primary capitalize">{gateway} Test Result</h4>
                <StatusBadge status={result.success ? 'connected' : 'error'} />
              </div>
              <div className="text-sm space-y-2">
                {result.success ? (
                  <div className="text-theme-success">
                    ✓ Connection successful - Gateway is operational
                  </div>
                ) : (
                  <div className="text-theme-error">
                    ✗ Connection failed: {result.error}
                  </div>
                )}
                <div className="text-theme-secondary">
                  Tested: {new Date(result.tested_at).toLocaleString()}
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Recent Transactions */}
      {overview && overview.recent_transactions.length > 0 && (
        <div className="card-theme p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">Recent Transactions</h3>
          <TransactionTable transactions={overview.recent_transactions} loading={loading} />
        </div>
      )}

      {/* Configuration Modal */}
      {showConfigModal && configGateway && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="card-theme max-w-2xl w-full mx-4 max-h-[90vh] overflow-y-auto">
            <div className="p-6">
              <div className="flex items-center justify-between mb-6">
                <h2 className="text-xl font-semibold text-theme-primary">
                  Configure {configGateway === 'stripe' ? 'Stripe' : 'PayPal'}
                </h2>
                <button
                  onClick={handleCloseConfigModal}
                  className="text-theme-tertiary hover:text-theme-secondary"
                >
                  <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>

              {configError && (
                <div className="mb-6 alert-theme alert-theme-error">
                  <p className="text-sm">{configError}</p>
                </div>
              )}

              {configGateway === 'stripe' && (
                <div className="space-y-4">
                  <div>
                    <label className="label-theme">
                      Publishable Key
                    </label>
                    <input
                      type="text"
                      value={configForm.publishable_key || ''}
                      onChange={(e) => setConfigForm({...configForm, publishable_key: e.target.value})}
                      className="input-theme"
                      placeholder="pk_test_..."
                    />
                  </div>
                  <div>
                    <label className="label-theme">
                      Secret Key
                    </label>
                    <input
                      type="password"
                      value={configForm.secret_key || ''}
                      onChange={(e) => setConfigForm({...configForm, secret_key: e.target.value})}
                      className="input-theme"
                      placeholder="sk_test_..."
                    />
                  </div>
                  <div>
                    <label className="label-theme">
                      Webhook Endpoint Secret
                    </label>
                    <input
                      type="password"
                      value={configForm.endpoint_secret || ''}
                      onChange={(e) => setConfigForm({...configForm, endpoint_secret: e.target.value})}
                      className="input-theme"
                      placeholder="whsec_..."
                    />
                  </div>
                  <div>
                    <label className="label-theme">
                      Webhook Tolerance (seconds)
                    </label>
                    <input
                      type="number"
                      value={configForm.webhook_tolerance || 300}
                      onChange={(e) => setConfigForm({...configForm, webhook_tolerance: parseInt(e.target.value)})}
                      className="input-theme"
                      min="1"
                      max="3600"
                    />
                  </div>
                </div>
              )}

              {configGateway === 'paypal' && (
                <div className="space-y-4">
                  <div>
                    <label className="label-theme">
                      Client ID
                    </label>
                    <input
                      type="text"
                      value={configForm.client_id || ''}
                      onChange={(e) => setConfigForm({...configForm, client_id: e.target.value})}
                      className="input-theme"
                      placeholder="PayPal Client ID"
                    />
                  </div>
                  <div>
                    <label className="label-theme">
                      Client Secret
                    </label>
                    <input
                      type="password"
                      value={configForm.client_secret || ''}
                      onChange={(e) => setConfigForm({...configForm, client_secret: e.target.value})}
                      className="input-theme"
                      placeholder="PayPal Client Secret"
                    />
                  </div>
                  <div>
                    <label className="label-theme">
                      Webhook ID
                    </label>
                    <input
                      type="text"
                      value={configForm.webhook_id || ''}
                      onChange={(e) => setConfigForm({...configForm, webhook_id: e.target.value})}
                      className="input-theme"
                      placeholder="PayPal Webhook ID"
                    />
                  </div>
                  <div>
                    <label className="label-theme">
                      Mode
                    </label>
                    <select
                      value={configForm.mode || 'sandbox'}
                      onChange={(e) => setConfigForm({...configForm, mode: e.target.value})}
                      className="input-theme"
                    >
                      <option value="sandbox">Sandbox (Test)</option>
                      <option value="live">Live (Production)</option>
                    </select>
                  </div>
                </div>
              )}

              <div className="flex items-center justify-between mt-6 pt-6 border-t border-theme">
                <div className="flex items-center space-x-4">
                  <label className="flex items-center">
                    <input
                      type="checkbox"
                      checked={configForm.enabled || false}
                      onChange={(e) => setConfigForm({...configForm, enabled: e.target.checked})}
                      className="rounded border-theme text-theme-interactive-primary focus:ring-theme-focus"
                    />
                    <span className="ml-2 text-sm text-theme-secondary">Enable Gateway</span>
                  </label>
                </div>

                <div className="flex space-x-3">
                  <button
                    onClick={handleCloseConfigModal}
                    className="btn-theme btn-theme-secondary btn-theme-sm"
                  >
                    Cancel
                  </button>
                  <button
                    onClick={handleSaveConfiguration}
                    disabled={configLoading}
                    className="btn-theme btn-theme-primary"
                  >
                    {configLoading ? 'Saving...' : 'Save Configuration'}
                  </button>
                </div>
              </div>

              <div className="mt-4 alert-theme alert-theme-warning">
                <div className="flex">
                  <svg className="w-5 h-5 text-theme-warning mr-2" fill="currentColor" viewBox="0 0 20 20">
                    <path fillRule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
                  </svg>
                  <div>
                    <h4 className="text-sm font-medium text-theme-warning">Important Note</h4>
                    <p className="text-sm text-theme-warning mt-1">
                      This configuration is stored in environment variables and requires server restart to take effect. 
                      For production use, configure these values through your deployment environment.
                    </p>
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