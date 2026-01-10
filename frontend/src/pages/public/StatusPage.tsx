import React, { useState, useEffect, useCallback } from 'react';
import { Link } from 'react-router-dom';
import {
  CheckCircleIcon,
  ExclamationTriangleIcon,
  XCircleIcon,
  ArrowPathIcon,
  ClockIcon,
} from '@heroicons/react/24/outline';
import { statusApi, SystemStatus, StatusHistory } from '@/features/status';

const STATUS_ICONS: Record<string, React.ElementType> = {
  operational: CheckCircleIcon,
  degraded: ExclamationTriangleIcon,
  partial_outage: ExclamationTriangleIcon,
  major_outage: XCircleIcon,
};

export const StatusPage: React.FC = () => {
  const [status, setStatus] = useState<SystemStatus | null>(null);
  const [history, setHistory] = useState<StatusHistory | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [lastRefresh, setLastRefresh] = useState<Date>(new Date());

  const loadStatus = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [statusResponse, historyResponse] = await Promise.all([
        statusApi.getStatus(),
        statusApi.getHistory(),
      ]);

      if (statusResponse.success && statusResponse.data) {
        setStatus(statusResponse.data);
      } else {
        setError(statusResponse.error || 'Failed to load status');
      }

      if (historyResponse.success && historyResponse.data) {
        setHistory(historyResponse.data);
      }

      setLastRefresh(new Date());
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadStatus();

    // Auto-refresh every 60 seconds
    const interval = setInterval(loadStatus, 60000);
    return () => clearInterval(interval);
  }, [loadStatus]);

  const formatTime = (dateString: string) => {
    const date = new Date(dateString);
    return date.toLocaleString();
  };

  const formatRelativeTime = (dateString: string) => {
    const date = new Date(dateString);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMins = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMins / 60);

    if (diffMins < 1) return 'Just now';
    if (diffMins < 60) return `${diffMins} minutes ago`;
    if (diffHours < 24) return `${diffHours} hours ago`;
    return date.toLocaleDateString();
  };

  const StatusIcon = status?.overall_status
    ? STATUS_ICONS[status.overall_status]
    : CheckCircleIcon;

  return (
    <div className="min-h-screen bg-theme-background">
      {/* Header */}
      <header className="bg-theme-surface border-b border-theme">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-3">
              <Link to="/" className="text-2xl font-bold text-theme-primary">
                Powernode
              </Link>
              <span className="text-theme-tertiary">|</span>
              <span className="text-lg text-theme-secondary">System Status</span>
            </div>
            <button
              onClick={loadStatus}
              disabled={loading}
              className="flex items-center gap-2 px-4 py-2 text-sm text-theme-secondary hover:text-theme-primary transition-colors"
            >
              <ArrowPathIcon className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
              Refresh
            </button>
          </div>
        </div>
      </header>

      <main className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {error ? (
          <div className="bg-theme-danger/10 border border-theme-danger rounded-lg p-6 text-center">
            <XCircleIcon className="w-12 h-12 text-theme-danger mx-auto mb-4" />
            <h2 className="text-lg font-semibold text-theme-danger mb-2">
              Unable to Load Status
            </h2>
            <p className="text-theme-danger mb-4">{error}</p>
            <button
              onClick={loadStatus}
              className="px-4 py-2 bg-theme-danger text-white rounded-lg hover:bg-theme-danger transition-colors"
            >
              Try Again
            </button>
          </div>
        ) : (
          <>
            {/* Overall Status Banner */}
            <div
              className={`rounded-xl p-8 mb-8 ${statusApi.getStatusBgColor(
                status?.overall_status || 'operational'
              )}`}
            >
              <div className="flex items-center justify-center">
                <StatusIcon
                  className={`w-12 h-12 mr-4 ${statusApi.getStatusTextColor(
                    status?.overall_status || 'operational'
                  )}`}
                />
                <div>
                  <h1
                    className={`text-2xl font-bold ${statusApi.getStatusTextColor(
                      status?.overall_status || 'operational'
                    )}`}
                  >
                    {statusApi.getStatusLabel(status?.overall_status || 'operational')}
                  </h1>
                  <p className="text-sm text-theme-secondary mt-1">
                    Last updated: {formatRelativeTime(status?.last_updated || new Date().toISOString())}
                  </p>
                </div>
              </div>
            </div>

            {/* Uptime Summary */}
            {status?.uptime && (
              <div className="bg-theme-surface rounded-lg border border-theme p-6 mb-8">
                <h2 className="text-lg font-semibold text-theme-primary mb-4">Uptime</h2>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                  <div className="text-center">
                    <div className="text-2xl font-bold text-theme-primary">
                      {status.uptime.last_24_hours.toFixed(2)}%
                    </div>
                    <div className="text-sm text-theme-secondary">Last 24 hours</div>
                  </div>
                  <div className="text-center">
                    <div className="text-2xl font-bold text-theme-primary">
                      {status.uptime.last_7_days.toFixed(2)}%
                    </div>
                    <div className="text-sm text-theme-secondary">Last 7 days</div>
                  </div>
                  <div className="text-center">
                    <div className="text-2xl font-bold text-theme-primary">
                      {status.uptime.last_30_days.toFixed(2)}%
                    </div>
                    <div className="text-sm text-theme-secondary">Last 30 days</div>
                  </div>
                  <div className="text-center">
                    <div className="text-2xl font-bold text-theme-primary">
                      {status.uptime.last_90_days.toFixed(2)}%
                    </div>
                    <div className="text-sm text-theme-secondary">Last 90 days</div>
                  </div>
                </div>
              </div>
            )}

            {/* Active Incidents */}
            {status?.incidents && status.incidents.length > 0 && (
              <div className="bg-theme-surface rounded-lg border border-theme p-6 mb-8">
                <h2 className="text-lg font-semibold text-theme-primary mb-4">Active Incidents</h2>
                <div className="space-y-4">
                  {status.incidents.map((incident) => (
                    <div
                      key={incident.id}
                      className="border-l-4 border-theme-warning bg-theme-warning/10 p-4 rounded-r-lg"
                    >
                      <div className="flex items-start justify-between">
                        <div>
                          <h3 className="font-medium text-theme-primary">{incident.title}</h3>
                          <p className="text-sm text-theme-secondary mt-1">
                            Status: {statusApi.getIncidentStatusLabel(incident.status)}
                          </p>
                        </div>
                        <span
                          className={`text-sm font-medium ${statusApi.getIncidentImpactColor(
                            incident.impact
                          )}`}
                        >
                          {incident.impact.toUpperCase()}
                        </span>
                      </div>
                      <div className="flex items-center text-xs text-theme-tertiary mt-2">
                        <ClockIcon className="w-4 h-4 mr-1" />
                        Started: {formatTime(incident.started_at)}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Component Status */}
            <div className="bg-theme-surface rounded-lg border border-theme p-6 mb-8">
              <h2 className="text-lg font-semibold text-theme-primary mb-4">System Components</h2>
              <div className="space-y-3">
                {status?.components &&
                  Object.entries(status.components).map(([key, component]) => {
                    const ComponentIcon =
                      STATUS_ICONS[component.status] || CheckCircleIcon;
                    return (
                      <div
                        key={key}
                        className="flex items-center justify-between p-4 bg-theme-background rounded-lg"
                      >
                        <div className="flex items-center">
                          <ComponentIcon
                            className={`w-5 h-5 mr-3 ${statusApi.getStatusTextColor(
                              component.status
                            )}`}
                          />
                          <div>
                            <div className="font-medium text-theme-primary">{component.name}</div>
                            <div className="text-sm text-theme-tertiary">{component.description}</div>
                          </div>
                        </div>
                        <div className="flex items-center">
                          {component.response_time !== null && (
                            <span className="text-sm text-theme-secondary mr-4">
                              {component.response_time}ms
                            </span>
                          )}
                          <span
                            className={`px-3 py-1 rounded-full text-xs font-medium ${statusApi.getStatusBgColor(
                              component.status
                            )} ${statusApi.getStatusTextColor(component.status)}`}
                          >
                            {component.status === 'operational' ? 'Operational' : component.status.replace('_', ' ')}
                          </span>
                        </div>
                      </div>
                    );
                  })}
              </div>
            </div>

            {/* Uptime History Chart */}
            {history?.daily_status && (
              <div className="bg-theme-surface rounded-lg border border-theme p-6 mb-8">
                <h2 className="text-lg font-semibold text-theme-primary mb-4">
                  30-Day Uptime History
                </h2>
                <div className="flex items-center justify-between mb-4">
                  <span className="text-sm text-theme-secondary">
                    {history.uptime_percentage.toFixed(2)}% uptime
                  </span>
                  <span className="text-sm text-theme-secondary">
                    {history.incidents_count} incidents
                  </span>
                </div>
                <div className="flex gap-1">
                  {history.daily_status.map((day, index) => (
                    <div
                      key={index}
                      className={`flex-1 h-8 rounded ${statusApi.getStatusColor(
                        day.status
                      )}`}
                      title={`${day.date}: ${day.uptime_percentage.toFixed(2)}% uptime - ${day.status}`}
                    />
                  ))}
                </div>
                <div className="flex justify-between mt-2 text-xs text-theme-tertiary">
                  <span>30 days ago</span>
                  <span>Today</span>
                </div>
              </div>
            )}

            {/* Legend */}
            <div className="bg-theme-surface rounded-lg border border-theme p-6">
              <h2 className="text-lg font-semibold text-theme-primary mb-4">Status Legend</h2>
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                <div className="flex items-center">
                  <div className="w-4 h-4 rounded bg-theme-success mr-2" />
                  <span className="text-sm text-theme-secondary">Operational</span>
                </div>
                <div className="flex items-center">
                  <div className="w-4 h-4 rounded bg-theme-warning mr-2" />
                  <span className="text-sm text-theme-secondary">Degraded</span>
                </div>
                <div className="flex items-center">
                  <div className="w-4 h-4 rounded bg-theme-warning mr-2" />
                  <span className="text-sm text-theme-secondary">Partial Outage</span>
                </div>
                <div className="flex items-center">
                  <div className="w-4 h-4 rounded bg-theme-danger mr-2" />
                  <span className="text-sm text-theme-secondary">Major Outage</span>
                </div>
              </div>
            </div>
          </>
        )}

        {/* Footer */}
        <footer className="mt-12 pt-8 border-t border-theme text-center">
          <p className="text-sm text-theme-tertiary">
            Status page powered by Powernode. Last checked:{' '}
            {lastRefresh.toLocaleTimeString()}
          </p>
          <div className="mt-4 space-x-4">
            <Link to="/" className="text-sm text-theme-secondary hover:text-theme-primary">
              Home
            </Link>
            <Link to="/login" className="text-sm text-theme-secondary hover:text-theme-primary">
              Sign In
            </Link>
          </div>
        </footer>
      </main>
    </div>
  );
};

export default StatusPage;
