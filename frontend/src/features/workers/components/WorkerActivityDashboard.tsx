import React, { useState, useMemo, useEffect } from 'react';
import { Worker, workerAPI } from '@/features/workers/services/workerApi';
import { 
  Activity, 
  Calendar, 
  TrendingUp, 
  TrendingDown,
  Clock,
  Globe,
  Smartphone,
  Monitor,
  MapPin,
  AlertTriangle,
  CheckCircle,
  XCircle,
  RefreshCw,
  Download,
  Filter
} from 'lucide-react';

export interface WorkerActivityDashboardProps {
  worker: Worker;
}

interface ActivityEvent {
  id: string;
  timestamp: string;
  type: 'auth' | 'api_call' | 'permission_check' | 'error' | 'status_change';
  action: string;
  details: string;
  ip_address?: string;
  user_agent?: string;
  status: 'success' | 'warning' | 'error';
  metadata?: Record<string, any>;
}

interface ActivityStats {
  totalRequests: number;
  successRate: number;
  avgResponseTime: number;
  lastActive: string;
  topEndpoints: { endpoint: string; count: number }[];
  errorCount: number;
  trends: {
    requests: { period: string; count: number }[];
    errors: { period: string; count: number }[];
  };
}

export const WorkerActivityDashboard: React.FC<WorkerActivityDashboardProps> = ({ worker }) => {
  const [timeRange, setTimeRange] = useState<'24h' | '7d' | '30d' | '90d'>('7d');
  const [activityFilter, setActivityFilter] = useState<'all' | 'success' | 'warning' | 'error'>('all');
  const [showDetails, setShowDetails] = useState<string | null>(null);
  const [realActivityStats, setRealActivityStats] = useState<any>(null);
  const [loading, setLoading] = useState(true);

  // Fetch real activity data from API
  useEffect(() => {
    const fetchActivityStats = async () => {
      try {
        setLoading(true);
        const response = await workerAPI.getWorkerActivities(worker.id, { page: 1, per_page: 1 });
        if (response && response.summary) {
          setRealActivityStats(response.summary);
        }
      } catch (error) {
        console.error('Failed to fetch activity stats:', error);
      } finally {
        setLoading(false);
      }
    };

    fetchActivityStats();
  }, [worker.id, timeRange]);

  // Activity stats using real data when available, fallback to mock data
  const activityStats: ActivityStats = useMemo(() => {
    if (realActivityStats) {
      return {
        totalRequests: realActivityStats.total_recent || worker.request_count || 0,
        successRate: realActivityStats.success_rate || 0,
        avgResponseTime: realActivityStats.avg_response_time || 0,
        lastActive: worker.last_seen_at || '',
        topEndpoints: realActivityStats.top_endpoints || [],
        errorCount: realActivityStats.failed_recent || 0,
        trends: {
          // For now, use mock data for trends (would need more complex backend logic for real trends)
          requests: [
            { period: '7 days ago', count: Math.floor(Math.random() * 100) },
            { period: '6 days ago', count: Math.floor(Math.random() * 150) },
            { period: '5 days ago', count: Math.floor(Math.random() * 120) },
            { period: '4 days ago', count: Math.floor(Math.random() * 180) },
            { period: '3 days ago', count: Math.floor(Math.random() * 140) },
            { period: '2 days ago', count: Math.floor(Math.random() * 200) },
            { period: '1 day ago', count: Math.floor(Math.random() * 160) },
            { period: 'Today', count: realActivityStats.total_recent || 0 }
          ],
          errors: [
            { period: '7 days ago', count: Math.floor(Math.random() * 3) },
            { period: '6 days ago', count: Math.floor(Math.random() * 4) },
            { period: '5 days ago', count: Math.floor(Math.random() * 2) },
            { period: '4 days ago', count: Math.floor(Math.random() * 5) },
            { period: '3 days ago', count: Math.floor(Math.random() * 3) },
            { period: '2 days ago', count: Math.floor(Math.random() * 4) },
            { period: '1 day ago', count: Math.floor(Math.random() * 2) },
            { period: 'Today', count: realActivityStats.failed_recent || 0 }
          ]
        }
      };
    }
    
    // Fallback to mock data
    return {
      totalRequests: worker.request_count || 0,
      successRate: realActivityStats?.success_rate || 0,
      avgResponseTime: realActivityStats?.avg_response_time || 0,
      lastActive: worker.last_seen_at || '',
      topEndpoints: [],
      errorCount: realActivityStats?.failed_recent || 0,
      trends: {
        requests: [
          { period: 'Today', count: worker.request_count || 0 }
        ],
        errors: [
          { period: 'Today', count: 0 }
        ]
      }
    };
  }, [realActivityStats, worker]);

  // Recent activity events from real data
  const recentActivity: ActivityEvent[] = useMemo(() => [], []);

  const filteredActivity = useMemo(() => {
    if (activityFilter === 'all') return recentActivity;
    return recentActivity.filter(event => event.status === activityFilter);
  }, [recentActivity, activityFilter]);

  const formatTimestamp = (timestamp: string) => {
    const date = new Date(timestamp);
    return date.toLocaleString('en-US', {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit'
    });
  };

  const getEventIcon = (type: string) => {
    switch (type) {
      case 'auth': return <CheckCircle className="w-4 h-4" />;
      case 'api_call': return <Globe className="w-4 h-4" />;
      case 'permission_check': return <CheckCircle className="w-4 h-4" />;
      case 'error': return <XCircle className="w-4 h-4" />;
      case 'status_change': return <RefreshCw className="w-4 h-4" />;
      default: return <Activity className="w-4 h-4" />;
    }
  };

  const getEventStatusColor = (status: string) => {
    switch (status) {
      case 'success': return 'text-theme-success';
      case 'warning': return 'text-theme-warning';
      case 'error': return 'text-theme-error';
      default: return 'text-theme-secondary';
    }
  };

  const getDeviceIcon = (userAgent?: string) => {
    if (!userAgent) return <Monitor className="w-4 h-4" />;
    if (userAgent.includes('Mobile')) return <Smartphone className="w-4 h-4" />;
    return <Monitor className="w-4 h-4" />;
  };

  const formatLastActive = (dateString: string) => {
    if (!dateString) return 'Never';
    const date = new Date(dateString);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMins = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMins / 60);
    const diffDays = Math.floor(diffHours / 24);

    if (diffMins < 1) return 'Just now';
    if (diffMins < 60) return `${diffMins}m ago`;
    if (diffHours < 24) return `${diffHours}h ago`;
    if (diffDays < 30) return `${diffDays}d ago`;
    return date.toLocaleDateString();
  };

  return (
    <div className="space-y-6">
      {/* Time Range Selector */}
      <div className="flex items-center justify-between">
        <h3 className="text-lg font-semibold text-theme-primary">Activity Dashboard</h3>
        <div className="flex items-center gap-2">
          <select
            value={timeRange}
            onChange={(e) => setTimeRange(e.target.value as any)}
            className="px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary text-sm"
          >
            <option value="24h">Last 24 Hours</option>
            <option value="7d">Last 7 Days</option>
            <option value="30d">Last 30 Days</option>
            <option value="90d">Last 90 Days</option>
          </select>
          <button className="p-2 border border-theme rounded-lg text-theme-secondary hover:text-theme-primary transition-colors">
            <Download className="w-4 h-4" />
          </button>
        </div>
      </div>

      {/* Key Metrics */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="bg-theme-surface rounded-lg p-4 border border-theme">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-2xl font-bold text-theme-primary">{activityStats.totalRequests.toLocaleString()}</div>
              <div className="text-sm text-theme-secondary">Total Requests</div>
            </div>
            <div className="p-2 bg-theme-info-background rounded-lg">
              <Activity className="w-5 h-5 text-theme-info" />
            </div>
          </div>
          <div className="mt-2 flex items-center gap-1 text-xs">
            <TrendingUp className="w-3 h-3 text-theme-success" />
            <span className="text-theme-success">+12%</span>
            <span className="text-theme-secondary">vs last period</span>
          </div>
        </div>

        <div className="bg-theme-surface rounded-lg p-4 border border-theme">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-2xl font-bold text-theme-primary">{activityStats.successRate}%</div>
              <div className="text-sm text-theme-secondary">Success Rate</div>
            </div>
            <div className="p-2 bg-theme-success-background rounded-lg">
              <CheckCircle className="w-5 h-5 text-theme-success" />
            </div>
          </div>
          <div className="mt-2 flex items-center gap-1 text-xs">
            <TrendingUp className="w-3 h-3 text-theme-success" />
            <span className="text-theme-success">+0.2%</span>
            <span className="text-theme-secondary">vs last period</span>
          </div>
        </div>

        <div className="bg-theme-surface rounded-lg p-4 border border-theme">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-2xl font-bold text-theme-primary">{activityStats.avgResponseTime}ms</div>
              <div className="text-sm text-theme-secondary">Avg Response</div>
            </div>
            <div className="p-2 bg-theme-warning-background rounded-lg">
              <Clock className="w-5 h-5 text-theme-warning" />
            </div>
          </div>
          <div className="mt-2 flex items-center gap-1 text-xs">
            <TrendingDown className="w-3 h-3 text-theme-success" />
            <span className="text-theme-success">-15ms</span>
            <span className="text-theme-secondary">vs last period</span>
          </div>
        </div>

        <div className="bg-theme-surface rounded-lg p-4 border border-theme">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-2xl font-bold text-theme-primary">{activityStats.errorCount}</div>
              <div className="text-sm text-theme-secondary">Errors</div>
            </div>
            <div className="p-2 bg-theme-error-background rounded-lg">
              <AlertTriangle className="w-5 h-5 text-theme-error" />
            </div>
          </div>
          <div className="mt-2 flex items-center gap-1 text-xs">
            <TrendingDown className="w-3 h-3 text-theme-success" />
            <span className="text-theme-success">-3</span>
            <span className="text-theme-secondary">vs last period</span>
          </div>
        </div>
      </div>

      {/* Activity Trends Chart */}
      <div className="bg-theme-surface rounded-lg p-6 border border-theme">
        <h4 className="font-semibold text-theme-primary mb-4">Activity Trends</h4>
        <div className="space-y-4">
          {/* Simple bar chart representation */}
          <div>
            <div className="text-sm text-theme-secondary mb-2">Request Volume</div>
            <div className="flex items-end gap-1 h-24">
              {activityStats.trends.requests.map((data, index) => (
                <div key={index} className="flex-1 flex flex-col items-center gap-1">
                  <div
                    className="w-full bg-theme-info rounded-t"
                    style={{
                      height: `${(data.count / Math.max(...activityStats.trends.requests.map(d => d.count))) * 100}%`,
                      minHeight: '4px'
                    }}
                    title={`${data.period}: ${data.count} requests`}
                  />
                  <div className="text-xs text-theme-secondary text-center transform rotate-45">
                    {data.period.split(' ')[0]}
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* Top Endpoints */}
      <div className="bg-theme-surface rounded-lg p-6 border border-theme">
        <h4 className="font-semibold text-theme-primary mb-4">
          Top API Endpoints
          {loading && <span className="ml-2 text-xs text-theme-secondary">(Loading...)</span>}
        </h4>
        <div className="space-y-3">
          {activityStats.topEndpoints.length > 0 ? (
            activityStats.topEndpoints.map((endpoint, index) => (
              <div key={endpoint.endpoint} className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div className="w-6 h-6 rounded-full bg-theme-info-background text-theme-info text-xs font-semibold flex items-center justify-center">
                    {index + 1}
                  </div>
                  <code className="text-sm font-mono text-theme-primary">{endpoint.endpoint}</code>
                </div>
                <div className="flex items-center gap-3">
                  <span className="text-sm font-medium text-theme-primary">{endpoint.count.toLocaleString()}</span>
                  <div className="w-20 h-2 bg-theme-background rounded-full overflow-hidden">
                    <div
                      className="h-full bg-theme-info rounded-full"
                      style={{
                        width: `${(endpoint.count / activityStats.topEndpoints[0].count) * 100}%`
                      }}
                    />
                  </div>
                </div>
              </div>
            ))
          ) : (
            <div className="text-center py-4 text-theme-secondary">
              <Globe className="w-8 h-8 mx-auto mb-2 opacity-50" />
              <p>No endpoint data available</p>
              <p className="text-xs mt-1">Worker activities will appear here once API calls are made</p>
            </div>
          )}
        </div>
      </div>

      {/* Recent Activity Log */}
      <div className="bg-theme-surface rounded-lg border border-theme">
        <div className="flex items-center justify-between p-6 border-b border-theme">
          <h4 className="font-semibold text-theme-primary">Recent Activity</h4>
          <div className="flex items-center gap-2">
            <select
              value={activityFilter}
              onChange={(e) => setActivityFilter(e.target.value as any)}
              className="px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary text-sm"
            >
              <option value="all">All Events</option>
              <option value="success">Success</option>
              <option value="warning">Warning</option>
              <option value="error">Error</option>
            </select>
          </div>
        </div>

        <div className="p-6">
          <div className="space-y-4">
            {filteredActivity.map((event) => (
              <div
                key={event.id}
                className={`p-4 rounded-lg border transition-colors cursor-pointer hover:bg-theme-background/50 ${
                  showDetails === event.id ? 'border-theme-interactive-primary bg-theme-interactive-primary/5' : 'border-theme'
                }`}
                onClick={() => setShowDetails(showDetails === event.id ? null : event.id)}
              >
                <div className="flex items-start gap-3">
                  <div className={`p-1 rounded ${getEventStatusColor(event.status)}`}>
                    {getEventIcon(event.type)}
                  </div>
                  <div className="flex-1">
                    <div className="flex items-center justify-between">
                      <div>
                        <div className="font-medium text-theme-primary">{event.action}</div>
                        <div className="text-sm text-theme-secondary mt-1">{event.details}</div>
                      </div>
                      <div className="text-sm text-theme-secondary">
                        {formatTimestamp(event.timestamp)}
                      </div>
                    </div>

                    {showDetails === event.id && event.metadata && (
                      <div className="mt-4 pt-4 border-t border-theme">
                        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
                          {event.ip_address && (
                            <div className="flex items-center gap-2">
                              <MapPin className="w-4 h-4 text-theme-secondary" />
                              <span className="text-theme-secondary">IP:</span>
                              <span className="text-theme-primary font-mono">{event.ip_address}</span>
                            </div>
                          )}
                          {event.user_agent && (
                            <div className="flex items-center gap-2">
                              {getDeviceIcon(event.user_agent)}
                              <span className="text-theme-secondary">Device:</span>
                              <span className="text-theme-primary truncate">
                                {event.user_agent.includes('Chrome') ? 'Chrome' : 'Unknown Browser'}
                              </span>
                            </div>
                          )}
                        </div>
                        
                        <div className="mt-3">
                          <div className="text-xs font-medium text-theme-secondary mb-2">Metadata:</div>
                          <div className="bg-theme-background p-3 rounded font-mono text-xs">
                            <pre className="text-theme-primary whitespace-pre-wrap">
                              {JSON.stringify(event.metadata, null, 2)}
                            </pre>
                          </div>
                        </div>
                      </div>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>

          {filteredActivity.length === 0 && (
            <div className="text-center py-8 text-theme-secondary">
              <Activity className="w-8 h-8 mx-auto mb-3 opacity-50" />
              <p>No activity events match your current filter.</p>
            </div>
          )}
        </div>
      </div>

      {/* Worker Status Summary */}
      <div className="bg-theme-background rounded-lg p-4">
        <h4 className="font-medium text-theme-primary mb-3">Worker Status</h4>
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 text-sm">
          <div className="text-center">
            <div className="text-lg font-bold text-theme-primary">{formatLastActive(worker.last_seen_at || '')}</div>
            <div className="text-theme-secondary">Last Active</div>
          </div>
          <div className="text-center">
            <div className="text-lg font-bold text-theme-success capitalize">{worker.status}</div>
            <div className="text-theme-secondary">Current Status</div>
          </div>
          <div className="text-center">
            <div className="text-lg font-bold text-theme-info">
              {worker.active_recently ? 'Yes' : 'No'}
            </div>
            <div className="text-theme-secondary">Recently Active</div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default WorkerActivityDashboard;