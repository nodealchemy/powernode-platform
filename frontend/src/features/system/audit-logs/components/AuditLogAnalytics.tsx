import React, { useState } from 'react';
import {
  Shield,
  AlertTriangle,
  Users,
  Activity,
  Eye,
  Calendar,
  RefreshCw
} from 'lucide-react';
import { AuditLogFilters as FilterType } from '@/features/system/audit-logs/services/auditLogsApi';
import { AuditLogChart } from './AuditLogChart';
import { SecurityOverview } from './SecurityOverview';
import { ComplianceMetrics } from './ComplianceMetrics';
import { RiskAssessment } from './RiskAssessment';
import { ActivityHeatmap } from './ActivityHeatmap';
import { TopThreats } from './TopThreats';

import type { ChartData } from './AuditLogChart';
import type { HeatmapDataPoint } from './ActivityHeatmap';

export interface AuditLogMetrics {
  totalEvents: number;
  securityEvents: number;
  failedEvents: number;
  highRiskEvents: number;
  suspiciousEvents: number;
  uniqueUsers: number;
  uniqueIps: number;
}

export interface AuditLogChartDataSet {
  activityTimeline?: ChartData;
  eventDistribution?: ChartData;
  securityEvents?: ChartData;
  complianceEvents?: ChartData;
  riskDistribution?: ChartData;
}

interface AuditLogAnalyticsProps {
  metrics?: Partial<AuditLogMetrics>;
  chartData?: AuditLogChartDataSet;
  heatmapData?: HeatmapDataPoint[];
  loading?: boolean;
  filters: FilterType;
  onFiltersChange: (filters: FilterType) => void;
  refreshData: () => void;
}

interface TimeRange {
  label: string;
  value: string;
  days: number;
}

const timeRanges: TimeRange[] = [
  { label: 'Last 24 Hours', value: '24h', days: 1 },
  { label: 'Last 7 Days', value: '7d', days: 7 },
  { label: 'Last 30 Days', value: '30d', days: 30 },
  { label: 'Last 90 Days', value: '90d', days: 90 }
];

type TabKey = 'overview' | 'security' | 'compliance' | 'risk';

interface AnalyticsTab {
  key: TabKey;
  label: string;
  icon: React.ReactNode;
}

