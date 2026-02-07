import React, { useState, useEffect } from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import {
  BarChart3,
  FileText,
  Clock,
  CheckCircle,
  AlertTriangle,
  Download,
  Calendar
} from 'lucide-react';
import { formatDateTime } from '@/shared/utils/formatters';

interface ReportsStats {
  total_reports: number;
  reports_this_month: number;
  pending_reports: number;
  failed_reports: number;
  most_popular_template: string;
  avg_generation_time: number;
  total_downloads: number;
  storage_used: string;
}

interface RecentReport {
  id: string;
  name: string;
  template: string;
  status: 'pending' | 'processing' | 'completed' | 'failed';
  requested_at: string;
  completed_at?: string;
  requested_by: string;
  file_size?: string;
}

export const ReportsOverviewPage: React.FC = () => {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [stats, setStats] = useState<ReportsStats | null>(null);
  const [recentReports, setRecentReports] = useState<RecentReport[]>([]);

  // WebSocket for real-time updates
  usePageWebSocket({
    pageType: 'business',
    onDataUpdate: () => {
      // Trigger data refresh if needed
      loadOverviewData();
    }
  });

  useEffect(() => {
    loadOverviewData();
  }, []);

  const loadOverviewData = async () => {
    try {
      setLoading(true);
      setError(null);

      // Simulate API calls (replace with actual API endpoints)
      const [statsResponse, recentResponse] = await Promise.all([
        // reportsService.getStats(),
        // reportsService.getRecentReports()
        Promise.resolve({
          data: {
            total_reports: 147,
            reports_this_month: 23,
            pending_reports: 3,
            failed_reports: 1,
            most_popular_template: 'Revenue Analysis',
            avg_generation_time: 45,
            total_downloads: 89,
            storage_used: '2.3 GB'
          }
        }),
        Promise.resolve({
          data: [
            {
              id: '1',
              name: 'Monthly Revenue Report',
              template: 'Revenue Analysis',
              status: 'completed' as const,
              requested_at: '2024-01-15T10:30:00Z',
              completed_at: '2024-01-15T10:32:15Z',
              requested_by: 'John Doe',
              file_size: '1.2 MB'
            },
            {
              id: '2',
              name: 'Customer Growth Analysis',
              template: 'Customer Analytics',
              status: 'processing' as const,
              requested_at: '2024-01-15T11:15:00Z',
              requested_by: 'Jane Smith'
            },
            {
              id: '3',
              name: 'Subscription Metrics',
              template: 'Subscription Report',
              status: 'completed' as const,
              requested_at: '2024-01-15T09:45:00Z',
              completed_at: '2024-01-15T09:47:30Z',
              requested_by: 'Mike Johnson',
              file_size: '856 KB'
            }
          ] satisfies RecentReport[]
        })
      ]);

      setStats(statsResponse.data);
      setRecentReports(recentResponse.data);
    } catch (error) {
      setError(error instanceof Error ? error.message : 'Failed to load overview data');
    } finally {
      setLoading(false);
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'completed':
        return <CheckCircle className="w-4 h-4 text-theme-success" />;
      case 'processing':
        return <Clock className="w-4 h-4 text-theme-warning animate-pulse" />;
      case 'pending':
        return <Clock className="w-4 h-4 text-theme-secondary" />;
      case 'failed':
        return <AlertTriangle className="w-4 h-4 text-theme-error" />;
      default:
        return <Clock className="w-4 h-4 text-theme-secondary" />;
    }
  };

  const getStatusText = (status: string) => {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'processing':
        return 'Processing';
      case 'pending':
        return 'Pending';
      case 'failed':
        return 'Failed';
      default:
        return 'Unknown';
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <LoadingSpinner />
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-theme-error-background border border-theme-error-border rounded-lg p-6">
        <h3 className="font-medium text-theme-error mb-2">Error Loading Overview</h3>
        <p className="text-theme-error opacity-80">{error}</p>
      </div>
    );
  }

  return (
    <PageContainer
      title="Reports Overview"
      description="Monitor your reporting activity and performance"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'Business', href: '/app/business' },
        { label: 'Reports Overview' }
      ]}
    >
      <div className="space-y-6">
        {/* Stats Grid */}
        {stats && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
          <div className="bg-theme-surface rounded-lg p-6">
            <div className="flex items-center gap-3">
              <FileText className="w-8 h-8 text-theme-interactive-primary" />
              <div>
                <p className="text-2xl font-bold text-theme-primary">{stats.total_reports}</p>
                <p className="text-sm text-theme-secondary">Total Reports</p>
              </div>
            </div>
          </div>

          <div className="bg-theme-surface rounded-lg p-6">
            <div className="flex items-center gap-3">
              <Calendar className="w-8 h-8 text-theme-success" />
              <div>
                <p className="text-2xl font-bold text-theme-primary">{stats.reports_this_month}</p>
                <p className="text-sm text-theme-secondary">This Month</p>
              </div>
            </div>
          </div>

          <div className="bg-theme-surface rounded-lg p-6">
            <div className="flex items-center gap-3">
              <Clock className="w-8 h-8 text-theme-warning" />
              <div>
                <p className="text-2xl font-bold text-theme-primary">{stats.pending_reports}</p>
                <p className="text-sm text-theme-secondary">Pending</p>
              </div>
            </div>
          </div>

          <div className="bg-theme-surface rounded-lg p-6">
            <div className="flex items-center gap-3">
              <Download className="w-8 h-8 text-theme-interactive-primary" />
              <div>
                <p className="text-2xl font-bold text-theme-primary">{stats.total_downloads}</p>
                <p className="text-sm text-theme-secondary">Downloads</p>
              </div>
            </div>
          </div>
        </div>
        )}

        {/* Performance Metrics */}
        {stats && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <div className="bg-theme-surface rounded-lg p-6">
            <h3 className="text-lg font-semibold text-theme-primary mb-4">Performance Metrics</h3>
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <span className="text-theme-secondary">Average Generation Time</span>
                <span className="font-medium text-theme-primary">{stats.avg_generation_time}s</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-theme-secondary">Storage Used</span>
                <span className="font-medium text-theme-primary">{stats.storage_used}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-theme-secondary">Most Popular Template</span>
                <span className="font-medium text-theme-primary">{stats.most_popular_template}</span>
              </div>
              {stats.failed_reports > 0 && (
                <div className="flex items-center justify-between">
                  <span className="text-theme-secondary">Failed Reports</span>
                  <span className="font-medium text-theme-error">{stats.failed_reports}</span>
                </div>
              )}
            </div>
          </div>

          <div className="bg-theme-surface rounded-lg p-6">
            <h3 className="text-lg font-semibold text-theme-primary mb-4">Quick Actions</h3>
            <div className="space-y-3">
              <button className="w-full flex items-center gap-3 p-3 text-left bg-theme-background rounded-lg hover:bg-theme-surface-hover transition-colors duration-200">
                <FileText className="w-5 h-5 text-theme-interactive-primary" />
                <div>
                  <p className="font-medium text-theme-primary">Create New Report</p>
                  <p className="text-sm text-theme-secondary">Start building a custom report</p>
                </div>
              </button>
              
              <button className="w-full flex items-center gap-3 p-3 text-left bg-theme-background rounded-lg hover:bg-theme-surface-hover transition-colors duration-200">
                <Calendar className="w-5 h-5 text-theme-interactive-primary" />
                <div>
                  <p className="font-medium text-theme-primary">Schedule Report</p>
                  <p className="text-sm text-theme-secondary">Set up automated reporting</p>
                </div>
              </button>
              
              <button className="w-full flex items-center gap-3 p-3 text-left bg-theme-background rounded-lg hover:bg-theme-surface-hover transition-colors duration-200">
                <BarChart3 className="w-5 h-5 text-theme-interactive-primary" />
                <div>
                  <p className="font-medium text-theme-primary">View Analytics</p>
                  <p className="text-sm text-theme-secondary">Analyze reporting trends</p>
                </div>
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Recent Reports */}
      <div className="bg-theme-surface rounded-lg p-6">
        <div className="flex items-center justify-between mb-6">
          <h3 className="text-lg font-semibold text-theme-primary">Recent Reports</h3>
          <button className="text-theme-link hover:text-theme-link-hover text-sm">
            View All
          </button>
        </div>

        {recentReports.length === 0 ? (
          <div className="text-center py-8">
            <FileText className="w-12 h-12 text-theme-secondary mx-auto mb-3" />
            <p className="text-theme-secondary">No recent reports</p>
          </div>
        ) : (
          <div className="space-y-3">
            {recentReports.map((report) => (
              <div key={report.id} className="flex items-center justify-between p-4 bg-theme-background rounded-lg">
                <div className="flex items-center gap-3">
                  {getStatusIcon(report.status)}
                  <div>
                    <p className="font-medium text-theme-primary">{report.name}</p>
                    <p className="text-sm text-theme-secondary">
                      {report.template} • {formatDateTime(report.requested_at)} • {report.requested_by}
                    </p>
                  </div>
                </div>
                
                <div className="flex items-center gap-3">
                  <span className="text-sm text-theme-secondary">
                    {getStatusText(report.status)}
                  </span>
                  {report.status === 'completed' && report.file_size && (
                    <span className="text-sm text-theme-secondary">
                      {report.file_size}
                    </span>
                  )}
                  {report.status === 'completed' && (
                    <button className="p-1 text-theme-link hover:text-theme-link-hover">
                      <Download className="w-4 h-4" />
                    </button>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
        </div>
      </div>
    </PageContainer>
  );
};

export default ReportsOverviewPage;