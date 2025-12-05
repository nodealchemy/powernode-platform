
import {
  Shield,
  AlertTriangle,
  Eye,
  Users,
  Globe,
  Lock,
  Unlock,
  TrendingUp,
  TrendingDown
} from 'lucide-react';

interface SecurityOverviewProps {
  metrics: any;
  timeRange: { label: string; value: string; days: number };
}

export const SecurityOverview: React.FC<SecurityOverviewProps> = ({ metrics, timeRange }) => {
  const securityMetrics = [
    {
      label: 'Failed Login Attempts',
      value: metrics?.failed_logins || 0,
      change: metrics?.failed_logins_change || 0,
      icon: <Lock className="w-5 h-5" />,
      color: 'red',
      description: 'Login failures in the last period'
    },
    {
      label: 'Security Alerts',
      value: metrics?.security_alerts || 0,
      change: metrics?.security_alerts_change || 0,
      icon: <AlertTriangle className="w-5 h-5" />,
      color: 'yellow',
      description: 'Automated security alerts triggered'
    },
    {
      label: 'Suspicious Activities',
      value: metrics?.suspicious_activities || 0,
      change: metrics?.suspicious_activities_change || 0,
      icon: <Eye className="w-5 h-5" />,
      color: 'orange',
      description: 'Activities flagged as suspicious'
    },
    {
      label: 'Account Lockouts',
      value: metrics?.account_lockouts || 0,
      change: metrics?.account_lockouts_change || 0,
      icon: <Unlock className="w-5 h-5" />,
      color: 'purple',
      description: 'Accounts locked due to security violations'
    }
  ];

  const threatSources = [
    { country: 'Unknown', attempts: 15, percentage: 35 },
    { country: 'Russia', attempts: 8, percentage: 19 },
    { country: 'China', attempts: 6, percentage: 14 },
    { country: 'Brazil', attempts: 4, percentage: 9 },
    { country: 'Others', attempts: 10, percentage: 23 }
  ];

  const getColorClasses = (color: string) => {
    switch (color) {
      case 'red': return 'bg-theme-error-background text-theme-error';
      case 'yellow': return 'bg-theme-warning-background text-theme-warning';
      case 'orange': return 'bg-theme-warning-background text-theme-warning';
      case 'purple': return 'bg-theme-info-background text-theme-info';
      default: return 'bg-theme-surface text-theme-secondary';
    }
  };

  return (
    <div className="space-y-6">
      {/* Security Status Overview */}
      <div className="bg-theme-background rounded-lg border border-theme p-6">
        <div className="flex items-center gap-3 mb-6">
          <div className="p-2 bg-theme-success-background rounded-lg">
            <Shield className="w-6 h-6 text-theme-success" />
          </div>
          <div>
            <h3 className="text-lg font-semibold text-theme-primary">Security Status</h3>
            <p className="text-theme-secondary">Overall security posture for {timeRange.label.toLowerCase()}</p>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          {securityMetrics.map((metric, index) => (
            <div key={index} className="p-4 bg-theme-surface rounded-lg border border-theme">
              <div className="flex items-center justify-between mb-2">
                <div className={`p-2 rounded-lg ${getColorClasses(metric.color)}`}>
                  {metric.icon}
                </div>
                <div className="flex items-center gap-1 text-sm">
                  {metric.change > 0 ? (
                    <TrendingUp className="w-3 h-3 text-theme-error" />
                  ) : (
                    <TrendingDown className="w-3 h-3 text-theme-success" />
                  )}
                  <span className={metric.change > 0 ? 'text-theme-error' : 'text-theme-success'}>
                    {Math.abs(metric.change)}%
                  </span>
                </div>
              </div>
              <div className="text-2xl font-bold text-theme-primary mb-1">{metric.value}</div>
              <div className="text-sm font-medium text-theme-secondary mb-1">{metric.label}</div>
              <div className="text-xs text-theme-tertiary">{metric.description}</div>
            </div>
          ))}
        </div>
      </div>

      {/* Threat Intelligence */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="bg-theme-background rounded-lg border border-theme p-6">
          <div className="flex items-center gap-2 mb-4">
            <Globe className="w-5 h-5 text-theme-secondary" />
            <h4 className="text-lg font-semibold text-theme-primary">Threat Sources by Country</h4>
          </div>
          <div className="space-y-3">
            {threatSources.map((source, index) => (
              <div key={index} className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div className="w-8 h-6 bg-theme-surface rounded border border-theme flex items-center justify-center">
                    <span className="text-xs font-medium text-theme-secondary">{source.country.substring(0, 2).toUpperCase()}</span>
                  </div>
                  <span className="text-sm font-medium text-theme-primary">{source.country}</span>
                </div>
                <div className="flex items-center gap-3">
                  <div className="w-20 bg-theme-background rounded-full h-2">
                    <div 
                      className="bg-theme-error h-2 rounded-full"
                      style={{ width: `${source.percentage}%` }}
                    />
                  </div>
                  <span className="text-sm text-theme-secondary w-8 text-right">{source.attempts}</span>
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="bg-theme-background rounded-lg border border-theme p-6">
          <div className="flex items-center gap-2 mb-4">
            <AlertTriangle className="w-5 h-5 text-theme-secondary" />
            <h4 className="text-lg font-semibold text-theme-primary">Recent Security Events</h4>
          </div>
          <div className="space-y-3">
            <div className="flex items-start gap-3 p-3 bg-theme-error-background rounded-lg border border-theme-error">
              <div className="p-1 bg-theme-error-background rounded">
                <AlertTriangle className="w-3 h-3 text-theme-error" />
              </div>
              <div className="flex-1">
                <div className="text-sm font-medium text-theme-error">Multiple failed login attempts</div>
                <div className="text-xs text-theme-error">admin@company.com - 5 attempts</div>
                <div className="text-xs text-theme-tertiary">2 minutes ago</div>
              </div>
            </div>
            
            <div className="flex items-start gap-3 p-3 bg-theme-warning-background rounded-lg border border-theme-warning">
              <div className="p-1 bg-theme-warning-background rounded">
                <Eye className="w-3 h-3 text-theme-warning" />
              </div>
              <div className="flex-1">
                <div className="text-sm font-medium text-theme-warning">Unusual access pattern detected</div>
                <div className="text-xs text-theme-warning">User login from new location</div>
                <div className="text-xs text-theme-tertiary">15 minutes ago</div>
              </div>
            </div>
            
            <div className="flex items-start gap-3 p-3 bg-theme-info-background rounded-lg border border-theme-info">
              <div className="p-1 bg-theme-info-background rounded">
                <Users className="w-3 h-3 text-theme-info" />
              </div>
              <div className="flex-1">
                <div className="text-sm font-medium text-theme-info">Admin action performed</div>
                <div className="text-xs text-theme-info">User permissions modified</div>
                <div className="text-xs text-theme-tertiary">1 hour ago</div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};