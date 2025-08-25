import React, { useState, useEffect } from 'react';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { FlexBetween, FlexItemsCenter } from '@/shared/components/ui/FlexContainer';
import { useNotification } from '@/shared/hooks/useNotification';
import { reverseProxyApi, HealthStatus } from '../../services/reverseProxyApi';
import { 
  Heart,
  TrendingUp,
  Clock,
  AlertTriangle,
  CheckCircle,
  XCircle,
  RefreshCw,
  Settings,
  Activity
} from 'lucide-react';

interface HealthMonitoringDashboardProps {
  healthStatus: HealthStatus;
  onRefresh: () => void;
  refreshing: boolean;
}

interface HealthDataPoint {
  timestamp: string;
  status: 'healthy' | 'unhealthy' | 'unreachable';
  response_time: number;
  response_code: number | null;
  error: string | null;
}

interface ServiceHealthHistory {
  service: string;
  timeframe: string;
  data_points: HealthDataPoint[];
}

export const HealthMonitoringDashboard: React.FC<HealthMonitoringDashboardProps> = ({
  healthStatus,
  onRefresh,
  refreshing
}) => {
  const { showNotification } = useNotification();
  const [selectedService, setSelectedService] = useState<string | null>(null);
  const [healthHistory, setHealthHistory] = useState<ServiceHealthHistory | null>(null);
  const [loadingHistory, setLoadingHistory] = useState(false);
  const [timeframe, setTimeframe] = useState<number>(24);
  const [editingHealthConfig, setEditingHealthConfig] = useState<string | null>(null);

  const serviceNames = Object.keys(healthStatus.services || {});

  useEffect(() => {
    if (selectedService && !healthHistory) {
      loadHealthHistory(selectedService, timeframe);
    }
  }, [selectedService]);

  const loadHealthHistory = async (serviceName: string, hours: number) => {
    try {
      setLoadingHistory(true);
      const history = await reverseProxyApi.getServiceHealthHistory(serviceName, hours);
      setHealthHistory(history);
    } catch (error) {
      console.error('Failed to load health history:', error);
      showNotification('Failed to load health history', 'error');
    } finally {
      setLoadingHistory(false);
    }
  };

  const getStatusIcon = (status: string, size: string = 'w-4 h-4') => {
    const className = `${size} mr-2`;
    switch (status) {
      case 'healthy':
        return <CheckCircle className={`${className} text-theme-success`} />;
      case 'unhealthy':
        return <AlertTriangle className={`${className} text-theme-warning`} />;
      case 'unreachable':
        return <XCircle className={`${className} text-theme-danger`} />;
      default:
        return <Heart className={`${className} text-theme-secondary`} />;
    }
  };

  const getStatusBadgeVariant = (status: string) => {
    switch (status) {
      case 'healthy': return 'success';
      case 'unhealthy': return 'warning';
      case 'unreachable': return 'danger';
      default: return 'secondary';
    }
  };

  const calculateUptime = (dataPoints: HealthDataPoint[]): number => {
    if (!dataPoints.length) return 0;
    const healthyPoints = dataPoints.filter(point => point.status === 'healthy').length;
    return Math.round((healthyPoints / dataPoints.length) * 100);
  };

  const calculateAverageResponseTime = (dataPoints: HealthDataPoint[]): number => {
    const healthyPoints = dataPoints.filter(point => point.status === 'healthy' && point.response_time > 0);
    if (!healthyPoints.length) return 0;
    const total = healthyPoints.reduce((sum, point) => sum + point.response_time, 0);
    return Math.round(total / healthyPoints.length);
  };

  const formatResponseTime = (ms: number): string => {
    if (ms < 1000) return `${ms}ms`;
    return `${(ms / 1000).toFixed(1)}s`;
  };

  return (
    <div className="space-y-6">
      {/* Overall Status Header */}
      <Card className="p-6">
        <FlexBetween>
          <FlexItemsCenter>
            {getStatusIcon(healthStatus.overall_status, 'w-6 h-6')}
            <div>
              <h2 className="text-xl font-semibold text-theme-primary">
                System Health Overview
              </h2>
              <p className="text-sm text-theme-secondary">
                Environment: {healthStatus.environment} • Last checked: {' '}
                {new Date(healthStatus.last_checked).toLocaleTimeString()}
              </p>
            </div>
          </FlexItemsCenter>
          <div className="flex items-center space-x-3">
            <Badge variant={getStatusBadgeVariant(healthStatus.overall_status)} size="lg">
              {healthStatus.overall_status.toUpperCase()}
            </Badge>
            <Button
              onClick={onRefresh}
              variant="secondary"
              size="sm"
              disabled={refreshing}
            >
              {refreshing ? (
                <LoadingSpinner size="sm" />
              ) : (
                <RefreshCw className="w-4 h-4" />
              )}
            </Button>
          </div>
        </FlexBetween>
      </Card>

      {/* Services Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {serviceNames.map((serviceName) => {
          const service = healthStatus.services[serviceName];
          return (
            <Card 
              key={serviceName} 
              className={`p-4 cursor-pointer transition-all hover:shadow-lg ${
                selectedService === serviceName 
                  ? 'border-theme-primary shadow-lg' 
                  : 'border-theme hover:border-theme-primary/50'
              }`}
              onClick={() => {
                setSelectedService(serviceName);
                setHealthHistory(null);
              }}
            >
              <FlexBetween className="mb-3">
                <FlexItemsCenter>
                  {getStatusIcon(service.status)}
                  <h3 className="font-medium text-theme-primary capitalize">
                    {serviceName.replace(/_/g, ' ')}
                  </h3>
                </FlexItemsCenter>
                <Badge variant={getStatusBadgeVariant(service.status)}>
                  {service.status}
                </Badge>
              </FlexBetween>

              <div className="space-y-2 text-sm">
                {service.url && (
                  <div className="flex justify-between">
                    <span className="text-theme-secondary">URL:</span>
                    <span className="text-theme-primary text-xs">{service.url}</span>
                  </div>
                )}
                {service.response_code && (
                  <div className="flex justify-between">
                    <span className="text-theme-secondary">Status:</span>
                    <span className="text-theme-primary">{service.response_code}</span>
                  </div>
                )}
                {service.response_time && (
                  <div className="flex justify-between">
                    <span className="text-theme-secondary">Response:</span>
                    <span className="text-theme-primary">
                      {formatResponseTime(service.response_time)}
                    </span>
                  </div>
                )}
                {service.error && (
                  <div className="text-theme-danger text-xs mt-2 p-2 bg-theme-danger/10 rounded">
                    {service.error}
                  </div>
                )}
              </div>
            </Card>
          );
        })}
      </div>

      {/* Detailed Service View */}
      {selectedService && (
        <Card className="p-6">
          <FlexBetween className="mb-6">
            <div>
              <h3 className="text-lg font-semibold text-theme-primary flex items-center">
                {getStatusIcon(healthStatus.services[selectedService].status)}
                {selectedService.replace(/_/g, ' ').toUpperCase()} Health Details
              </h3>
              <p className="text-sm text-theme-secondary">
                Detailed health monitoring and historical data
              </p>
            </div>
            <div className="flex items-center space-x-2">
              <select
                value={timeframe}
                onChange={(e) => {
                  const hours = parseInt(e.target.value);
                  setTimeframe(hours);
                  loadHealthHistory(selectedService, hours);
                }}
                className="p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
              >
                <option value={1}>Last Hour</option>
                <option value={6}>Last 6 Hours</option>
                <option value={24}>Last 24 Hours</option>
                <option value={168}>Last Week</option>
              </select>
              <Button
                onClick={() => setEditingHealthConfig(selectedService)}
                variant="secondary"
                size="sm"
              >
                <Settings className="w-4 h-4 mr-2" />
                Configure
              </Button>
            </div>
          </FlexBetween>

          {loadingHistory ? (
            <div className="flex justify-center py-8">
              <LoadingSpinner size="lg" />
            </div>
          ) : healthHistory ? (
            <div className="space-y-6">
              {/* Health Metrics */}
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <Card className="p-4 bg-theme-success/10 border-theme-success/20">
                  <FlexItemsCenter className="mb-2">
                    <TrendingUp className="w-5 h-5 text-theme-success mr-2" />
                    <h4 className="font-medium text-theme-success">Uptime</h4>
                  </FlexItemsCenter>
                  <p className="text-2xl font-bold text-theme-success">
                    {calculateUptime(healthHistory.data_points)}%
                  </p>
                  <p className="text-sm text-theme-secondary">
                    {healthHistory.timeframe}
                  </p>
                </Card>

                <Card className="p-4 bg-theme-primary/10 border-theme-primary/20">
                  <FlexItemsCenter className="mb-2">
                    <Clock className="w-5 h-5 text-theme-primary mr-2" />
                    <h4 className="font-medium text-theme-primary">Avg Response</h4>
                  </FlexItemsCenter>
                  <p className="text-2xl font-bold text-theme-primary">
                    {formatResponseTime(calculateAverageResponseTime(healthHistory.data_points))}
                  </p>
                  <p className="text-sm text-theme-secondary">
                    Average response time
                  </p>
                </Card>

                <Card className="p-4 bg-theme-warning/10 border-theme-warning/20">
                  <FlexItemsCenter className="mb-2">
                    <Activity className="w-5 h-5 text-theme-warning mr-2" />
                    <h4 className="font-medium text-theme-warning">Data Points</h4>
                  </FlexItemsCenter>
                  <p className="text-2xl font-bold text-theme-warning">
                    {healthHistory.data_points.length}
                  </p>
                  <p className="text-sm text-theme-secondary">
                    Health checks recorded
                  </p>
                </Card>
              </div>

              {/* Recent Events */}
              <div>
                <h4 className="font-medium text-theme-primary mb-3">Recent Health Events</h4>
                <div className="space-y-2 max-h-64 overflow-y-auto">
                  {healthHistory.data_points
                    .slice()
                    .reverse()
                    .slice(0, 20)
                    .map((point, index) => (
                      <div 
                        key={index} 
                        className="flex items-center justify-between p-3 bg-theme-surface rounded-lg border border-theme"
                      >
                        <FlexItemsCenter>
                          {getStatusIcon(point.status)}
                          <div>
                            <span className="text-sm font-medium text-theme-primary">
                              {point.status.toUpperCase()}
                            </span>
                            <p className="text-xs text-theme-secondary">
                              {new Date(point.timestamp).toLocaleString()}
                            </p>
                          </div>
                        </FlexItemsCenter>
                        <div className="text-right">
                          {point.response_code && (
                            <p className="text-sm text-theme-primary">
                              HTTP {point.response_code}
                            </p>
                          )}
                          <p className="text-xs text-theme-secondary">
                            {point.response_time > 0 ? formatResponseTime(point.response_time) : 'N/A'}
                          </p>
                        </div>
                      </div>
                    ))}
                </div>
              </div>
            </div>
          ) : (
            <div className="text-center py-8">
              <Heart className="w-12 h-12 mx-auto mb-4 text-theme-secondary" />
              <p className="text-theme-secondary">
                Loading health history for {selectedService}...
              </p>
            </div>
          )}
        </Card>
      )}

      {/* Health Check Configuration Modal would go here */}
      {editingHealthConfig && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <Card className="w-full max-w-md p-6 m-4">
            <h3 className="text-lg font-semibold text-theme-primary mb-4">
              Configure Health Checks - {editingHealthConfig}
            </h3>
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Check Interval (seconds)
                </label>
                <input
                  type="number"
                  defaultValue={30}
                  className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                  min="10"
                  max="3600"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Timeout (seconds)
                </label>
                <input
                  type="number"
                  defaultValue={10}
                  className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                  min="1"
                  max="60"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Health Check Path
                </label>
                <input
                  type="text"
                  defaultValue="/health"
                  className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                  placeholder="/health"
                />
              </div>
            </div>
            <div className="flex justify-end space-x-3 mt-6">
              <Button
                onClick={() => setEditingHealthConfig(null)}
                variant="secondary"
              >
                Cancel
              </Button>
              <Button
                onClick={() => {
                  showNotification('Health check configuration updated', 'success');
                  setEditingHealthConfig(null);
                }}
                variant="primary"
              >
                Save Config
              </Button>
            </div>
          </Card>
        </div>
      )}
    </div>
  );
};