export const AuditLogAnalytics: React.FC<AuditLogAnalyticsProps> = ({
  metrics,
  chartData,
  heatmapData,
  loading: propLoading = false,
  filters,
  onFiltersChange,
  refreshData
}) => {
  const [selectedTimeRange, setSelectedTimeRange] = useState<TimeRange>(timeRanges[1]);
  const [activeTab, setActiveTab] = useState<TabKey>('overview');

  // Handle time range changes
  const handleTimeRangeChange = (timeRange: TimeRange) => {
    setSelectedTimeRange(timeRange);
    const endDate = new Date();
    const startDate = new Date(endDate.getTime() - (timeRange.days * 24 * 60 * 60 * 1000));

    onFiltersChange({
      ...filters,
      date_from: startDate.toISOString().split('T')[0],
      date_to: endDate.toISOString().split('T')[0]
    });
  };

  // Use metrics from props with defaults for display
  const displayMetrics: AuditLogMetrics = {
    totalEvents: metrics?.totalEvents ?? 0,
    securityEvents: metrics?.securityEvents ?? 0,
    failedEvents: metrics?.failedEvents ?? 0,
    highRiskEvents: metrics?.highRiskEvents ?? 0,
    suspiciousEvents: metrics?.suspiciousEvents ?? 0,
    uniqueUsers: metrics?.uniqueUsers ?? 0,
    uniqueIps: metrics?.uniqueIps ?? 0
  };

  const tabs: AnalyticsTab[] = [
    { key: 'overview', label: 'Overview', icon: <Activity className="w-4 h-4" /> },
    { key: 'security', label: 'Security', icon: <Shield className="w-4 h-4" /> },
    { key: 'compliance', label: 'Compliance', icon: <Eye className="w-4 h-4" /> },
    { key: 'risk', label: 'Risk Analysis', icon: <AlertTriangle className="w-4 h-4" /> }
  ];

  return (
    <div className="space-y-6">
      {/* Analytics Header */}
      <div className="bg-theme-surface rounded-lg border border-theme p-6">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div>
            <h2 className="text-xl font-semibold text-theme-primary mb-2">Security Analytics Dashboard</h2>
            <p className="text-theme-secondary">Comprehensive audit log analysis and insights</p>
          </div>
          
          <div className="flex items-center gap-4">
            {/* Time Range Selector */}
            <div className="flex items-center gap-2">
              <Calendar className="w-4 h-4 text-theme-secondary" />
              <select
                value={selectedTimeRange.value}
                onChange={(e) => {
                  const timeRange = timeRanges.find(tr => tr.value === e.target.value);
                  if (timeRange) handleTimeRangeChange(timeRange);
                }}
                className="px-3 py-2 text-sm bg-theme-background border border-theme rounded-md text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-focus focus:border-transparent"
              >
                {timeRanges.map((range) => (
                  <option key={range.value} value={range.value}>
                    {range.label}
                  </option>
                ))}
              </select>
            </div>
            
            <button
              onClick={refreshData}
              disabled={propLoading}
              className="flex items-center gap-2 px-3 py-2 text-sm bg-theme-interactive-primary text-white rounded-md hover:bg-theme-interactive-primary-hover transition-colors duration-200 disabled:opacity-50"
            >
              <RefreshCw className={`w-4 h-4 ${propLoading ? 'animate-spin' : ''}`} />
              Refresh
            </button>
          </div>
        </div>
      </div>

      {/* Tab Navigation */}
      <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
        <div className="border-b border-theme">
          <nav className="flex space-x-8 px-6" aria-label="Analytics tabs">
            {tabs.map((tab) => (
              <button
                key={tab.key}
                onClick={() => setActiveTab(tab.key)}
                className={`flex items-center gap-2 py-4 px-1 border-b-2 font-medium text-sm transition-colors duration-200 ${
                  activeTab === tab.key
                    ? 'border-theme-interactive-primary text-theme-interactive-primary'
                    : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme'
                }`}
              >
                {tab.icon}
                {tab.label}
              </button>
            ))}
          </nav>
        </div>

        {/* Tab Content */}
        <div className="p-6">
          {activeTab === 'overview' && (
            <div className="space-y-6">
              {/* Key Metrics Grid */}
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                <div className="bg-theme-background rounded-lg p-4 border border-theme">
                  <div className="flex items-center justify-between mb-2">
                    <div className="text-sm font-medium text-theme-secondary">Total Events</div>
                    <Activity className="w-4 h-4 text-theme-link" />
                  </div>
                  <div className="text-2xl font-bold text-theme-primary">{displayMetrics.totalEvents.toLocaleString()}</div>
                </div>

                <div className="bg-theme-background rounded-lg p-4 border border-theme">
                  <div className="flex items-center justify-between mb-2">
                    <div className="text-sm font-medium text-theme-secondary">Security Events</div>
                    <Shield className="w-4 h-4 text-theme-status-success" />
                  </div>
                  <div className="text-2xl font-bold text-theme-primary">{displayMetrics.securityEvents}</div>
                </div>

                <div className="bg-theme-background rounded-lg p-4 border border-theme">
                  <div className="flex items-center justify-between mb-2">
                    <div className="text-sm font-medium text-theme-secondary">High Risk</div>
                    <AlertTriangle className="w-4 h-4 text-theme-status-error" />
                  </div>
                  <div className="text-2xl font-bold text-theme-primary">{displayMetrics.highRiskEvents}</div>
                </div>

                <div className="bg-theme-background rounded-lg p-4 border border-theme">
                  <div className="flex items-center justify-between mb-2">
                    <div className="text-sm font-medium text-theme-secondary">Unique Users</div>
                    <Users className="w-4 h-4 text-theme-link" />
                  </div>
                  <div className="text-2xl font-bold text-theme-primary">{displayMetrics.uniqueUsers}</div>
                </div>
              </div>

              {/* Charts */}
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <AuditLogChart
                  title="Activity Timeline"
                  type="line"
                  data={chartData?.activityTimeline || []}
                  timeRange={selectedTimeRange}
                  loading={propLoading}
                />
                <AuditLogChart
                  title="Event Distribution"
                  type="pie"
                  data={chartData?.eventDistribution || []}
                  timeRange={selectedTimeRange}
                  loading={propLoading}
                />
              </div>

              {/* Activity Heatmap */}
              <ActivityHeatmap data={heatmapData || []} loading={propLoading} />
            </div>
          )}

          {activeTab === 'security' && (
            <div className="space-y-6">
              <SecurityOverview metrics={displayMetrics as unknown as Record<string, unknown>} timeRange={selectedTimeRange} />
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <AuditLogChart
                  title="Security Events Over Time"
                  type="line"
                  data={chartData?.securityEvents || []}
                  timeRange={selectedTimeRange}
                  loading={propLoading}
                />
                <TopThreats timeRange={selectedTimeRange} />
              </div>
            </div>
          )}

          {activeTab === 'compliance' && (
            <div className="space-y-6">
              <ComplianceMetrics timeRange={selectedTimeRange} />
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <AuditLogChart
                  title="Compliance Events"
                  type="bar"
                  data={chartData?.complianceEvents || []}
                  timeRange={selectedTimeRange}
                  loading={propLoading}
                />
                <div className="bg-theme-background rounded-lg border border-theme p-6">
                  <h3 className="text-lg font-semibold text-theme-primary mb-4">Regulation Coverage</h3>
                  <div className="space-y-4">
                    <div>
                      <div className="flex items-center justify-between mb-2">
                        <span className="text-sm font-medium text-theme-secondary">GDPR Compliance</span>
                        <span className="text-sm font-semibold text-theme-status-success">98%</span>
                      </div>
                      <div className="w-full bg-theme-background rounded-full h-2">
                        <div className="bg-theme-status-success h-2 rounded-full" style={{ width: '98%' }}></div>
                      </div>
                    </div>
                    <div>
                      <div className="flex items-center justify-between mb-2">
                        <span className="text-sm font-medium text-theme-secondary">CCPA Compliance</span>
                        <span className="text-sm font-semibold text-theme-link">95%</span>
                      </div>
                      <div className="w-full bg-theme-background rounded-full h-2">
                        <div className="bg-theme-link h-2 rounded-full" style={{ width: '95%' }}></div>
                      </div>
                    </div>
                    <div>
                      <div className="flex items-center justify-between mb-2">
                        <span className="text-sm font-medium text-theme-secondary">SOX Compliance</span>
                        <span className="text-sm font-semibold text-theme-status-warning">92%</span>
                      </div>
                      <div className="w-full bg-theme-background rounded-full h-2">
                        <div className="bg-theme-status-warning h-2 rounded-full" style={{ width: '92%' }}></div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          )}

          {activeTab === 'risk' && (
            <div className="space-y-6">
              <RiskAssessment metrics={displayMetrics} timeRange={selectedTimeRange} />
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <AuditLogChart
                  title="Risk Level Distribution"
                  type="doughnut"
                  data={chartData?.riskDistribution || []}
                  timeRange={selectedTimeRange}
                  loading={propLoading}
                />
                <div className="bg-theme-background rounded-lg border border-theme p-6">
                  <h3 className="text-lg font-semibold text-theme-primary mb-4">Risk Recommendations</h3>
                  <div className="space-y-3">
                    <div className="flex items-start gap-3 p-3 bg-theme-status-warning-background rounded-lg border border-theme-status-warning">
                      <AlertTriangle className="w-4 h-4 text-theme-status-warning mt-0.5" />
                      <div>
                        <div className="text-sm font-medium text-theme-status-warning">High Failed Login Rate</div>
                        <div className="text-xs text-theme-status-warning">Consider implementing additional rate limiting</div>
                      </div>
                    </div>
                    <div className="flex items-start gap-3 p-3 bg-theme-link-background rounded-lg border border-theme-link">
                      <Eye className="w-4 h-4 text-theme-link mt-0.5" />
                      <div>
                        <div className="text-sm font-medium text-theme-link">Off-Hours Activity</div>
                        <div className="text-xs text-theme-link">Review admin actions during unusual hours</div>
                      </div>
                    </div>
                    <div className="flex items-start gap-3 p-3 bg-theme-status-success-background rounded-lg border border-theme-status-success">
                      <Shield className="w-4 h-4 text-theme-status-success mt-0.5" />
                      <div>
                        <div className="text-sm font-medium text-theme-status-success">Security Posture Good</div>
                        <div className="text-xs text-theme-status-success">Current security measures are effective</div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};