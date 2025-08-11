import React, { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { RootState } from '../../store';
import { 
  adminApi, 
  AdminSettingsData, 
  AdminUser, 
  AdminAccount, 
  AdminLog,
  SystemSettings
} from '../../services/adminApi';
import { serviceAPI, Service } from '../../services/serviceApi';
import { ServiceList } from '../../components/services/ServiceList';
import { ServiceDetails } from '../../components/services/ServiceDetails';
import { CreateServiceModal } from '../../components/services/CreateServiceModal';
import { 
  paymentGatewaysApi, 
  PaymentGatewaysOverview, 
  GatewayDetails, 
  PaymentTransaction,
  WebhookEvent,
  TestConnectionResult
} from '../../services/paymentGatewaysApi';
import { AdminSettingsOverviewPage } from './AdminSettingsOverviewPage';

export const AdminSettingsPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const [settings, setSettings] = useState<AdminSettingsData | null>(null);
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [accounts, setAccounts] = useState<AdminAccount[]>([]);
  const [logs, setLogs] = useState<AdminLog[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState('overview');
  const [saving, setSaving] = useState(false);
  const [successMessage, setSuccessMessage] = useState('');
  const [systemSettings, setSystemSettings] = useState<Partial<SystemSettings>>({});
  
  // Services States
  const [services, setServices] = useState<Service[]>([]);
  const [selectedService, setSelectedService] = useState<Service | null>(null);
  const [showCreateServiceModal, setShowCreateServiceModal] = useState(false);
  const [servicesError, setServicesError] = useState<string | null>(null);
  const [servicesStats, setServicesStats] = useState({ total: 0, account_services: 0 });
  
  // Payment Gateway States
  const [paymentOverview, setPaymentOverview] = useState<PaymentGatewaysOverview | null>(null);
  const [selectedGateway, setSelectedGateway] = useState<'stripe' | 'paypal' | null>(null);
  const [gatewayDetails, setGatewayDetails] = useState<GatewayDetails | null>(null);
  const [testing, setTesting] = useState<'stripe' | 'paypal' | null>(null);
  const [testResults, setTestResults] = useState<Record<string, TestConnectionResult>>({});
  const [paymentActiveTab, setPaymentActiveTab] = useState<'overview' | 'transactions' | 'webhooks'>('overview');
  const [showConfigModal, setShowConfigModal] = useState(false);
  const [configGateway, setConfigGateway] = useState<'stripe' | 'paypal' | null>(null);
  const [configForm, setConfigForm] = useState<any>({});
  const [configLoading, setConfigLoading] = useState(false);
  const [configError, setConfigError] = useState<string | null>(null);

  // Check if user has admin access
  const hasAdminAccess = user?.role === 'owner' || user?.role === 'admin';

  useEffect(() => {
    if (hasAdminAccess) {
      loadAdminData();
    }
  }, [hasAdminAccess]);

  useEffect(() => {
    if (activeTab === 'services') {
      loadServices();
    } else if (activeTab === 'payments') {
      loadPaymentOverview();
    }
  }, [activeTab]);

  const loadAdminData = async () => {
    try {
      setLoading(true);
      const [settingsData, usersData, accountsData, logsData] = await Promise.all([
        adminApi.getAdminSettings(),
        adminApi.getUsers(),
        adminApi.getAccounts(),
        adminApi.getSystemLogs()
      ]);

      setSettings(settingsData);
      setUsers(usersData.users);
      setAccounts(accountsData.accounts);
      setLogs(logsData.logs);
      setSystemSettings(settingsData.system_settings);
    } catch (error) {
      console.error('Failed to load admin data:', error);
    } finally {
      setLoading(false);
    }
  };

  const showSuccess = (message: string) => {
    setSuccessMessage(message);
    setTimeout(() => setSuccessMessage(''), 3000);
  };

  const handleUpdateSettings = async (updatedSettings: Partial<SystemSettings>) => {
    try {
      setSaving(true);
      await adminApi.updateAdminSettings(updatedSettings);
      setSystemSettings({ ...systemSettings, ...updatedSettings });
      showSuccess('Admin settings updated successfully');
    } catch (error) {
      console.error('Failed to update settings:', error);
    } finally {
      setSaving(false);
    }
  };

  const handleSuspendAccount = async (accountId: string, reason: string) => {
    try {
      await adminApi.suspendAccount(accountId, reason);
      await loadAdminData(); // Reload data
      showSuccess('Account suspended successfully');
    } catch (error) {
      console.error('Failed to suspend account:', error);
    }
  };

  const handleActivateAccount = async (accountId: string, reason: string) => {
    try {
      await adminApi.activateAccount(accountId, reason);
      await loadAdminData(); // Reload data
      showSuccess('Account activated successfully');
    } catch (error) {
      console.error('Failed to activate account:', error);
    }
  };

  const loadServices = async () => {
    try {
      setServicesError(null);
      const response = await serviceAPI.getServices();
      setServices(response.services);
      setServicesStats({
        total: response.total,
        account_services: response.account_services
      });
    } catch (error: any) {
      setServicesError(error.response?.data?.error || 'Failed to load services');
    }
  };

  const handleServiceSelect = (service: Service) => {
    setSelectedService(service);
  };

  const handleServiceCreate = async (serviceData: any) => {
    try {
      await serviceAPI.createService(serviceData);
      await loadServices();
      setShowCreateServiceModal(false);
      showSuccess('Service created successfully');
    } catch (error: any) {
      throw new Error(error.response?.data?.error || 'Failed to create service');
    }
  };

  const handleServiceUpdate = async (serviceId: string, data: any) => {
    try {
      const response = await serviceAPI.updateService(serviceId, data);
      setServices(prev => prev.map(s => s.id === serviceId ? response.service : s));
      setSelectedService(prev => prev?.id === serviceId ? response.service : prev);
      showSuccess('Service updated successfully');
      return response;
    } catch (error: any) {
      throw new Error(error.response?.data?.error || 'Failed to update service');
    }
  };

  const handleServiceDelete = async (serviceId: string) => {
    try {
      await serviceAPI.deleteService(serviceId);
      setServices(prev => prev.filter(s => s.id !== serviceId));
      setSelectedService(prev => prev?.id === serviceId ? null : prev);
      showSuccess('Service deleted successfully');
    } catch (error: any) {
      throw new Error(error.response?.data?.error || 'Failed to delete service');
    }
  };

  const handleTokenRegenerate = async (serviceId: string) => {
    try {
      const response = await serviceAPI.regenerateToken(serviceId);
      setServices(prev => prev.map(s => s.id === serviceId ? response.service : s));
      setSelectedService(prev => prev?.id === serviceId ? response.service : prev);
      showSuccess('Token regenerated successfully');
      return response.new_token;
    } catch (error: any) {
      throw new Error(error.response?.data?.error || 'Failed to regenerate token');
    }
  };

  const handleServiceStatusChange = async (serviceId: string, action: 'suspend' | 'activate' | 'revoke') => {
    try {
      let response: { service: Service; message: string };
      switch (action) {
        case 'suspend':
          response = await serviceAPI.suspendService(serviceId);
          break;
        case 'activate':
          response = await serviceAPI.activateService(serviceId);
          break;
        case 'revoke':
          response = await serviceAPI.revokeService(serviceId);
          break;
        default:
          throw new Error(`Unknown action: ${action}`);
      }
      
      setServices(prev => prev.map(s => s.id === serviceId ? response.service : s));
      setSelectedService(prev => prev?.id === serviceId ? response.service : prev);
      showSuccess(`Service ${action}d successfully`);
      return response;
    } catch (error: any) {
      throw new Error(error.response?.data?.error || `Failed to ${action} service`);
    }
  };

  // Payment Gateway Functions
  const loadPaymentOverview = async () => {
    try {
      const paymentData = await paymentGatewaysApi.getOverview();
      setPaymentOverview(paymentData);
    } catch (error) {
      console.error('Error loading payment gateways overview:', error);
    }
  };

  const handleTestConnection = async (gateway: 'stripe' | 'paypal') => {
    try {
      setTesting(gateway);
      const result = await paymentGatewaysApi.testConnection(gateway);
      setTestResults(prev => ({ ...prev, [gateway]: result }));
      
      await loadPaymentOverview();
    } catch (error) {
      console.error(`Error testing ${gateway} connection:`, error);
    } finally {
      setTesting(null);
    }
  };

  const handleViewGatewayDetails = async (gateway: 'stripe' | 'paypal') => {
    try {
      setLoading(true);
      const details = await paymentGatewaysApi.getGatewayDetails(gateway);
      setGatewayDetails(details);
      setSelectedGateway(gateway);
      setPaymentActiveTab('overview');
    } catch (error) {
      console.error(`Error loading ${gateway} details:`, error);
    } finally {
      setLoading(false);
    }
  };

  const handleBackToGatewayOverview = () => {
    setSelectedGateway(null);
    setGatewayDetails(null);
  };

  const handleConfigureGateway = (gateway: 'stripe' | 'paypal') => {
    setConfigGateway(gateway);
    setConfigError(null);
    
    if (paymentOverview) {
      const config = gateway === 'stripe' ? paymentOverview.gateways.stripe : paymentOverview.gateways.paypal;
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
      
      await loadPaymentOverview();
      
      setShowConfigModal(false);
      setConfigGateway(null);
      setConfigForm({});
      showSuccess('Payment gateway configuration updated successfully');
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

  // StatusBadge Component
  const StatusBadge: React.FC<{ status: string; text?: string }> = ({ status, text }) => {
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

  if (!hasAdminAccess) {
    return (
      <div className="text-center py-12">
        <div className="text-theme-error text-lg font-medium">
          🚫 Access Denied
        </div>
        <p className="text-theme-secondary mt-2">
          You need administrator privileges to access this page.
        </p>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-theme-secondary">Loading admin settings...</div>
      </div>
    );
  }

  const tabs = [
    { id: 'overview', name: 'Overview', icon: '📊' },
    { id: 'system', name: 'System Settings', icon: '⚙️' },
    { id: 'users', name: 'User Management', icon: '👥' },
    { id: 'accounts', name: 'Account Management', icon: '🏢' },
    { id: 'security', name: 'Security', icon: '🔒' },
    { id: 'services', name: 'Services', icon: '🤖' },
    { id: 'payments', name: 'Payment Gateways', icon: '💳' },
    { id: 'notifications', name: 'Notifications', icon: '🔔' },
    { id: 'maintenance', name: 'Maintenance', icon: '🔧' },
    { id: 'logs', name: 'System Logs', icon: '📋' }
  ];

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-2xl font-bold text-theme-primary">Admin Settings</h1>
          <p className="text-theme-secondary">
            System administration and platform management.
          </p>
        </div>
        <div className="bg-theme-error text-theme-error px-3 py-1 rounded-full text-sm font-medium">
          🔧 Admin Mode
        </div>
      </div>

      {successMessage && (
        <div className="alert-theme alert-theme-success">
          {successMessage}
        </div>
      )}

      {/* Tab Navigation */}
      <div className="border-b border-theme">
        <nav className="-mb-px flex space-x-8">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`py-2 px-1 border-b-2 font-medium text-sm ${
                activeTab === tab.id
                  ? 'border-theme-focus text-theme-link'
                  : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme'
              }`}
            >
              <span className="mr-2">{tab.icon}</span>
              {tab.name}
            </button>
          ))}
        </nav>
      </div>

      {/* Overview Tab */}
      {activeTab === 'overview' && (
        <AdminSettingsOverviewPage />
      )}

      {/* System Settings Tab */}
      {activeTab === 'system' && (
        <div className="space-y-6">
          {/* Platform Configuration */}
          <div className="card-theme">
            <div className="px-6 py-4 border-b border-theme">
              <h3 className="text-lg font-semibold text-theme-primary flex items-center">
                <span className="mr-2">🏗️</span>
                Platform Configuration
              </h3>
              <p className="text-sm text-theme-secondary mt-1">Core platform settings and features</p>
            </div>
            <div className="p-6 space-y-6">
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <div>
                  <label className="label-theme">Platform Name</label>
                  <input
                    type="text"
                    value={systemSettings.system_name || 'Powernode Platform'}
                    onChange={(e) => handleUpdateSettings({ system_name: e.target.value })}
                    disabled={saving}
                    className="input-theme"
                    placeholder="Your Platform Name"
                  />
                  <p className="text-xs text-theme-tertiary mt-1">Displayed in emails and interface</p>
                </div>
                
                <div>
                  <label className="label-theme">System Email</label>
                  <input
                    type="email"
                    value={systemSettings.system_email || ''}
                    onChange={(e) => handleUpdateSettings({ system_email: e.target.value })}
                    disabled={saving}
                    className="input-theme"
                    placeholder="system@yourplatform.com"
                  />
                  <p className="text-xs text-theme-tertiary mt-1">Default sender for system emails</p>
                </div>

                <div>
                  <label className="label-theme">Support Email</label>
                  <input
                    type="email"
                    value={systemSettings.support_email || ''}
                    onChange={(e) => handleUpdateSettings({ support_email: e.target.value })}
                    disabled={saving}
                    className="input-theme"
                    placeholder="support@yourplatform.com"
                  />
                  <p className="text-xs text-theme-tertiary mt-1">Contact email for user support</p>
                </div>

                <div>
                  <label className="label-theme">Platform URL</label>
                  <input
                    type="url"
                    value={systemSettings.platform_url || ''}
                    onChange={(e) => handleUpdateSettings({ platform_url: e.target.value })}
                    disabled={saving}
                    className="input-theme"
                    placeholder="https://yourplatform.com"
                  />
                  <p className="text-xs text-theme-tertiary mt-1">Base URL for links in emails</p>
                </div>
              </div>
            </div>
          </div>

          {/* User Registration & Access */}
          <div className="card-theme">
            <div className="px-6 py-4 border-b border-theme">
              <h3 className="text-lg font-semibold text-theme-primary flex items-center">
                <span className="mr-2">👥</span>
                User Registration & Access
              </h3>
              <p className="text-sm text-theme-secondary mt-1">Control how users can register and access the platform</p>
            </div>
            <div className="p-6 space-y-6">
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <div className="flex items-center justify-between p-4 rounded-lg border border-theme bg-theme-background-secondary">
                  <div>
                    <h4 className="text-sm font-medium text-theme-primary">User Registration</h4>
                    <p className="text-sm text-theme-secondary">Allow new users to create accounts</p>
                  </div>
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input
                      type="checkbox"
                      className="sr-only peer"
                      checked={systemSettings.registration_enabled || false}
                      onChange={(e) => handleUpdateSettings({ registration_enabled: e.target.checked })}
                      disabled={saving}
                    />
                    <div className="toggle-theme peer-checked:bg-theme-success"></div>
                  </label>
                </div>

                <div className="flex items-center justify-between p-4 rounded-lg border border-theme bg-theme-background-secondary">
                  <div>
                    <h4 className="text-sm font-medium text-theme-primary">Email Verification</h4>
                    <p className="text-sm text-theme-secondary">Require email verification for new users</p>
                  </div>
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input
                      type="checkbox"
                      className="sr-only peer"
                      checked={systemSettings.email_verification_required || false}
                      onChange={(e) => handleUpdateSettings({ email_verification_required: e.target.checked })}
                      disabled={saving}
                    />
                    <div className="toggle-theme peer-checked:bg-theme-success"></div>
                  </label>
                </div>

                <div className="flex items-center justify-between p-4 rounded-lg border border-theme bg-theme-background-secondary">
                  <div>
                    <h4 className="text-sm font-medium text-theme-primary">Account Deletion</h4>
                    <p className="text-sm text-theme-secondary">Allow users to delete their accounts</p>
                  </div>
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input
                      type="checkbox"
                      className="sr-only peer"
                      checked={systemSettings.allow_account_deletion || false}
                      onChange={(e) => handleUpdateSettings({ allow_account_deletion: e.target.checked })}
                      disabled={saving}
                    />
                    <div className="toggle-theme peer-checked:bg-theme-warning"></div>
                  </label>
                </div>

                <div className="flex items-center justify-between p-4 rounded-lg border border-theme bg-theme-background-secondary">
                  <div>
                    <h4 className="text-sm font-medium text-theme-primary">Maintenance Mode</h4>
                    <p className="text-sm text-theme-secondary">Prevent user access during updates</p>
                  </div>
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input
                      type="checkbox"
                      className="sr-only peer"
                      checked={systemSettings.maintenance_mode || false}
                      onChange={(e) => handleUpdateSettings({ maintenance_mode: e.target.checked })}
                      disabled={saving}
                    />
                    <div className="toggle-theme peer-checked:bg-theme-error"></div>
                  </label>
                </div>
              </div>
            </div>
          </div>

          {/* Security Settings */}
          <div className="card-theme">
            <div className="px-6 py-4 border-b border-theme">
              <h3 className="text-lg font-semibold text-theme-primary flex items-center">
                <span className="mr-2">🔐</span>
                Security Settings
              </h3>
              <p className="text-sm text-theme-secondary mt-1">Password policies and session management</p>
            </div>
            <div className="p-6 space-y-6">
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <div>
                  <label className="label-theme">Password Complexity Level</label>
                  <select
                    value={systemSettings.password_complexity_level || 'high'}
                    onChange={(e) => handleUpdateSettings({ password_complexity_level: e.target.value as any })}
                    disabled={saving}
                    className="select-theme"
                  >
                    <option value="low">Low - 8+ characters</option>
                    <option value="medium">Medium - 10+ chars, mixed case</option>
                    <option value="high">High - 12+ chars, mixed case, numbers, symbols</option>
                  </select>
                </div>

                <div>
                  <label className="label-theme">Session Timeout (minutes)</label>
                  <input
                    type="number"
                    min="5"
                    max="480"
                    value={systemSettings.session_timeout_minutes || 60}
                    onChange={(e) => handleUpdateSettings({ session_timeout_minutes: parseInt(e.target.value) })}
                    disabled={saving}
                    className="input-theme"
                  />
                  <p className="text-xs text-theme-tertiary mt-1">Auto-logout after inactivity</p>
                </div>

                <div>
                  <label className="label-theme">Max Failed Login Attempts</label>
                  <input
                    type="number"
                    min="3"
                    max="10"
                    value={systemSettings.max_failed_login_attempts || 5}
                    onChange={(e) => handleUpdateSettings({ max_failed_login_attempts: parseInt(e.target.value) })}
                    disabled={saving}
                    className="input-theme"
                  />
                  <p className="text-xs text-theme-tertiary mt-1">Lock account after failed attempts</p>
                </div>

                <div>
                  <label className="label-theme">Account Lockout Duration (minutes)</label>
                  <input
                    type="number"
                    min="5"
                    max="1440"
                    value={systemSettings.account_lockout_duration || 30}
                    onChange={(e) => handleUpdateSettings({ account_lockout_duration: parseInt(e.target.value) })}
                    disabled={saving}
                    className="input-theme"
                  />
                  <p className="text-xs text-theme-tertiary mt-1">How long accounts stay locked</p>
                </div>
              </div>
            </div>
          </div>

          {/* Business Settings */}
          <div className="card-theme">
            <div className="px-6 py-4 border-b border-theme">
              <h3 className="text-lg font-semibold text-theme-primary flex items-center">
                <span className="mr-2">💼</span>
                Business Settings
              </h3>
              <p className="text-sm text-theme-secondary mt-1">Trial periods, billing, and subscription settings</p>
            </div>
            <div className="p-6 space-y-6">
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <div>
                  <label className="label-theme">Default Trial Period (days)</label>
                  <input
                    type="number"
                    min="0"
                    max="365"
                    value={systemSettings.trial_period_days || 14}
                    onChange={(e) => handleUpdateSettings({ trial_period_days: parseInt(e.target.value) })}
                    disabled={saving}
                    className="input-theme"
                  />
                  <p className="text-xs text-theme-tertiary mt-1">Default trial length for new accounts</p>
                </div>

                <div>
                  <label className="label-theme">Payment Retry Attempts</label>
                  <input
                    type="number"
                    min="1"
                    max="5"
                    value={systemSettings.payment_retry_attempts || 3}
                    onChange={(e) => handleUpdateSettings({ payment_retry_attempts: parseInt(e.target.value) })}
                    disabled={saving}
                    className="input-theme"
                  />
                  <p className="text-xs text-theme-tertiary mt-1">Retry failed payments automatically</p>
                </div>

                <div>
                  <label className="label-theme">Webhook Timeout (seconds)</label>
                  <input
                    type="number"
                    min="5"
                    max="60"
                    value={systemSettings.webhook_timeout_seconds || 30}
                    onChange={(e) => handleUpdateSettings({ webhook_timeout_seconds: parseInt(e.target.value) })}
                    disabled={saving}
                    className="input-theme"
                  />
                  <p className="text-xs text-theme-tertiary mt-1">Timeout for payment webhook processing</p>
                </div>

                <div>
                  <label className="label-theme">Rate Limit (requests/minute)</label>
                  <input
                    type="number"
                    min="10"
                    max="1000"
                    value={systemSettings.rate_limit_requests_per_minute || 60}
                    onChange={(e) => handleUpdateSettings({ rate_limit_requests_per_minute: parseInt(e.target.value) })}
                    disabled={saving}
                    className="input-theme"
                  />
                  <p className="text-xs text-theme-tertiary mt-1">API rate limiting per user</p>
                </div>
              </div>
            </div>
          </div>

          {/* Save Button */}
          <div className="flex justify-end">
            <button
              onClick={() => handleUpdateSettings(systemSettings)}
              disabled={saving}
              className="btn-theme btn-theme-primary px-6 py-2"
            >
              {saving ? 'Saving...' : 'Save All Settings'}
            </button>
          </div>
        </div>
      )}

      {/* Users Tab */}
      {activeTab === 'users' && (
        <div className="space-y-6">
          {/* User Stats */}
          <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
            <div className="card-theme p-4">
              <div className="flex items-center">
                <div className="text-2xl mr-3">👥</div>
                <div>
                  <p className="text-sm text-theme-secondary">Total Users</p>
                  <p className="text-xl font-semibold text-theme-primary">{users.length}</p>
                </div>
              </div>
            </div>
            <div className="card-theme p-4">
              <div className="flex items-center">
                <div className="text-2xl mr-3">✅</div>
                <div>
                  <p className="text-sm text-theme-secondary">Active Users</p>
                  <p className="text-xl font-semibold text-theme-success">
                    {users.filter(u => u.status === 'active').length}
                  </p>
                </div>
              </div>
            </div>
            <div className="card-theme p-4">
              <div className="flex items-center">
                <div className="text-2xl mr-3">⚠️</div>
                <div>
                  <p className="text-sm text-theme-secondary">Suspended</p>
                  <p className="text-xl font-semibold text-theme-error">
                    {users.filter(u => u.status === 'suspended').length}
                  </p>
                </div>
              </div>
            </div>
            <div className="card-theme p-4">
              <div className="flex items-center">
                <div className="text-2xl mr-3">📧</div>
                <div>
                  <p className="text-sm text-theme-secondary">Unverified</p>
                  <p className="text-xl font-semibold text-theme-warning">
                    {users.filter(u => !u.email_verified).length}
                  </p>
                </div>
              </div>
            </div>
          </div>

          {/* User Management */}
          <div className="card-theme">
            <div className="px-6 py-4 border-b border-theme">
              <div className="flex items-center justify-between">
                <div>
                  <h3 className="text-lg font-semibold text-theme-primary flex items-center">
                    <span className="mr-2">👥</span>
                    User Management
                  </h3>
                  <p className="text-sm text-theme-secondary mt-1">Manage all platform users</p>
                </div>
                <div className="flex items-center gap-3">
                  <div className="relative">
                    <input
                      type="text"
                      placeholder="Search users..."
                      className="input-theme pl-10 pr-4 py-2 w-64"
                    />
                    <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                      <span className="text-theme-tertiary">🔍</span>
                    </div>
                  </div>
                  <select className="select-theme">
                    <option value="all">All Statuses</option>
                    <option value="active">Active</option>
                    <option value="suspended">Suspended</option>
                    <option value="inactive">Inactive</option>
                  </select>
                  <select className="select-theme">
                    <option value="all">All Roles</option>
                    <option value="owner">Owners</option>
                    <option value="admin">Admins</option>
                    <option value="user">Users</option>
                  </select>
                </div>
              </div>
            </div>
            
            <div className="overflow-x-auto">
              <table className="min-w-full divide-y divide-theme">
                <thead className="bg-theme-background-secondary">
                  <tr>
                    <th className="px-6 py-3 text-left">
                      <input type="checkbox" className="checkbox-theme" />
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                      User
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                      Account
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                      Role
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                      Status
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                      Last Login
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                      Actions
                    </th>
                  </tr>
                </thead>
                <tbody className="card-theme divide-y divide-theme">
                  {users.slice(0, 20).map((user) => (
                    <tr key={user.id} className="hover:bg-theme-surface-hover">
                      <td className="px-6 py-4">
                        <input type="checkbox" className="checkbox-theme" />
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <div className="flex items-center">
                          <div className="h-10 w-10 rounded-full bg-theme-info flex items-center justify-center mr-4">
                            <span className="text-sm font-medium text-theme-info">
                              {user.full_name.split(' ').map(n => n[0]).join('').toUpperCase()}
                            </span>
                          </div>
                          <div>
                            <div className="text-sm font-medium text-theme-primary">{user.full_name}</div>
                            <div className="text-sm text-theme-secondary">{user.email}</div>
                            <div className="flex items-center gap-2 mt-1">
                              {user.email_verified ? (
                                <span className="text-xs text-theme-success">✅ Verified</span>
                              ) : (
                                <span className="text-xs text-theme-warning">⚠️ Unverified</span>
                              )}
                              {user.locked && (
                                <span className="text-xs text-theme-error">🔒 Locked</span>
                              )}
                            </div>
                          </div>
                        </div>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <div>
                          <div className="text-sm text-theme-primary">{user.account.name}</div>
                          <div className="text-xs text-theme-secondary">{user.account.status}</div>
                        </div>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <div className="flex flex-wrap gap-1">
                          {user.roles.map(role => (
                            <span key={role} className="inline-flex px-2 py-1 text-xs font-semibold rounded-full bg-theme-info text-theme-info">
                              {role}
                            </span>
                          ))}
                        </div>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${
                          user.status === 'active' ? 'bg-theme-success text-theme-success' :
                          user.status === 'suspended' ? 'bg-theme-error text-theme-error' :
                          'bg-theme-background-tertiary text-theme-secondary'
                        }`}>
                          {user.status}
                        </span>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-secondary">
                        {user.last_login_at ? (
                          <div>
                            <div>{new Date(user.last_login_at).toLocaleDateString()}</div>
                            <div className="text-xs">{new Date(user.last_login_at).toLocaleTimeString()}</div>
                          </div>
                        ) : (
                          'Never'
                        )}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm font-medium">
                        <div className="flex items-center gap-2">
                          <button className="text-theme-link hover:text-theme-link-hover">
                            View
                          </button>
                          <button className="text-theme-warning hover:text-theme-warning-hover">
                            Edit
                          </button>
                          {user.status === 'active' ? (
                            <button className="text-theme-error hover:text-theme-error-hover">
                              Suspend
                            </button>
                          ) : (
                            <button className="text-theme-success hover:text-theme-success-hover">
                              Activate
                            </button>
                          )}
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {/* Pagination */}
            <div className="px-6 py-4 border-t border-theme">
              <div className="flex items-center justify-between">
                <div className="text-sm text-theme-secondary">
                  Showing 1 to {Math.min(20, users.length)} of {users.length} users
                </div>
                <div className="flex items-center gap-2">
                  <button className="btn-theme btn-theme-secondary px-3 py-1 text-sm">
                    Previous
                  </button>
                  <span className="px-3 py-1 text-sm text-theme-primary">1</span>
                  <button className="btn-theme btn-theme-secondary px-3 py-1 text-sm">
                    Next
                  </button>
                </div>
              </div>
            </div>
          </div>

          {/* Bulk Actions */}
          <div className="card-theme p-4">
            <h4 className="text-sm font-medium text-theme-primary mb-3">Bulk Actions</h4>
            <div className="flex items-center gap-3">
              <select className="select-theme">
                <option value="">Select Action</option>
                <option value="suspend">Suspend Selected</option>
                <option value="activate">Activate Selected</option>
                <option value="verify">Verify Email</option>
                <option value="export">Export Data</option>
              </select>
              <button className="btn-theme btn-theme-secondary px-4 py-2">
                Apply to Selected
              </button>
              <div className="text-sm text-theme-secondary">
                0 users selected
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Accounts Tab */}
      {activeTab === 'accounts' && (
        <div className="card-theme">
          <div className="px-6 py-4 border-b border-theme">
            <h3 className="text-lg font-medium text-theme-primary">Account Management</h3>
            <p className="text-sm text-theme-secondary mt-1">{accounts.length} total accounts</p>
          </div>
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-theme">
              <thead className="bg-theme-background-secondary">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Account
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Users
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Plan
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Status
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody className="card-theme divide-y divide-theme">
                {accounts.slice(0, 10).map((account) => (
                  <tr key={account.id}>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div>
                        <div className="text-sm font-medium text-theme-primary">{account.name}</div>
                        <div className="text-sm text-theme-secondary">{account.subdomain || 'No subdomain'}</div>
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-primary">
                      {account.users_count}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-primary">
                      {account.subscription?.plan_name || 'No subscription'}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${
                        account.status === 'active' ? 'bg-theme-success text-theme-success' :
                        account.status === 'suspended' ? 'bg-theme-error text-theme-error' :
                        'bg-theme-background-tertiary text-theme-secondary'
                      }`}>
                        {account.status}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium space-x-2">
                      {account.status === 'active' ? (
                        <button
                          onClick={() => handleSuspendAccount(account.id, 'Admin action')}
                          className="text-theme-error hover:text-theme-error-hover"
                        >
                          Suspend
                        </button>
                      ) : (
                        <button
                          onClick={() => handleActivateAccount(account.id, 'Admin action')}
                          className="text-theme-success hover:text-theme-success-hover"
                        >
                          Activate
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Security Tab */}
      {activeTab === 'security' && (
        <div className="space-y-6">
          {/* Security Overview */}
          <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
            <div className="card-theme p-4">
              <div className="flex items-center">
                <div className="text-2xl mr-3">🔐</div>
                <div>
                  <p className="text-sm text-theme-secondary">Failed Logins</p>
                  <p className="text-xl font-semibold text-theme-error">
                    {settings?.security_settings?.failed_login_attempts_today || 0}
                  </p>
                </div>
              </div>
            </div>
            <div className="card-theme p-4">
              <div className="flex items-center">
                <div className="text-2xl mr-3">🔒</div>
                <div>
                  <p className="text-sm text-theme-secondary">Locked Accounts</p>
                  <p className="text-xl font-semibold text-theme-warning">
                    {settings?.security_settings?.locked_accounts || 0}
                  </p>
                </div>
              </div>
            </div>
            <div className="card-theme p-4">
              <div className="flex items-center">
                <div className="text-2xl mr-3">⚠️</div>
                <div>
                  <p className="text-sm text-theme-secondary">Security Events</p>
                  <p className="text-xl font-semibold text-theme-info">
                    {settings?.security_settings?.recent_security_events || 0}
                  </p>
                </div>
              </div>
            </div>
            <div className="card-theme p-4">
              <div className="flex items-center">
                <div className="text-2xl mr-3">🛡️</div>
                <div>
                  <p className="text-sm text-theme-secondary">Security Level</p>
                  <p className="text-xl font-semibold text-theme-success">High</p>
                </div>
              </div>
            </div>
          </div>

          {/* Security Alerts */}
          <div className="card-theme">
            <div className="px-6 py-4 border-b border-theme">
              <h3 className="text-lg font-semibold text-theme-primary flex items-center">
                <span className="mr-2">🚨</span>
                Security Alerts
              </h3>
              <p className="text-sm text-theme-secondary mt-1">Recent security events and alerts</p>
            </div>
            <div className="p-6">
              <div className="space-y-4">
                <div className="flex items-start gap-4 p-4 rounded-lg bg-theme-background-secondary">
                  <div className="text-2xl">🟢</div>
                  <div className="flex-1">
                    <h4 className="font-medium text-theme-primary">System Security: Normal</h4>
                    <p className="text-sm text-theme-secondary mt-1">No critical security events detected in the last 24 hours</p>
                    <p className="text-xs text-theme-tertiary mt-2">Last checked: {new Date().toLocaleString()}</p>
                  </div>
                </div>
                
                <div className="flex items-start gap-4 p-4 rounded-lg border border-theme-warning bg-theme-warning">
                  <div className="text-2xl">🟡</div>
                  <div className="flex-1">
                    <h4 className="font-medium text-theme-primary">Rate Limiting Active</h4>
                    <p className="text-sm text-theme-secondary mt-1">3 IP addresses currently rate-limited due to excessive requests</p>
                    <p className="text-xs text-theme-tertiary mt-2">Auto-resolved in 15 minutes</p>
                  </div>
                </div>
              </div>
            </div>
          </div>

          {/* IP Blocking */}
          <div className="card-theme">
            <div className="px-6 py-4 border-b border-theme">
              <h3 className="text-lg font-semibold text-theme-primary flex items-center">
                <span className="mr-2">🚫</span>
                IP Blocking & Monitoring
              </h3>
              <p className="text-sm text-theme-secondary mt-1">Monitor and block suspicious IP addresses</p>
            </div>
            <div className="p-6 space-y-4">
              <div className="flex items-center justify-between">
                <div>
                  <h4 className="font-medium text-theme-primary">Auto IP Blocking</h4>
                  <p className="text-sm text-theme-secondary">Automatically block IPs with suspicious activity</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input type="checkbox" className="sr-only peer" checked disabled={saving} />
                  <div className="toggle-theme peer-checked:bg-theme-success"></div>
                </label>
              </div>
              
              <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-theme">
                  <thead className="bg-theme-background-secondary">
                    <tr>
                      <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                        IP Address
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                        Reason
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                        Blocked At
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                        Actions
                      </th>
                    </tr>
                  </thead>
                  <tbody className="card-theme divide-y divide-theme">
                    <tr>
                      <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-theme-primary">
                        192.168.1.100
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-secondary">
                        Excessive login attempts
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-secondary">
                        2 hours ago
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm font-medium">
                        <button className="text-theme-link hover:text-theme-link-hover mr-3">Unblock</button>
                        <button className="text-theme-error hover:text-theme-error-hover">Permanent Block</button>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Services Tab */}
      {activeTab === 'services' && (
        <div className="space-y-6">
          <div className="card-theme">
            <div className="px-6 py-4 border-b border-theme">
              <div className="flex items-center justify-between">
                <div>
                  <h3 className="text-lg font-semibold text-theme-primary flex items-center">
                    <span className="mr-2">🤖</span>
                    Services Management
                  </h3>
                  <p className="text-sm text-theme-secondary mt-1">
                    Manage authentication services for background jobs and integrations
                  </p>
                </div>
                <button
                  onClick={() => setShowCreateServiceModal(true)}
                  className="btn-theme btn-theme-primary"
                >
                  Create Service
                </button>
              </div>
              
              {/* Stats */}
              <div className="flex gap-6 mt-4">
                <div className="text-sm">
                  <span className="text-theme-secondary">Total Services:</span>
                  <span className="ml-2 font-semibold text-theme-primary">{servicesStats.total}</span>
                </div>
                <div className="text-sm">
                  <span className="text-theme-secondary">Account Services:</span>
                  <span className="ml-2 font-semibold text-theme-link">{servicesStats.account_services}</span>
                </div>
              </div>
            </div>

            {/* Error Display */}
            {servicesError && (
              <div className="mx-6 mt-4 p-4 bg-theme-error rounded-md border border-theme">
                <p className="text-theme-error text-sm">{servicesError}</p>
                <button
                  onClick={loadServices}
                  className="mt-2 text-theme-error hover:text-theme-error text-sm underline opacity-80 hover:opacity-100 transition-opacity duration-150"
                >
                  Try again
                </button>
              </div>
            )}

            {/* Main Content */}
            <div className="flex">
              {/* Services List */}
              <div className="w-1/3 border-r border-theme">
                <ServiceList
                  services={services}
                  selectedService={selectedService}
                  onServiceSelect={handleServiceSelect}
                  onServiceUpdate={handleServiceUpdate}
                  onServiceDelete={handleServiceDelete}
                  onTokenRegenerate={handleTokenRegenerate}
                  onStatusChange={handleServiceStatusChange}
                />
              </div>

              {/* Service Details */}
              <div className="flex-1">
                {selectedService ? (
                  <ServiceDetails
                    service={selectedService}
                    onServiceUpdate={handleServiceUpdate}
                    onTokenRegenerate={handleTokenRegenerate}
                    onStatusChange={handleServiceStatusChange}
                  />
                ) : (
                  <div className="flex items-center justify-center h-96 text-theme-secondary">
                    <div className="text-center">
                      <div className="text-4xl mb-4">🤖</div>
                      <p className="text-lg font-medium">Select a service to view details</p>
                      <p className="text-sm mt-2">Choose a service from the list to see its configuration and activity</p>
                    </div>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Payment Gateways Tab */}
      {activeTab === 'payments' && (
        <div className="space-y-6">
          {selectedGateway && gatewayDetails ? (
            <div className="space-y-6">
              <div className="flex items-center justify-between">
                <div className="flex items-center space-x-4">
                  <button
                    onClick={handleBackToGatewayOverview}
                    className="btn-theme btn-theme-secondary btn-theme-sm"
                  >
                    ← Back
                  </button>
                  <h3 className="text-xl font-semibold text-theme-primary">
                    {gatewayDetails.configuration.name} Gateway
                  </h3>
                  <StatusBadge status={gatewayDetails.status.status} />
                </div>
              </div>

              <div className="border-b border-theme">
                <nav className="-mb-px flex space-x-8">
                  {(['overview', 'transactions', 'webhooks'] as const).map((tab) => (
                    <button
                      key={tab}
                      onClick={() => setPaymentActiveTab(tab)}
                      className={`py-2 px-1 border-b-2 font-medium text-sm ${
                        paymentActiveTab === tab
                          ? 'border-theme-focus text-theme-link'
                          : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme'
                      }`}
                    >
                      {tab.charAt(0).toUpperCase() + tab.slice(1)}
                    </button>
                  ))}
                </nav>
              </div>

              <div className="space-y-6">
                {paymentActiveTab === 'overview' && (
                  <>
                    <div className="card-theme p-6">
                      <h4 className="text-lg font-semibold text-theme-primary mb-4">Configuration</h4>
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

                    <div className="card-theme p-6">
                      <h4 className="text-lg font-semibold text-theme-primary mb-4">Statistics</h4>
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

                {paymentActiveTab === 'transactions' && (
                  <div className="card-theme p-6">
                    <h4 className="text-lg font-semibold text-theme-primary mb-4">Recent Transactions</h4>
                    <div className="overflow-x-auto">
                      <table className="min-w-full divide-y divide-theme">
                        <thead className="bg-theme-background-secondary">
                          <tr>
                            <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">Transaction</th>
                            <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">Amount</th>
                            <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">Method</th>
                            <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">Status</th>
                            <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">Date</th>
                          </tr>
                        </thead>
                        <tbody className="bg-theme-surface divide-y divide-theme">
                          {gatewayDetails.transactions.map((transaction) => (
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
                  </div>
                )}

                {paymentActiveTab === 'webhooks' && (
                  <div className="card-theme p-6">
                    <h4 className="text-lg font-semibold text-theme-primary mb-4">Recent Webhook Events</h4>
                    <div className="overflow-x-auto">
                      <table className="min-w-full divide-y divide-theme">
                        <thead className="bg-theme-background-secondary">
                          <tr>
                            <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">Event</th>
                            <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">Status</th>
                            <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">Processed</th>
                            <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">Created</th>
                          </tr>
                        </thead>
                        <tbody className="bg-theme-surface divide-y divide-theme">
                          {gatewayDetails.webhooks.map((webhook) => (
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
                  </div>
                )}
              </div>
            </div>
          ) : (
            <>
              {paymentOverview && (
                <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                  <div className="card-theme p-6">
                    <h4 className="text-lg font-semibold text-theme-primary mb-2">Total Transactions</h4>
                    <div className="text-3xl font-bold text-theme-interactive-primary">
                      {paymentOverview.statistics.overall.total_transactions.toLocaleString()}
                    </div>
                    <div className="text-sm text-theme-secondary">
                      {paymentOverview.statistics.overall.successful_transactions} successful
                    </div>
                  </div>
                  <div className="card-theme p-6">
                    <h4 className="text-lg font-semibold text-theme-primary mb-2">Success Rate</h4>
                    <div className="text-3xl font-bold text-theme-success">
                      {paymentGatewaysApi.formatSuccessRate(paymentOverview.statistics.overall.success_rate)}
                    </div>
                    <div className="text-sm text-theme-secondary">Overall performance</div>
                  </div>
                  <div className="card-theme p-6">
                    <h4 className="text-lg font-semibold text-theme-primary mb-2">Total Volume</h4>
                    <div className="text-3xl font-bold text-theme-link">
                      {paymentGatewaysApi.formatCurrency(paymentOverview.statistics.overall.total_volume)}
                    </div>
                    <div className="text-sm text-theme-secondary">All-time processed</div>
                  </div>
                </div>
              )}

              {paymentOverview && (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div className="card-theme p-6">
                    <div className="flex items-center justify-between mb-4">
                      <div className="flex items-center space-x-3">
                        <div className="w-12 h-12 bg-theme-background-secondary rounded-lg flex items-center justify-center">
                          <span className="text-lg font-semibold text-theme-secondary">S</span>
                        </div>
                        <div>
                          <h4 className="text-lg font-semibold text-theme-primary">{paymentOverview.gateways.stripe.name}</h4>
                          <div className="flex items-center space-x-2">
                            <StatusBadge status={paymentOverview.status.stripe.status} />
                            {paymentOverview.gateways.stripe.test_mode && (
                              <span className="px-2 py-1 text-xs bg-theme-info text-theme-info rounded-full">
                                Test Mode
                              </span>
                            )}
                          </div>
                        </div>
                      </div>
                      <div className="flex space-x-2">
                        <button
                          onClick={() => handleConfigureGateway('stripe')}
                          className="btn-theme btn-theme-success text-white"
                        >
                          Configure
                        </button>
                        <button
                          onClick={() => handleTestConnection('stripe')}
                          disabled={testing === 'stripe' || paymentOverview.status.stripe.status === 'not_configured'}
                          className="btn-theme btn-theme-primary"
                        >
                          {testing === 'stripe' ? 'Testing...' : 'Test'}
                        </button>
                        <button
                          onClick={() => handleViewGatewayDetails('stripe')}
                          className="btn-theme btn-theme-secondary btn-theme-sm"
                        >
                          Details
                        </button>
                      </div>
                    </div>

                    <div className="space-y-3 text-sm">
                      <div className="flex justify-between">
                        <span className="text-theme-secondary">Status:</span>
                        <span className="text-theme-primary">{paymentOverview.status.stripe.message}</span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-theme-secondary">Total Transactions:</span>
                        <span className="text-theme-primary">{paymentOverview.statistics.stripe.total_transactions.toLocaleString()}</span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-theme-secondary">Success Rate:</span>
                        <span className="text-theme-primary">{paymentGatewaysApi.formatSuccessRate(paymentOverview.statistics.stripe.success_rate)}</span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-theme-secondary">30-Day Volume:</span>
                        <span className="text-theme-primary">
                          {paymentGatewaysApi.formatCurrency(paymentOverview.statistics.stripe.last_30_days.volume)}
                        </span>
                      </div>
                    </div>
                  </div>

                  <div className="card-theme p-6">
                    <div className="flex items-center justify-between mb-4">
                      <div className="flex items-center space-x-3">
                        <div className="w-12 h-12 bg-theme-background-secondary rounded-lg flex items-center justify-center">
                          <span className="text-lg font-semibold text-theme-secondary">P</span>
                        </div>
                        <div>
                          <h4 className="text-lg font-semibold text-theme-primary">{paymentOverview.gateways.paypal.name}</h4>
                          <div className="flex items-center space-x-2">
                            <StatusBadge status={paymentOverview.status.paypal.status} />
                            {paymentOverview.gateways.paypal.test_mode && (
                              <span className="px-2 py-1 text-xs bg-theme-info text-theme-info rounded-full">
                                Test Mode
                              </span>
                            )}
                          </div>
                        </div>
                      </div>
                      <div className="flex space-x-2">
                        <button
                          onClick={() => handleConfigureGateway('paypal')}
                          className="btn-theme btn-theme-success text-white"
                        >
                          Configure
                        </button>
                        <button
                          onClick={() => handleTestConnection('paypal')}
                          disabled={testing === 'paypal' || paymentOverview.status.paypal.status === 'not_configured'}
                          className="btn-theme btn-theme-primary"
                        >
                          {testing === 'paypal' ? 'Testing...' : 'Test'}
                        </button>
                        <button
                          onClick={() => handleViewGatewayDetails('paypal')}
                          className="btn-theme btn-theme-secondary btn-theme-sm"
                        >
                          Details
                        </button>
                      </div>
                    </div>

                    <div className="space-y-3 text-sm">
                      <div className="flex justify-between">
                        <span className="text-theme-secondary">Status:</span>
                        <span className="text-theme-primary">{paymentOverview.status.paypal.message}</span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-theme-secondary">Total Transactions:</span>
                        <span className="text-theme-primary">{paymentOverview.statistics.paypal.total_transactions.toLocaleString()}</span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-theme-secondary">Success Rate:</span>
                        <span className="text-theme-primary">{paymentGatewaysApi.formatSuccessRate(paymentOverview.statistics.paypal.success_rate)}</span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-theme-secondary">30-Day Volume:</span>
                        <span className="text-theme-primary">
                          {paymentGatewaysApi.formatCurrency(paymentOverview.statistics.paypal.last_30_days.volume)}
                        </span>
                      </div>
                    </div>
                  </div>
                </div>
              )}

              {Object.keys(testResults).length > 0 && (
                <div className="space-y-4">
                  <h4 className="text-lg font-semibold text-theme-primary">Connection Test Results</h4>
                  {Object.entries(testResults).map(([gateway, result]) => (
                    <div key={gateway} className="card-theme p-6">
                      <div className="flex items-center justify-between mb-3">
                        <h5 className="font-medium text-theme-primary capitalize">{gateway} Test Result</h5>
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

              {paymentOverview && paymentOverview.recent_transactions.length > 0 && (
                <div className="card-theme p-6">
                  <h4 className="text-lg font-semibold text-theme-primary mb-4">Recent Transactions</h4>
                  <div className="overflow-x-auto">
                    <table className="min-w-full divide-y divide-theme">
                      <thead className="bg-theme-background-secondary">
                        <tr>
                          <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">Transaction</th>
                          <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">Amount</th>
                          <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">Method</th>
                          <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">Status</th>
                          <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">Date</th>
                        </tr>
                      </thead>
                      <tbody className="bg-theme-surface divide-y divide-theme">
                        {paymentOverview.recent_transactions.map((transaction) => (
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
                </div>
              )}
            </>
          )}
        </div>
      )}

      {/* Notifications Tab */}
      {activeTab === 'notifications' && (
        <div className="space-y-6">
          <div className="card-theme">
            <div className="px-6 py-4 border-b border-theme">
              <h3 className="text-lg font-semibold text-theme-primary flex items-center">
                <span className="mr-2">🔔</span>
                Notification Settings
              </h3>
              <p className="text-sm text-theme-secondary mt-1">Configure email notifications and alerts</p>
            </div>
            <div className="p-6 space-y-6">
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <div className="flex items-center justify-between p-4 rounded-lg border border-theme bg-theme-background-secondary">
                  <div>
                    <h4 className="text-sm font-medium text-theme-primary">Payment Notifications</h4>
                    <p className="text-sm text-theme-secondary">Email alerts for payment events</p>
                  </div>
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input type="checkbox" className="sr-only peer" checked disabled={saving} />
                    <div className="toggle-theme peer-checked:bg-theme-success"></div>
                  </label>
                </div>

                <div className="flex items-center justify-between p-4 rounded-lg border border-theme bg-theme-background-secondary">
                  <div>
                    <h4 className="text-sm font-medium text-theme-primary">Security Alerts</h4>
                    <p className="text-sm text-theme-secondary">Notifications for security events</p>
                  </div>
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input type="checkbox" className="sr-only peer" checked disabled={saving} />
                    <div className="toggle-theme peer-checked:bg-theme-success"></div>
                  </label>
                </div>

                <div className="flex items-center justify-between p-4 rounded-lg border border-theme bg-theme-background-secondary">
                  <div>
                    <h4 className="text-sm font-medium text-theme-primary">System Maintenance</h4>
                    <p className="text-sm text-theme-secondary">Alerts for system maintenance</p>
                  </div>
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input type="checkbox" className="sr-only peer" checked disabled={saving} />
                    <div className="toggle-theme peer-checked:bg-theme-success"></div>
                  </label>
                </div>

                <div className="flex items-center justify-between p-4 rounded-lg border border-theme bg-theme-background-secondary">
                  <div>
                    <h4 className="text-sm font-medium text-theme-primary">User Activity</h4>
                    <p className="text-sm text-theme-secondary">Notifications for user registrations</p>
                  </div>
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input type="checkbox" className="sr-only peer" disabled={saving} />
                    <div className="toggle-theme peer-checked:bg-theme-success"></div>
                  </label>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Maintenance Tab */}
      {activeTab === 'maintenance' && (
        <div className="space-y-6">
          <div className="card-theme">
            <div className="px-6 py-4 border-b border-theme">
              <h3 className="text-lg font-semibold text-theme-primary flex items-center">
                <span className="mr-2">🔧</span>
                System Maintenance
              </h3>
              <p className="text-sm text-theme-secondary mt-1">Database maintenance, backups, and system health</p>
            </div>
            <div className="p-6 space-y-6">
              {/* Maintenance Mode Control */}
              <div className="bg-theme-background-secondary border border-theme rounded-lg p-6">
                <div className="flex items-center justify-between mb-4">
                  <div>
                    <h4 className="text-lg font-medium text-theme-primary">Maintenance Mode</h4>
                    <p className="text-sm text-theme-secondary">Put the system in maintenance mode to prevent user access</p>
                  </div>
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input
                      type="checkbox"
                      className="sr-only peer"
                      checked={systemSettings.maintenance_mode || false}
                      onChange={(e) => handleUpdateSettings({ maintenance_mode: e.target.checked })}
                      disabled={saving}
                    />
                    <div className="toggle-theme peer-checked:bg-theme-error"></div>
                  </label>
                </div>
                {systemSettings.maintenance_mode && (
                  <div className="alert-theme alert-theme-warning">
                    <strong>⚠️ Maintenance Mode Active:</strong> Users cannot access the application.
                  </div>
                )}
              </div>

              {/* Database Operations */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div className="card-theme p-6">
                  <h4 className="text-lg font-medium text-theme-primary mb-4 flex items-center">
                    <span className="mr-2">💾</span>
                    Database Backup
                  </h4>
                  <div className="space-y-4">
                    <div className="flex justify-between items-center">
                      <span className="text-sm text-theme-secondary">Last Backup</span>
                      <span className="text-sm font-medium text-theme-primary">2 hours ago</span>
                    </div>
                    <div className="flex justify-between items-center">
                      <span className="text-sm text-theme-secondary">Backup Size</span>
                      <span className="text-sm font-medium text-theme-primary">245 MB</span>
                    </div>
                    <button className="btn-theme btn-theme-primary w-full">
                      Create Backup Now
                    </button>
                  </div>
                </div>

                <div className="card-theme p-6">
                  <h4 className="text-lg font-medium text-theme-primary mb-4 flex items-center">
                    <span className="mr-2">🗑️</span>
                    Data Cleanup
                  </h4>
                  <div className="space-y-4">
                    <div className="flex justify-between items-center">
                      <span className="text-sm text-theme-secondary">Old Logs</span>
                      <span className="text-sm font-medium text-theme-primary">1,245 entries</span>
                    </div>
                    <div className="flex justify-between items-center">
                      <span className="text-sm text-theme-secondary">Expired Sessions</span>
                      <span className="text-sm font-medium text-theme-primary">67 sessions</span>
                    </div>
                    <button className="btn-theme btn-theme-secondary w-full">
                      Run Cleanup
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* System Logs Tab */}
      {activeTab === 'logs' && (
        <div className="space-y-6">
          {/* Log Stats */}
          <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
            <div className="card-theme p-4">
              <div className="flex items-center">
                <div className="text-2xl mr-3">📊</div>
                <div>
                  <p className="text-sm text-theme-secondary">Total Logs</p>
                  <p className="text-xl font-semibold text-theme-primary">{logs.length}</p>
                </div>
              </div>
            </div>
            <div className="card-theme p-4">
              <div className="flex items-center">
                <div className="text-2xl mr-3">❌</div>
                <div>
                  <p className="text-sm text-theme-secondary">Errors</p>
                  <p className="text-xl font-semibold text-theme-error">
                    {logs.filter(l => l.action.includes('error')).length}
                  </p>
                </div>
              </div>
            </div>
            <div className="card-theme p-4">
              <div className="flex items-center">
                <div className="text-2xl mr-3">⚠️</div>
                <div>
                  <p className="text-sm text-theme-secondary">Warnings</p>
                  <p className="text-xl font-semibold text-theme-warning">
                    {logs.filter(l => l.action.includes('warning')).length}
                  </p>
                </div>
              </div>
            </div>
            <div className="card-theme p-4">
              <div className="flex items-center">
                <div className="text-2xl mr-3">📅</div>
                <div>
                  <p className="text-sm text-theme-secondary">Today</p>
                  <p className="text-xl font-semibold text-theme-info">
                    {logs.filter(l => new Date(l.created_at).toDateString() === new Date().toDateString()).length}
                  </p>
                </div>
              </div>
            </div>
          </div>

          <div className="card-theme">
            <div className="px-6 py-4 border-b border-theme">
              <div className="flex items-center justify-between">
                <div>
                  <h3 className="text-lg font-semibold text-theme-primary flex items-center">
                    <span className="mr-2">📋</span>
                    System Logs
                  </h3>
                  <p className="text-sm text-theme-secondary mt-1">Monitor system activities and events</p>
                </div>
                <div className="flex items-center gap-3">
                  <select className="select-theme">
                    <option value="all">All Levels</option>
                    <option value="error">Errors Only</option>
                    <option value="warning">Warnings</option>
                    <option value="info">Info</option>
                  </select>
                  <select className="select-theme">
                    <option value="all">All Sources</option>
                    <option value="auth">Authentication</option>
                    <option value="payment">Payments</option>
                    <option value="system">System</option>
                  </select>
                  <button className="btn-theme btn-theme-secondary px-4 py-2">
                    Export Logs
                  </button>
                </div>
              </div>
            </div>
            <div className="overflow-x-auto">
              <table className="min-w-full divide-y divide-theme">
                <thead className="bg-theme-background-secondary">
                  <tr>
                    <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                      Level
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                      Timestamp
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                      Action
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                      User
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                      IP Address
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                      Actions
                    </th>
                  </tr>
                </thead>
                <tbody className="card-theme divide-y divide-theme">
                  {logs.slice(0, 50).map((log) => (
                    <tr key={log.id} className="hover:bg-theme-surface-hover">
                      <td className="px-6 py-4 whitespace-nowrap">
                        <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${
                          log.action.includes('error') ? 'bg-theme-error text-theme-error' :
                          log.action.includes('warning') ? 'bg-theme-warning text-theme-warning' :
                          'bg-theme-info text-theme-info'
                        }`}>
                          {log.action.includes('error') ? 'ERROR' : log.action.includes('warning') ? 'WARN' : 'INFO'}
                        </span>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-secondary">
                        <div>{new Date(log.created_at).toLocaleDateString()}</div>
                        <div className="text-xs">{new Date(log.created_at).toLocaleTimeString()}</div>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <span className="text-sm font-medium text-theme-primary">{log.action}</span>
                        <div className="text-sm text-theme-secondary">{log.resource_type}</div>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-primary">
                        {log.user ? `${log.user.full_name} (${log.user.email})` : 'System'}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-secondary">
                        {log.ip_address}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm font-medium">
                        <button className="text-theme-link hover:text-theme-link-hover">
                          View Details
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {/* Pagination */}
            <div className="px-6 py-4 border-t border-theme">
              <div className="flex items-center justify-between">
                <div className="text-sm text-theme-secondary">
                  Showing 1 to {Math.min(50, logs.length)} of {logs.length} logs
                </div>
                <div className="flex items-center gap-2">
                  <button className="btn-theme btn-theme-secondary px-3 py-1 text-sm">
                    Previous
                  </button>
                  <span className="px-3 py-1 text-sm text-theme-primary">1</span>
                  <button className="btn-theme btn-theme-secondary px-3 py-1 text-sm">
                    Next
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Create Service Modal */}
      {showCreateServiceModal && (
        <CreateServiceModal
          onClose={() => setShowCreateServiceModal(false)}
          onCreate={handleServiceCreate}
        />
      )}

      {/* Payment Gateway Configuration Modal */}
      {showConfigModal && configGateway && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="card-theme max-w-2xl w-full mx-4 max-h-[90vh] overflow-y-auto">
            <div className="p-6">
              <div className="flex items-center justify-between mb-6">
                <h3 className="text-xl font-semibold text-theme-primary">
                  Configure {configGateway === 'stripe' ? 'Stripe' : 'PayPal'}
                </h3>
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
                    <label className="label-theme">Publishable Key</label>
                    <input
                      type="text"
                      value={configForm.publishable_key || ''}
                      onChange={(e) => setConfigForm({...configForm, publishable_key: e.target.value})}
                      className="input-theme"
                      placeholder="pk_test_..."
                    />
                  </div>
                  <div>
                    <label className="label-theme">Secret Key</label>
                    <input
                      type="password"
                      value={configForm.secret_key || ''}
                      onChange={(e) => setConfigForm({...configForm, secret_key: e.target.value})}
                      className="input-theme"
                      placeholder="sk_test_..."
                    />
                  </div>
                  <div>
                    <label className="label-theme">Webhook Endpoint Secret</label>
                    <input
                      type="password"
                      value={configForm.endpoint_secret || ''}
                      onChange={(e) => setConfigForm({...configForm, endpoint_secret: e.target.value})}
                      className="input-theme"
                      placeholder="whsec_..."
                    />
                  </div>
                  <div>
                    <label className="label-theme">Webhook Tolerance (seconds)</label>
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
                    <label className="label-theme">Client ID</label>
                    <input
                      type="text"
                      value={configForm.client_id || ''}
                      onChange={(e) => setConfigForm({...configForm, client_id: e.target.value})}
                      className="input-theme"
                      placeholder="PayPal Client ID"
                    />
                  </div>
                  <div>
                    <label className="label-theme">Client Secret</label>
                    <input
                      type="password"
                      value={configForm.client_secret || ''}
                      onChange={(e) => setConfigForm({...configForm, client_secret: e.target.value})}
                      className="input-theme"
                      placeholder="PayPal Client Secret"
                    />
                  </div>
                  <div>
                    <label className="label-theme">Webhook ID</label>
                    <input
                      type="text"
                      value={configForm.webhook_id || ''}
                      onChange={(e) => setConfigForm({...configForm, webhook_id: e.target.value})}
                      className="input-theme"
                      placeholder="PayPal Webhook ID"
                    />
                  </div>
                  <div>
                    <label className="label-theme">Mode</label>
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