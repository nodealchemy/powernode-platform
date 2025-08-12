import React, { useState, useEffect } from 'react';
import { 
  Filter, 
  X, 
  Calendar, 
  Search, 
  User, 
  Shield, 
  AlertTriangle,
  Clock,
  RefreshCw
} from 'lucide-react';
import { AuditLogFilters as FilterType } from '../../services/auditLogsApi';

interface AuditLogFiltersProps {
  filters: FilterType;
  onFiltersChange: (filters: FilterType) => void;
  onClearFilters: () => void;
  isLoading?: boolean;
}

export const AuditLogFilters: React.FC<AuditLogFiltersProps> = ({
  filters,
  onFiltersChange,
  onClearFilters,
  isLoading = false
}) => {
  const [isExpanded, setIsExpanded] = useState(false);
  const [localFilters, setLocalFilters] = useState<FilterType>(filters);

  useEffect(() => {
    setLocalFilters(filters);
  }, [filters]);

  const handleFilterChange = (key: keyof FilterType, value: string | undefined) => {
    const newFilters = { ...localFilters, [key]: value || undefined };
    setLocalFilters(newFilters);
    onFiltersChange(newFilters);
  };

  const handleDateChange = (field: 'date_from' | 'date_to', value: string) => {
    handleFilterChange(field, value || undefined);
  };

  const clearFilter = (key: keyof FilterType) => {
    handleFilterChange(key, undefined);
  };

  const hasActiveFilters = Object.values(localFilters).some(value => value !== undefined && value !== '');

  const actionOptions = [
    'user_login', 'user_logout', 'user_registration', 'login_failed',
    'subscription_created', 'subscription_updated', 'subscription_cancelled',
    'payment_completed', 'payment_failed', 'payment_refunded',
    'admin_settings_update', 'impersonation_started', 'impersonation_ended',
    'account_locked', 'account_unlocked', 'password_changed',
    'two_factor_enabled', 'two_factor_disabled', 'api_key_created',
    'security_alert', 'fraud_detection', 'suspicious_activity',
    'gdpr_request', 'ccpa_request', 'data_export', 'audit_log_cleanup'
  ];

  const sourceOptions = [
    'web', 'api', 'system', 'webhook', 'admin_panel', 'mobile_app', 'integration'
  ];

  const resourceTypeOptions = [
    'User', 'Account', 'Subscription', 'Payment', 'Invoice', 'Plan',
    'ApiKey', 'WebhookEndpoint', 'SystemSettings', 'AuditLog'
  ];

  const statusOptions = ['success', 'warning', 'error'];

  const severityOptions = ['low', 'medium', 'high', 'critical'];

  const riskLevelOptions = ['low', 'medium', 'high', 'critical'];

  return (
    <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
      {/* Filter Header */}
      <div className="px-4 py-3 border-b border-theme">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Filter className="w-4 h-4 text-theme-secondary" />
            <h3 className="text-sm font-medium text-theme-primary">Filters</h3>
            {hasActiveFilters && (
              <span className="px-2 py-1 bg-theme-interactive-primary text-white text-xs rounded-full">
                {Object.values(localFilters).filter(v => v).length}
              </span>
            )}
          </div>
          
          <div className="flex items-center gap-2">
            <button
              onClick={() => setIsExpanded(!isExpanded)}
              className="text-theme-secondary hover:text-theme-primary transition-colors duration-200"
            >
              <RefreshCw className={`w-4 h-4 transition-transform duration-200 ${isExpanded ? 'rotate-180' : ''}`} />
            </button>
            
            {hasActiveFilters && (
              <button
                onClick={onClearFilters}
                className="flex items-center gap-1 px-2 py-1 text-xs text-theme-secondary hover:text-theme-primary transition-colors duration-200"
              >
                <X className="w-3 h-3" />
                Clear All
              </button>
            )}
          </div>
        </div>
      </div>

      {/* Quick Filters */}
      <div className="px-4 py-3 border-b border-theme">
        <div className="flex flex-wrap gap-2">
          <button
            onClick={() => handleFilterChange('action', 'login_failed')}
            className={`flex items-center gap-1 px-3 py-1 text-xs rounded-full transition-colors duration-200 ${
              localFilters.action === 'login_failed'
                ? 'bg-theme-error bg-opacity-10 text-theme-error'
                : 'bg-theme-background text-theme-secondary hover:text-theme-primary'
            }`}
          >
            <Shield className="w-3 h-3" />
            Failed Logins
          </button>
          
          <button
            onClick={() => handleFilterChange('status', 'error')}
            className={`flex items-center gap-1 px-3 py-1 text-xs rounded-full transition-colors duration-200 ${
              localFilters.status === 'error'
                ? 'bg-theme-error bg-opacity-10 text-theme-error'
                : 'bg-theme-background text-theme-secondary hover:text-theme-primary'
            }`}
          >
            <AlertTriangle className="w-3 h-3" />
            Errors
          </button>
          
          <button
            onClick={() => handleFilterChange('source', 'admin_panel')}
            className={`flex items-center gap-1 px-3 py-1 text-xs rounded-full transition-colors duration-200 ${
              localFilters.source === 'admin_panel'
                ? 'bg-theme-warning bg-opacity-10 text-theme-warning'
                : 'bg-theme-background text-theme-secondary hover:text-theme-primary'
            }`}
          >
            <User className="w-3 h-3" />
            Admin Actions
          </button>
          
          <button
            onClick={() => handleFilterChange('date_from', new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString().split('T')[0])}
            className={`flex items-center gap-1 px-3 py-1 text-xs rounded-full transition-colors duration-200 ${
              localFilters.date_from === new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString().split('T')[0]
                ? 'bg-theme-info bg-opacity-10 text-theme-info'
                : 'bg-theme-background text-theme-secondary hover:text-theme-primary'
            }`}
          >
            <Clock className="w-3 h-3" />
            Last 24h
          </button>
        </div>
      </div>

      {/* Expanded Filters */}
      {isExpanded && (
        <div className="px-4 py-4 space-y-4">
          {/* Search and Date Range */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div>
              <label className="block text-xs font-medium text-theme-secondary mb-1">
                User Email
              </label>
              <div className="relative">
                <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-theme-tertiary" />
                <input
                  type="text"
                  value={localFilters.user_email || ''}
                  onChange={(e) => handleFilterChange('user_email', e.target.value)}
                  placeholder="Search by user email..."
                  className="w-full pl-9 pr-3 py-2 text-sm bg-theme-background border border-theme rounded-md text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-focus focus:border-transparent"
                />
              </div>
            </div>
            
            <div>
              <label className="block text-xs font-medium text-theme-secondary mb-1">
                From Date
              </label>
              <div className="relative">
                <Calendar className="absolute left-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-theme-tertiary" />
                <input
                  type="date"
                  value={localFilters.date_from || ''}
                  onChange={(e) => handleDateChange('date_from', e.target.value)}
                  className="w-full pl-9 pr-3 py-2 text-sm bg-theme-background border border-theme rounded-md text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-focus focus:border-transparent"
                />
              </div>
            </div>
            
            <div>
              <label className="block text-xs font-medium text-theme-secondary mb-1">
                To Date
              </label>
              <div className="relative">
                <Calendar className="absolute left-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-theme-tertiary" />
                <input
                  type="date"
                  value={localFilters.date_to || ''}
                  onChange={(e) => handleDateChange('date_to', e.target.value)}
                  className="w-full pl-9 pr-3 py-2 text-sm bg-theme-background border border-theme rounded-md text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-focus focus:border-transparent"
                />
              </div>
            </div>
          </div>

          {/* Action and Source */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-medium text-theme-secondary mb-1">
                Action
              </label>
              <select
                value={localFilters.action || ''}
                onChange={(e) => handleFilterChange('action', e.target.value)}
                className="w-full px-3 py-2 text-sm bg-theme-background border border-theme rounded-md text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-focus focus:border-transparent"
              >
                <option value="">All Actions</option>
                {actionOptions.map((action) => (
                  <option key={action} value={action}>
                    {action.split('_').map(word => word.charAt(0).toUpperCase() + word.slice(1)).join(' ')}
                  </option>
                ))}
              </select>
            </div>
            
            <div>
              <label className="block text-xs font-medium text-theme-secondary mb-1">
                Source
              </label>
              <select
                value={localFilters.source || ''}
                onChange={(e) => handleFilterChange('source', e.target.value)}
                className="w-full px-3 py-2 text-sm bg-theme-background border border-theme rounded-md text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-focus focus:border-transparent"
              >
                <option value="">All Sources</option>
                {sourceOptions.map((source) => (
                  <option key={source} value={source}>
                    {source.charAt(0).toUpperCase() + source.slice(1)}
                  </option>
                ))}
              </select>
            </div>
          </div>

          {/* Resource Type and Status */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-medium text-theme-secondary mb-1">
                Resource Type
              </label>
              <select
                value={localFilters.resource_type || ''}
                onChange={(e) => handleFilterChange('resource_type', e.target.value)}
                className="w-full px-3 py-2 text-sm bg-theme-background border border-theme rounded-md text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-focus focus:border-transparent"
              >
                <option value="">All Resources</option>
                {resourceTypeOptions.map((type) => (
                  <option key={type} value={type}>
                    {type}
                  </option>
                ))}
              </select>
            </div>
            
            <div>
              <label className="block text-xs font-medium text-theme-secondary mb-1">
                Status
              </label>
              <select
                value={localFilters.status || ''}
                onChange={(e) => handleFilterChange('status', e.target.value)}
                className="w-full px-3 py-2 text-sm bg-theme-background border border-theme rounded-md text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-focus focus:border-transparent"
              >
                <option value="">All Statuses</option>
                {statusOptions.map((status) => (
                  <option key={status} value={status}>
                    {status.charAt(0).toUpperCase() + status.slice(1)}
                  </option>
                ))}
              </select>
            </div>
          </div>

          {/* Account Name and IP Address */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-medium text-theme-secondary mb-1">
                Account Name
              </label>
              <input
                type="text"
                value={localFilters.account_name || ''}
                onChange={(e) => handleFilterChange('account_name', e.target.value)}
                placeholder="Search by account name..."
                className="w-full px-3 py-2 text-sm bg-theme-background border border-theme rounded-md text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-focus focus:border-transparent"
              />
            </div>
            
            <div>
              <label className="block text-xs font-medium text-theme-secondary mb-1">
                IP Address
              </label>
              <input
                type="text"
                value={localFilters.ip_address || ''}
                onChange={(e) => handleFilterChange('ip_address', e.target.value)}
                placeholder="Filter by IP address..."
                className="w-full px-3 py-2 text-sm bg-theme-background border border-theme rounded-md text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-focus focus:border-transparent"
              />
            </div>
          </div>
        </div>
      )}

      {/* Active Filters Display */}
      {hasActiveFilters && (
        <div className="px-4 py-3 bg-theme-background border-t border-theme">
          <div className="flex flex-wrap gap-2">
            {Object.entries(localFilters).map(([key, value]) => {
              if (!value) return null;
              
              return (
                <div
                  key={key}
                  className="flex items-center gap-1 px-2 py-1 bg-theme-interactive-primary bg-opacity-10 text-theme-interactive-primary text-xs rounded-full"
                >
                  <span className="font-medium">
                    {key.replace('_', ' ').replace(/\b\w/g, l => l.toUpperCase())}:
                  </span>
                  <span>{value}</span>
                  <button
                    onClick={() => clearFilter(key as keyof FilterType)}
                    className="ml-1 hover:bg-theme-interactive-primary hover:bg-opacity-20 rounded-full p-0.5 transition-colors duration-200"
                  >
                    <X className="w-3 h-3" />
                  </button>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
};