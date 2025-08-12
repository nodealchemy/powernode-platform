import React, { useState } from 'react';
import { 
  Eye, 
  Edit, 
  Trash2, 
  Power, 
  PowerOff,
  Globe,
  Clock,
  CheckCircle,
  AlertTriangle,
  Search,
  Filter,
  MoreVertical,
  ExternalLink,
  Calendar,
  Activity,
  TrendingUp,
  TrendingDown
} from 'lucide-react';
import webhooksApi, { WebhookEndpoint } from '../../services/webhooksApi';
import Pagination from '../common/Pagination';

interface WebhookListProps {
  webhooks: WebhookEndpoint[];
  pagination: {
    current_page: number;
    per_page: number;
    total_pages: number;
    total_count: number;
  };
  onPageChange: (page: number) => void;
  onView: (webhook: WebhookEndpoint) => void;
  onEdit: (webhook: WebhookEndpoint) => void;
  onDelete: (webhookId: string) => void;
  onToggleStatus: (webhookId: string) => void;
  filters: {
    status: string;
    search: string;
  };
  onFiltersChange: (filters: any) => void;
}

const WebhookList: React.FC<WebhookListProps> = ({
  webhooks,
  pagination,
  onPageChange,
  onView,
  onEdit,
  onDelete,
  onToggleStatus,
  filters,
  onFiltersChange
}) => {
  const [expandedRows, setExpandedRows] = useState<Set<string>>(new Set());
  const [dropdownOpen, setDropdownOpen] = useState<string | null>(null);

  // Toggle row expansion
  const toggleRowExpansion = (webhookId: string) => {
    const newExpanded = new Set(expandedRows);
    if (newExpanded.has(webhookId)) {
      newExpanded.delete(webhookId);
    } else {
      newExpanded.add(webhookId);
    }
    setExpandedRows(newExpanded);
  };

  // Filter webhooks based on current filters
  const filteredWebhooks = webhooks.filter(webhook => {
    const matchesStatus = filters.status === 'all' || webhook.status === filters.status;
    const matchesSearch = filters.search === '' || 
      webhook.url.toLowerCase().includes(filters.search.toLowerCase()) ||
      (webhook.description && webhook.description.toLowerCase().includes(filters.search.toLowerCase()));
    
    return matchesStatus && matchesSearch;
  });

  // Handle dropdown toggle
  const toggleDropdown = (webhookId: string) => {
    setDropdownOpen(dropdownOpen === webhookId ? null : webhookId);
  };

  // Close dropdown when clicking outside
  React.useEffect(() => {
    const handleClickOutside = () => setDropdownOpen(null);
    document.addEventListener('click', handleClickOutside);
    return () => document.removeEventListener('click', handleClickOutside);
  }, []);

  if (webhooks.length === 0) {
    return (
      <div className="bg-theme-surface rounded-lg border border-theme p-8 text-center">
        <Globe className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
        <h3 className="text-lg font-medium text-theme-primary mb-2">No webhooks configured</h3>
        <p className="text-theme-secondary mb-4">
          Create your first webhook endpoint to start receiving real-time notifications
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Filters */}
      <div className="bg-theme-surface rounded-lg border border-theme p-4">
        <div className="flex flex-col sm:flex-row gap-4">
          {/* Search */}
          <div className="flex-1">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-tertiary w-4 h-4" />
              <input
                type="text"
                placeholder="Search webhooks..."
                value={filters.search}
                onChange={(e) => onFiltersChange({ ...filters, search: e.target.value })}
                className="w-full pl-10 pr-4 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus"
              />
            </div>
          </div>

          {/* Status Filter */}
          <div className="sm:w-48">
            <select
              value={filters.status}
              onChange={(e) => onFiltersChange({ ...filters, status: e.target.value })}
              className="w-full px-4 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
            >
              <option value="all">All Status</option>
              <option value="active">Active</option>
              <option value="inactive">Inactive</option>
            </select>
          </div>
        </div>

        {filteredWebhooks.length < webhooks.length && (
          <div className="mt-4 text-sm text-theme-secondary">
            Showing {filteredWebhooks.length} of {webhooks.length} webhooks
          </div>
        )}
      </div>

      {/* Webhooks List */}
      <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
        {/* Desktop Table */}
        <div className="hidden md:block">
          <table className="w-full">
            <thead>
              <tr className="bg-theme-background border-b border-theme">
                <th className="text-left py-3 px-4 font-medium text-theme-primary">
                  Webhook
                </th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">
                  Status
                </th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">
                  Events
                </th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">
                  Performance
                </th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">
                  Last Delivery
                </th>
                <th className="text-right py-3 px-4 font-medium text-theme-primary">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-theme">
              {filteredWebhooks.map((webhook) => {
                const successRate = webhooksApi.getSuccessRate(webhook);
                const isExpanded = expandedRows.has(webhook.id);

                return (
                  <React.Fragment key={webhook.id}>
                    {/* Main Row */}
                    <tr className="hover:bg-theme-surface-hover transition-colors duration-200">
                      <td className="py-3 px-4">
                        <div>
                          <div className="flex items-center gap-2">
                            <Globe className="w-4 h-4 text-theme-tertiary flex-shrink-0" />
                            <span 
                              className="font-medium text-theme-primary hover:text-theme-link cursor-pointer truncate"
                              onClick={() => onView(webhook)}
                              title={webhook.url}
                            >
                              {webhooksApi.formatUrl(webhook.url, 40)}
                            </span>
                            <ExternalLink className="w-3 h-3 text-theme-tertiary" />
                          </div>
                          {webhook.description && (
                            <p className="text-sm text-theme-secondary mt-1 truncate">
                              {webhook.description}
                            </p>
                          )}
                        </div>
                      </td>

                      <td className="py-3 px-4">
                        <span className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-medium ${
                          webhooksApi.getStatusColor(webhook.status)
                        }`}>
                          {webhook.status === 'active' ? (
                            <CheckCircle className="w-3 h-3 mr-1" />
                          ) : (
                            <Clock className="w-3 h-3 mr-1" />
                          )}
                          {webhook.status.charAt(0).toUpperCase() + webhook.status.slice(1)}
                        </span>
                      </td>

                      <td className="py-3 px-4">
                        <div className="flex items-center gap-2">
                          <span className="text-sm text-theme-primary font-medium">
                            {webhook.event_types.length}
                          </span>
                          <span className="text-sm text-theme-secondary">
                            event{webhook.event_types.length !== 1 ? 's' : ''}
                          </span>
                          {webhook.event_types.length > 0 && (
                            <button
                              onClick={() => toggleRowExpansion(webhook.id)}
                              className="text-xs text-theme-link hover:text-theme-link-hover"
                            >
                              {isExpanded ? 'Hide' : 'View'}
                            </button>
                          )}
                        </div>
                      </td>

                      <td className="py-3 px-4">
                        <div className="flex items-center gap-4">
                          <div className="text-center">
                            <div className={`text-sm font-medium ${
                              successRate >= 95 ? 'text-theme-success' :
                              successRate >= 80 ? 'text-theme-warning' : 'text-theme-error'
                            }`}>
                              {successRate}%
                            </div>
                            <div className="text-xs text-theme-secondary">Success</div>
                          </div>
                          
                          <div className="text-center">
                            <div className="text-sm font-medium text-theme-primary">
                              {webhook.success_count + webhook.failure_count}
                            </div>
                            <div className="text-xs text-theme-secondary">Total</div>
                          </div>
                        </div>
                      </td>

                      <td className="py-3 px-4">
                        {webhook.last_delivery_at ? (
                          <div>
                            <div className="text-sm text-theme-primary">
                              {new Date(webhook.last_delivery_at).toLocaleDateString()}
                            </div>
                            <div className="text-xs text-theme-secondary">
                              {new Date(webhook.last_delivery_at).toLocaleTimeString()}
                            </div>
                          </div>
                        ) : (
                          <span className="text-sm text-theme-tertiary">Never</span>
                        )}
                      </td>

                      <td className="py-3 px-4">
                        <div className="flex items-center justify-end gap-2">
                          <button
                            onClick={() => onView(webhook)}
                            className="p-1 text-theme-secondary hover:text-theme-primary transition-colors duration-200"
                            title="View Details"
                          >
                            <Eye className="w-4 h-4" />
                          </button>

                          <button
                            onClick={() => onEdit(webhook)}
                            className="p-1 text-theme-secondary hover:text-theme-primary transition-colors duration-200"
                            title="Edit Webhook"
                          >
                            <Edit className="w-4 h-4" />
                          </button>

                          <button
                            onClick={() => onToggleStatus(webhook.id)}
                            className={`p-1 transition-colors duration-200 ${
                              webhook.status === 'active'
                                ? 'text-theme-warning hover:text-theme-warning-hover'
                                : 'text-theme-success hover:text-theme-success-hover'
                            }`}
                            title={`${webhook.status === 'active' ? 'Disable' : 'Enable'} Webhook`}
                          >
                            {webhook.status === 'active' ? (
                              <PowerOff className="w-4 h-4" />
                            ) : (
                              <Power className="w-4 h-4" />
                            )}
                          </button>

                          <button
                            onClick={() => onDelete(webhook.id)}
                            className="p-1 text-theme-error hover:text-theme-error-hover transition-colors duration-200"
                            title="Delete Webhook"
                          >
                            <Trash2 className="w-4 h-4" />
                          </button>
                        </div>
                      </td>
                    </tr>

                    {/* Expanded Row - Event Types */}
                    {isExpanded && (
                      <tr>
                        <td colSpan={6} className="px-4 py-3 bg-theme-background border-b border-theme">
                          <div>
                            <h4 className="text-sm font-medium text-theme-primary mb-2">
                              Subscribed Events:
                            </h4>
                            <div className="flex flex-wrap gap-2">
                              {webhook.event_types.map((eventType) => (
                                <span
                                  key={eventType}
                                  className="px-2 py-1 bg-theme-interactive-primary bg-opacity-10 text-theme-interactive-primary rounded text-xs"
                                >
                                  {webhooksApi.formatEventType(eventType)}
                                </span>
                              ))}
                            </div>
                          </div>
                        </td>
                      </tr>
                    )}
                  </React.Fragment>
                );
              })}
            </tbody>
          </table>
        </div>

        {/* Mobile Cards */}
        <div className="md:hidden divide-y divide-theme">
          {filteredWebhooks.map((webhook) => {
            const successRate = webhooksApi.getSuccessRate(webhook);
            
            return (
              <div key={webhook.id} className="p-4">
                {/* Header */}
                <div className="flex items-start justify-between mb-3">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 mb-1">
                      <Globe className="w-4 h-4 text-theme-tertiary flex-shrink-0" />
                      <span 
                        className="font-medium text-theme-primary hover:text-theme-link cursor-pointer truncate"
                        onClick={() => onView(webhook)}
                      >
                        {webhooksApi.formatUrl(webhook.url, 30)}
                      </span>
                    </div>
                    {webhook.description && (
                      <p className="text-sm text-theme-secondary truncate">
                        {webhook.description}
                      </p>
                    )}
                  </div>
                  
                  <div className="relative">
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        toggleDropdown(webhook.id);
                      }}
                      className="p-1 text-theme-secondary hover:text-theme-primary transition-colors duration-200"
                    >
                      <MoreVertical className="w-4 h-4" />
                    </button>

                    {dropdownOpen === webhook.id && (
                      <div className="absolute right-0 mt-1 w-48 bg-theme-surface border border-theme rounded-lg shadow-lg z-10">
                        <div className="py-1">
                          <button
                            onClick={() => {
                              onView(webhook);
                              setDropdownOpen(null);
                            }}
                            className="w-full text-left px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                          >
                            <Eye className="w-4 h-4" />
                            View Details
                          </button>
                          <button
                            onClick={() => {
                              onEdit(webhook);
                              setDropdownOpen(null);
                            }}
                            className="w-full text-left px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                          >
                            <Edit className="w-4 h-4" />
                            Edit Webhook
                          </button>
                          <button
                            onClick={() => {
                              onToggleStatus(webhook.id);
                              setDropdownOpen(null);
                            }}
                            className={`w-full text-left px-4 py-2 text-sm hover:bg-theme-surface-hover flex items-center gap-2 ${
                              webhook.status === 'active' ? 'text-theme-warning' : 'text-theme-success'
                            }`}
                          >
                            {webhook.status === 'active' ? (
                              <>
                                <PowerOff className="w-4 h-4" />
                                Disable Webhook
                              </>
                            ) : (
                              <>
                                <Power className="w-4 h-4" />
                                Enable Webhook
                              </>
                            )}
                          </button>
                          <button
                            onClick={() => {
                              onDelete(webhook.id);
                              setDropdownOpen(null);
                            }}
                            className="w-full text-left px-4 py-2 text-sm text-theme-error hover:bg-theme-surface-hover flex items-center gap-2"
                          >
                            <Trash2 className="w-4 h-4" />
                            Delete Webhook
                          </button>
                        </div>
                      </div>
                    )}
                  </div>
                </div>

                {/* Stats */}
                <div className="grid grid-cols-3 gap-4 mb-3">
                  <div className="text-center">
                    <span className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-medium ${
                      webhooksApi.getStatusColor(webhook.status)
                    }`}>
                      {webhook.status === 'active' ? (
                        <CheckCircle className="w-3 h-3 mr-1" />
                      ) : (
                        <Clock className="w-3 h-3 mr-1" />
                      )}
                      {webhook.status.charAt(0).toUpperCase() + webhook.status.slice(1)}
                    </span>
                  </div>

                  <div className="text-center">
                    <div className="text-sm font-medium text-theme-primary">
                      {webhook.event_types.length}
                    </div>
                    <div className="text-xs text-theme-secondary">
                      Event{webhook.event_types.length !== 1 ? 's' : ''}
                    </div>
                  </div>

                  <div className="text-center">
                    <div className={`text-sm font-medium ${
                      successRate >= 95 ? 'text-theme-success' :
                      successRate >= 80 ? 'text-theme-warning' : 'text-theme-error'
                    }`}>
                      {successRate}%
                    </div>
                    <div className="text-xs text-theme-secondary">Success</div>
                  </div>
                </div>

                {/* Last Delivery */}
                <div className="text-xs text-theme-secondary">
                  Last delivery: {webhook.last_delivery_at 
                    ? new Date(webhook.last_delivery_at).toLocaleString()
                    : 'Never'
                  }
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Pagination */}
      {pagination.total_pages > 1 && (
        <div className="flex justify-center">
          <Pagination
            currentPage={pagination.current_page}
            totalPages={pagination.total_pages}
            onPageChange={onPageChange}
          />
        </div>
      )}
    </div>
  );
};

export default WebhookList;