import React, { useState, useEffect } from 'react';
import {
  accountWebhooksApi,
  AccountGitWebhookConfig,
  AccountGitWebhookFormData,
} from '../services/git/accountWebhooksApi';
import { PaginationInfo } from '../types';

interface AccountWebhooksListProps {
  onViewDetails?: (webhook: AccountGitWebhookConfig) => void;
}

const statusColors: Record<string, string> = {
  active: 'bg-theme-success/10 text-theme-success',
  inactive: 'bg-theme-bg-tertiary text-theme-text-secondary',
};

const healthColors: Record<string, string> = {
  excellent: 'text-theme-success',
  good: 'text-theme-info',
  warning: 'text-theme-warning',
  critical: 'text-theme-danger',
  unknown: 'text-theme-text-tertiary',
};

export const AccountWebhooksList: React.FC<AccountWebhooksListProps> = ({ onViewDetails }) => {
  const [webhooks, setWebhooks] = useState<AccountGitWebhookConfig[]>([]);
  const [pagination, setPagination] = useState<PaginationInfo | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<'all' | 'active' | 'inactive'>('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  const fetchWebhooks = async (page = 1) => {
    setIsLoading(true);
    setError(null);
    try {
      const params: Parameters<typeof accountWebhooksApi.getAccountWebhooks>[0] = {
        page,
        per_page: 10,
      };

      if (statusFilter !== 'all') {
        params.status = statusFilter;
      }

      if (searchQuery.trim()) {
        params.search = searchQuery.trim();
      }

      const result = await accountWebhooksApi.getAccountWebhooks(params);
      setWebhooks(result.webhooks);
      setPagination(result.pagination);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load webhooks');
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchWebhooks();
  }, [statusFilter, searchQuery]);

  const handleToggleStatus = async (webhook: AccountGitWebhookConfig) => {
    setActionLoading(webhook.id);
    try {
      const result = await accountWebhooksApi.toggleAccountWebhookStatus(webhook.id);
      setWebhooks((prev) => prev.map((w) => (w.id === webhook.id ? result.webhook : w)));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to toggle status');
    } finally {
      setActionLoading(null);
    }
  };

  const handleDelete = async (webhook: AccountGitWebhookConfig) => {
    if (!confirm(`Delete webhook "${webhook.name}"? This action cannot be undone.`)) {
      return;
    }

    setActionLoading(webhook.id);
    try {
      await accountWebhooksApi.deleteAccountWebhook(webhook.id);
      setWebhooks((prev) => prev.filter((w) => w.id !== webhook.id));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to delete webhook');
    } finally {
      setActionLoading(null);
    }
  };

  const handleTest = async (webhook: AccountGitWebhookConfig) => {
    setActionLoading(webhook.id);
    try {
      await accountWebhooksApi.testAccountWebhook(webhook.id);
      // Could show a success message here
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to test webhook');
    } finally {
      setActionLoading(null);
    }
  };

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold text-theme-text-primary">Account Webhooks</h2>
          <p className="text-sm text-theme-text-secondary">
            Configure webhooks that receive events from all repositories in your account
          </p>
        </div>
        <button
          onClick={() => setShowCreateModal(true)}
          className="inline-flex items-center gap-2 px-4 py-2 bg-theme-primary text-white rounded-lg hover:bg-theme-primary-hover transition-colors"
        >
          <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
          </svg>
          Add Webhook
        </button>
      </div>

      {/* Filters */}
      <div className="flex items-center gap-4">
        <div className="flex-1">
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search webhooks..."
            className="w-full max-w-xs px-3 py-2 text-sm border border-theme-border rounded-lg bg-theme-bg-secondary text-theme-text-primary placeholder-theme-text-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
          />
        </div>
        <div className="flex items-center gap-2">
          {(['all', 'active', 'inactive'] as const).map((status) => (
            <button
              key={status}
              onClick={() => setStatusFilter(status)}
              className={`px-3 py-1.5 text-sm font-medium rounded-lg transition-colors ${
                statusFilter === status
                  ? 'bg-theme-primary text-white'
                  : 'bg-theme-bg-tertiary text-theme-text-secondary hover:bg-theme-bg-hover'
              }`}
            >
              {status.charAt(0).toUpperCase() + status.slice(1)}
            </button>
          ))}
        </div>
      </div>

      {/* Error Message */}
      {error && (
        <div className="p-4 bg-theme-danger/10 border border-theme-danger/20 rounded-lg">
          <p className="text-sm text-theme-danger">{error}</p>
        </div>
      )}

      {/* Loading State */}
      {isLoading && (
        <div className="flex items-center justify-center py-12">
          <svg
            className="w-8 h-8 animate-spin text-theme-primary"
            fill="none"
            viewBox="0 0 24 24"
          >
            <circle
              className="opacity-25"
              cx="12"
              cy="12"
              r="10"
              stroke="currentColor"
              strokeWidth="4"
            />
            <path
              className="opacity-75"
              fill="currentColor"
              d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
            />
          </svg>
        </div>
      )}

      {/* Webhooks List */}
      {!isLoading && webhooks.length === 0 && (
        <div className="text-center py-12">
          <svg
            className="mx-auto h-12 w-12 text-theme-text-tertiary"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={1.5}
              d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"
            />
          </svg>
          <h3 className="mt-2 text-sm font-medium text-theme-text-primary">No webhooks</h3>
          <p className="mt-1 text-sm text-theme-text-secondary">
            Get started by creating a new account webhook.
          </p>
        </div>
      )}

      {!isLoading && webhooks.length > 0 && (
        <div className="bg-theme-bg-primary border border-theme-border rounded-lg overflow-hidden">
          <table className="w-full">
            <thead>
              <tr className="bg-theme-bg-secondary border-b border-theme-border">
                <th className="px-4 py-3 text-left text-xs font-medium text-theme-text-tertiary uppercase tracking-wider">
                  Name / URL
                </th>
                <th className="px-4 py-3 text-left text-xs font-medium text-theme-text-tertiary uppercase tracking-wider">
                  Events
                </th>
                <th className="px-4 py-3 text-left text-xs font-medium text-theme-text-tertiary uppercase tracking-wider">
                  Health
                </th>
                <th className="px-4 py-3 text-left text-xs font-medium text-theme-text-tertiary uppercase tracking-wider">
                  Status
                </th>
                <th className="px-4 py-3 text-right text-xs font-medium text-theme-text-tertiary uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-theme-border">
              {webhooks.map((webhook) => (
                <tr key={webhook.id} className="hover:bg-theme-bg-hover">
                  <td className="px-4 py-4">
                    <div className="font-medium text-theme-text-primary">{webhook.name}</div>
                    <div className="text-sm text-theme-text-secondary truncate max-w-xs">
                      {webhook.url}
                    </div>
                    {webhook.branch_filter_enabled && (
                      <div className="mt-1 inline-flex items-center gap-1 px-2 py-0.5 bg-theme-bg-tertiary rounded text-xs text-theme-text-secondary">
                        <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path
                            strokeLinecap="round"
                            strokeLinejoin="round"
                            strokeWidth={2}
                            d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z"
                          />
                        </svg>
                        Branch filter: {webhook.branch_filter}
                      </div>
                    )}
                  </td>
                  <td className="px-4 py-4">
                    <div className="text-sm text-theme-text-primary">
                      {webhook.event_types.length === 0
                        ? 'All events'
                        : `${webhook.event_types.length} event${webhook.event_types.length === 1 ? '' : 's'}`}
                    </div>
                  </td>
                  <td className="px-4 py-4">
                    <div className="flex items-center gap-2">
                      <span className={`${healthColors[webhook.health_status]} font-medium text-sm`}>
                        {webhook.success_rate}%
                      </span>
                      <span className="text-xs text-theme-text-tertiary">
                        ({webhook.success_count + webhook.failure_count} deliveries)
                      </span>
                    </div>
                  </td>
                  <td className="px-4 py-4">
                    <span
                      className={`inline-flex px-2 py-1 text-xs font-medium rounded-full ${statusColors[webhook.status]}`}
                    >
                      {webhook.status}
                    </span>
                  </td>
                  <td className="px-4 py-4 text-right">
                    <div className="flex items-center justify-end gap-2">
                      <button
                        onClick={() => handleTest(webhook)}
                        disabled={actionLoading === webhook.id || !webhook.is_active}
                        title="Send test webhook"
                        className="p-1.5 text-theme-text-secondary hover:text-theme-primary hover:bg-theme-bg-hover rounded transition-colors disabled:opacity-50"
                      >
                        <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path
                            strokeLinecap="round"
                            strokeLinejoin="round"
                            strokeWidth={2}
                            d="M5 3l14 9-14 9V3z"
                          />
                        </svg>
                      </button>
                      <button
                        onClick={() => handleToggleStatus(webhook)}
                        disabled={actionLoading === webhook.id}
                        title={webhook.is_active ? 'Deactivate' : 'Activate'}
                        className="p-1.5 text-theme-text-secondary hover:text-theme-primary hover:bg-theme-bg-hover rounded transition-colors disabled:opacity-50"
                      >
                        {webhook.is_active ? (
                          <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path
                              strokeLinecap="round"
                              strokeLinejoin="round"
                              strokeWidth={2}
                              d="M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z"
                            />
                          </svg>
                        ) : (
                          <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path
                              strokeLinecap="round"
                              strokeLinejoin="round"
                              strokeWidth={2}
                              d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"
                            />
                            <path
                              strokeLinecap="round"
                              strokeLinejoin="round"
                              strokeWidth={2}
                              d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                            />
                          </svg>
                        )}
                      </button>
                      <button
                        onClick={() => onViewDetails?.(webhook)}
                        title="View details"
                        className="p-1.5 text-theme-text-secondary hover:text-theme-primary hover:bg-theme-bg-hover rounded transition-colors"
                      >
                        <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path
                            strokeLinecap="round"
                            strokeLinejoin="round"
                            strokeWidth={2}
                            d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                          />
                          <path
                            strokeLinecap="round"
                            strokeLinejoin="round"
                            strokeWidth={2}
                            d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"
                          />
                        </svg>
                      </button>
                      <button
                        onClick={() => handleDelete(webhook)}
                        disabled={actionLoading === webhook.id}
                        title="Delete"
                        className="p-1.5 text-theme-text-secondary hover:text-theme-danger hover:bg-theme-danger/10 rounded transition-colors disabled:opacity-50"
                      >
                        <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path
                            strokeLinecap="round"
                            strokeLinejoin="round"
                            strokeWidth={2}
                            d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                          />
                        </svg>
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Pagination */}
      {pagination && pagination.total_pages > 1 && (
        <div className="flex items-center justify-between">
          <div className="text-sm text-theme-text-secondary">
            Showing {(pagination.current_page - 1) * pagination.per_page + 1} to{' '}
            {Math.min(pagination.current_page * pagination.per_page, pagination.total_count)} of{' '}
            {pagination.total_count} webhooks
          </div>
          <div className="flex items-center gap-2">
            <button
              onClick={() => fetchWebhooks(pagination.current_page - 1)}
              disabled={pagination.current_page === 1}
              className="px-3 py-1 text-sm font-medium text-theme-text-secondary hover:text-theme-text-primary disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Previous
            </button>
            <button
              onClick={() => fetchWebhooks(pagination.current_page + 1)}
              disabled={pagination.current_page === pagination.total_pages}
              className="px-3 py-1 text-sm font-medium text-theme-text-secondary hover:text-theme-text-primary disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Next
            </button>
          </div>
        </div>
      )}

      {/* Create Modal would go here - keeping it simple for now */}
    </div>
  );
};

export default AccountWebhooksList;
