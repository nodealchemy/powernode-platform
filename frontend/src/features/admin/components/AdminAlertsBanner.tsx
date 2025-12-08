import React, { useState, useEffect } from 'react';
import {
  AlertTriangle,
  X,
  ChevronRight,
  Bell,
  Shield,
  AlertCircle,
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { performanceApi, PerformanceAlert } from '@/shared/services/performanceApi';

interface AdminAlertsBannerProps {
  maxAlerts?: number;
  onViewAll?: () => void;
  className?: string;
}

export const AdminAlertsBanner: React.FC<AdminAlertsBannerProps> = ({
  maxAlerts = 3,
  onViewAll,
  className = '',
}) => {
  const [alerts, setAlerts] = useState<PerformanceAlert[]>([]);
  const [dismissedAlerts, setDismissedAlerts] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadAlerts();
  }, []);

  const loadAlerts = async () => {
    try {
      const response = await performanceApi.getActiveAlerts();
      if (response.success && response.data) {
        setAlerts(response.data);
      }
    } catch {
      // Silent fail - banner is supplementary
    } finally {
      setLoading(false);
    }
  };

  const dismissAlert = (alertId: string) => {
    setDismissedAlerts((prev) => new Set([...prev, alertId]));
  };

  const visibleAlerts = alerts
    .filter((alert) => !dismissedAlerts.has(alert.id))
    .slice(0, maxAlerts);

  const criticalCount = alerts.filter(
    (a) => a.severity === 'critical' && !dismissedAlerts.has(a.id)
  ).length;
  const highCount = alerts.filter(
    (a) => a.severity === 'high' && !dismissedAlerts.has(a.id)
  ).length;
  const totalCount = alerts.filter((a) => !dismissedAlerts.has(a.id)).length;

  const getSeverityStyles = (severity: string) => {
    switch (severity) {
      case 'critical':
        return {
          bg: 'bg-theme-error',
          text: 'text-white',
          icon: AlertTriangle,
          border: 'border-theme-error',
        };
      case 'high':
        return {
          bg: 'bg-theme-error bg-opacity-80',
          text: 'text-white',
          icon: AlertCircle,
          border: 'border-theme-error',
        };
      case 'medium':
        return {
          bg: 'bg-theme-warning',
          text: 'text-white',
          icon: AlertCircle,
          border: 'border-theme-warning',
        };
      default:
        return {
          bg: 'bg-theme-info',
          text: 'text-white',
          icon: Bell,
          border: 'border-theme-info',
        };
    }
  };

  // Don't render if no visible alerts
  if (loading || visibleAlerts.length === 0) {
    return null;
  }

  // Single critical/high alert - full banner
  if (visibleAlerts.length === 1 && ['critical', 'high'].includes(visibleAlerts[0].severity)) {
    const alert = visibleAlerts[0];
    const styles = getSeverityStyles(alert.severity);
    const Icon = styles.icon;

    return (
      <div className={`${styles.bg} ${className}`}>
        <div className="px-4 py-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <Icon className={`w-5 h-5 ${styles.text}`} />
              <div>
                <p className={`font-medium ${styles.text}`}>
                  {alert.type.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())} Alert
                </p>
                <p className={`text-sm ${styles.text} opacity-90`}>{alert.message}</p>
              </div>
            </div>
            <div className="flex items-center gap-2">
              {onViewAll && (
                <Button
                  variant="outline"
                  onClick={onViewAll}
                  className={`border-white border-opacity-30 ${styles.text} hover:bg-white hover:bg-opacity-10`}
                >
                  View Details
                  <ChevronRight className="w-4 h-4 ml-1" />
                </Button>
              )}
              <button
                onClick={() => dismissAlert(alert.id)}
                className={`p-1 rounded-full hover:bg-white hover:bg-opacity-10 ${styles.text}`}
              >
                <X className="w-4 h-4" />
              </button>
            </div>
          </div>
        </div>
      </div>
    );
  }

  // Multiple alerts - compact summary
  return (
    <div className={`bg-theme-warning ${className}`}>
      <div className="px-4 py-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-2">
              <Shield className="w-5 h-5 text-white" />
              <span className="font-medium text-white">
                {totalCount} Active Alert{totalCount !== 1 ? 's' : ''}
              </span>
            </div>
            <div className="flex items-center gap-3">
              {criticalCount > 0 && (
                <span className="px-2 py-0.5 rounded-full bg-white bg-opacity-20 text-white text-xs font-medium">
                  {criticalCount} Critical
                </span>
              )}
              {highCount > 0 && (
                <span className="px-2 py-0.5 rounded-full bg-white bg-opacity-20 text-white text-xs font-medium">
                  {highCount} High
                </span>
              )}
            </div>
          </div>
          <div className="flex items-center gap-4">
            {/* Alert previews */}
            <div className="hidden md:flex items-center gap-2">
              {visibleAlerts.slice(0, 2).map((alert) => {
                const styles = getSeverityStyles(alert.severity);
                const Icon = styles.icon;
                return (
                  <div
                    key={alert.id}
                    className="flex items-center gap-2 px-3 py-1 bg-white bg-opacity-10 rounded-full"
                  >
                    <Icon className="w-4 h-4 text-white" />
                    <span className="text-sm text-white truncate max-w-[150px]">
                      {alert.type.replace(/_/g, ' ')}
                    </span>
                  </div>
                );
              })}
              {totalCount > 2 && (
                <span className="text-sm text-white opacity-80">
                  +{totalCount - 2} more
                </span>
              )}
            </div>
            {onViewAll && (
              <Button
                variant="outline"
                onClick={onViewAll}
                className="border-white border-opacity-30 text-white hover:bg-white hover:bg-opacity-10"
              >
                View All
                <ChevronRight className="w-4 h-4 ml-1" />
              </Button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default AdminAlertsBanner;
