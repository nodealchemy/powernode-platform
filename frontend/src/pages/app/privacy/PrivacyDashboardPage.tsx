import React, { useState, useEffect } from 'react';
import { ShieldCheckIcon, DocumentTextIcon, Cog6ToothIcon } from '@heroicons/react/24/outline';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { ConsentManager } from '@/features/privacy/components/ConsentManager';
import { DataExportCard } from '@/features/privacy/components/DataExportCard';
import { DataDeletionCard } from '@/features/privacy/components/DataDeletionCard';
import privacyApi, {
  type PrivacyDashboard,
  type DataDeletionRequest,
} from '@/features/privacy/services/privacyApi';
import { useNotifications } from '@/shared/hooks/useNotifications';

const PrivacyDashboardPage: React.FC = () => {
  const [dashboard, setDashboard] = useState<PrivacyDashboard | null>(null);
  const [deletionRequest, setDeletionRequest] = useState<DataDeletionRequest | null>(null);
  const [loading, setLoading] = useState(true);
  const { showNotification } = useNotifications();

  useEffect(() => {
    loadDashboard();
    loadDeletionStatus();
  }, []);

  const loadDashboard = async () => {
    try {
      const data = await privacyApi.getDashboard();
      setDashboard(data);
    } catch (error) {
      showNotification('Failed to load privacy dashboard', 'error');
    } finally {
      setLoading(false);
    }
  };

  const loadDeletionStatus = async () => {
    try {
      const request = await privacyApi.getDeletionStatus();
      setDeletionRequest(request);
    } catch (error) {
      // Ignore - may not have a deletion request
    }
  };

  const handleUpdateConsents = async (consents: Partial<Record<string, boolean>>) => {
    try {
      const result = await privacyApi.updateConsents(consents);
      setDashboard((prev) => prev ? { ...prev, consents: result.consents } : prev);
      showNotification('Consent preferences updated', 'success');
    } catch (error) {
      showNotification('Failed to update consent preferences', 'error');
      throw error;
    }
  };

  const handleRequestExport = async (options: { format: string; export_type: string }) => {
    try {
      const request = await privacyApi.requestExport(options as Parameters<typeof privacyApi.requestExport>[0]);
      setDashboard((prev) =>
        prev ? { ...prev, export_requests: [request, ...prev.export_requests] } : prev
      );
      showNotification('Data export requested. You will be notified when it is ready.', 'success');
    } catch (error) {
      showNotification('Failed to request data export', 'error');
      throw error;
    }
  };

  const handleDownloadExport = async (id: string, token: string) => {
    try {
      const blob = await privacyApi.downloadExport(id, token);
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `powernode_data_export.zip`;
      document.body.appendChild(a);
      a.click();
      window.URL.revokeObjectURL(url);
      document.body.removeChild(a);
      showNotification('Download started', 'success');
    } catch (error) {
      showNotification('Failed to download export', 'error');
    }
  };

  const handleRequestDeletion = async (options: { deletion_type: string; reason?: string }) => {
    try {
      const request = await privacyApi.requestDeletion(options as Parameters<typeof privacyApi.requestDeletion>[0]);
      setDeletionRequest(request);
      showNotification('Data deletion request submitted', 'success');
    } catch (error) {
      showNotification('Failed to submit deletion request', 'error');
      throw error;
    }
  };

  const handleCancelDeletion = async (id: string) => {
    try {
      const request = await privacyApi.cancelDeletion(id);
      setDeletionRequest(request);
      showNotification('Deletion request cancelled', 'success');
    } catch (error) {
      showNotification('Failed to cancel deletion request', 'error');
    }
  };

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Privacy Center' }
  ];

  if (loading) {
    return (
      <PageContainer title="Privacy Center" breadcrumbs={breadcrumbs}>
        <div className="flex items-center justify-center h-64">
          <div className="animate-spin rounded-full h-8 w-8 border-t-2 border-b-2 border-theme-primary"></div>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="Privacy Center"
      description="Manage your privacy settings and data"
      breadcrumbs={breadcrumbs}
    >
      {/* Header Stats */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <div className="flex items-center space-x-3">
            <div className="p-3 bg-theme-success/20 dark:bg-theme-success/30 rounded-lg">
              <ShieldCheckIcon className="h-6 w-6 text-theme-success dark:text-theme-success" />
            </div>
            <div>
              <p className="text-sm text-theme-secondary">Active Consents</p>
              <p className="text-2xl font-bold text-theme-primary">
                {dashboard ? Object.values(dashboard.consents).filter((c) => c.granted).length : 0}
              </p>
            </div>
          </div>
        </div>

        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <div className="flex items-center space-x-3">
            <div className="p-3 bg-theme-info/20 dark:bg-theme-info/30 rounded-lg">
              <DocumentTextIcon className="h-6 w-6 text-theme-info dark:text-theme-info" />
            </div>
            <div>
              <p className="text-sm text-theme-secondary">Data Exports</p>
              <p className="text-2xl font-bold text-theme-primary">
                {dashboard?.export_requests.length || 0}
              </p>
            </div>
          </div>
        </div>

        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <div className="flex items-center space-x-3">
            <div className="p-3 bg-theme-interactive-primary/20 dark:bg-theme-interactive-primary/30 rounded-lg">
              <Cog6ToothIcon className="h-6 w-6 text-theme-interactive-primary dark:text-theme-interactive-primary" />
            </div>
            <div>
              <p className="text-sm text-theme-secondary">Terms Status</p>
              <p className="text-2xl font-bold text-theme-primary">
                {dashboard?.terms_status.needs_review ? 'Review Needed' : 'Up to Date'}
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* Terms Review Alert */}
      {dashboard?.terms_status.needs_review && (
        <div className="mb-8 p-4 bg-theme-warning/10 dark:bg-theme-warning/20 border border-theme-warning/30 dark:border-theme-warning/50 rounded-lg">
          <div className="flex items-center space-x-3">
            <DocumentTextIcon className="h-6 w-6 text-theme-warning" />
            <div>
              <p className="font-medium text-theme-warning dark:text-theme-warning">
                Terms and Policies Updated
              </p>
              <p className="text-sm text-theme-warning dark:text-theme-warning">
                Please review and accept the updated:{' '}
                {dashboard.terms_status.missing.join(', ').replace(/_/g, ' ')}
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Main Content */}
      <div className="space-y-8">
        {/* Consent Management */}
        {dashboard && (
          <ConsentManager
            consents={dashboard.consents}
            onUpdate={handleUpdateConsents}
            loading={loading}
          />
        )}

        {/* Data Export */}
        <DataExportCard
          requests={dashboard?.export_requests || []}
          onRequestExport={handleRequestExport}
          onDownload={handleDownloadExport}
          loading={loading}
        />

        {/* Data Deletion */}
        <DataDeletionCard
          deletionRequest={deletionRequest}
          onRequestDeletion={handleRequestDeletion}
          onCancelDeletion={handleCancelDeletion}
          loading={loading}
        />

        {/* Data Retention Info */}
        {dashboard?.data_retention_info && dashboard.data_retention_info.length > 0 && (
          <div className="bg-theme-surface rounded-lg border border-theme p-6">
            <h3 className="text-lg font-semibold text-theme-primary mb-4">Data Retention Policies</h3>
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead>
                  <tr className="text-left border-b border-theme">
                    <th className="pb-3 text-sm font-medium text-theme-secondary">Data Type</th>
                    <th className="pb-3 text-sm font-medium text-theme-secondary">Retention Period</th>
                    <th className="pb-3 text-sm font-medium text-theme-secondary">Action</th>
                  </tr>
                </thead>
                <tbody>
                  {dashboard.data_retention_info.map((policy, index) => (
                    <tr key={index} className="border-b border-theme last:border-0">
                      <td className="py-3 text-sm text-theme-primary capitalize">
                        {policy.data_type.replace(/_/g, ' ')}
                      </td>
                      <td className="py-3 text-sm text-theme-secondary">
                        {policy.retention_days
                          ? `${Math.round(policy.retention_days / 365)} years`
                          : 'As required'}
                      </td>
                      <td className="py-3">
                        <span
                          className={`px-2 py-1 text-xs rounded ${
                            policy.action === 'delete'
                              ? 'bg-theme-danger/20 text-theme-danger dark:bg-theme-danger/30 dark:text-theme-danger'
                              : policy.action === 'anonymize'
                              ? 'bg-theme-warning/20 text-theme-warning dark:bg-theme-warning/30 dark:text-theme-warning'
                              : 'bg-theme-info/20 text-theme-info dark:bg-theme-info/30 dark:text-theme-info'
                          }`}
                        >
                          {policy.action}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </div>
    </PageContainer>
  );
};

export default PrivacyDashboardPage;
