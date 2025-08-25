import React from 'react';
import {
  AlertTriangle,
  Shield,
  Eye,
  Lock,
  Globe,
  TrendingUp,
  TrendingDown,
  Activity
} from 'lucide-react';

interface TopThreatsProps {
  timeRange: { label: string; value: string; days: number };
}

interface ThreatData {
  type: string;
  severity: 'low' | 'medium' | 'high' | 'critical';
  count: number;
  change: number;
  description: string;
  icon: React.ReactNode;
  sources: string[];
  lastSeen: string;
}

export const TopThreats: React.FC<TopThreatsProps> = ({ timeRange }) => {
  const threatData: ThreatData[] = [
    {
      type: 'Brute Force Attacks',
      severity: 'high',
      count: 45,
      change: +23,
      description: 'Repeated login attempts with invalid credentials',
      icon: <Lock className="w-5 h-5" />,
      sources: ['192.168.1.100', '203.0.113.42', '198.51.100.23'],
      lastSeen: '2 hours ago'
    },
    {
      type: 'Suspicious User Agents',
      severity: 'medium',
      count: 32,
      change: -8,
      description: 'Non-standard or potentially malicious user agents',
      icon: <Eye className="w-5 h-5" />,
      sources: ['Bot/1.0', 'Scanner-XSS', 'Unknown/Unknown'],
      lastSeen: '1 hour ago'
    },
    {
      type: 'Geo-location Anomalies',
      severity: 'medium',
      count: 28,
      change: +15,
      description: 'Logins from unusual geographic locations',
      icon: <Globe className="w-5 h-5" />,
      sources: ['Russia', 'China', 'North Korea'],
      lastSeen: '45 minutes ago'
    },
    {
      type: 'Privilege Escalation',
      severity: 'critical',
      count: 12,
      change: +50,
      description: 'Attempts to gain elevated system privileges',
      icon: <Shield className="w-5 h-5" />,
      sources: ['admin-panel', 'api-endpoint', 'database'],
      lastSeen: '3 hours ago'
    },
    {
      type: 'SQL Injection Attempts',
      severity: 'critical',
      count: 8,
      change: -25,
      description: 'Malicious SQL code injection attempts',
      icon: <AlertTriangle className="w-5 h-5" />,
      sources: ['/api/users', '/search', '/admin/reports'],
      lastSeen: '6 hours ago'
    },
    {
      type: 'Account Takeover Indicators',
      severity: 'high',
      count: 6,
      change: +100,
      description: 'Signs of compromised user accounts',
      icon: <Activity className="w-5 h-5" />,
      sources: ['user@domain.com', 'admin@company.com'],
      lastSeen: '30 minutes ago'
    }
  ];

  const getSeverityColor = (severity: string) => {
    switch (severity) {
      case 'critical': return 'text-theme-error bg-theme-error-background border-theme-error';
      case 'high': return 'text-theme-warning bg-theme-warning-background border-theme-warning';
      case 'medium': return 'text-theme-warning bg-theme-warning-background border-theme-warning';
      case 'low': return 'text-theme-success bg-theme-success-background border-theme-success';
      default: return 'text-theme-secondary bg-theme-background-secondary border-theme';
    }
  };

  const getSeverityDotColor = (severity: string) => {
    switch (severity) {
      case 'critical': return 'bg-theme-error';
      case 'high': return 'bg-theme-warning';
      case 'medium': return 'bg-theme-warning';
      case 'low': return 'bg-theme-success';
      default: return 'bg-theme-background-secondary';
    }
  };

  const getTrendIcon = (change: number) => {
    if (change > 0) {
      return <TrendingUp className="w-3 h-3 text-theme-error" />;
    } else if (change < 0) {
      return <TrendingDown className="w-3 h-3 text-theme-success" />;
    }
    return null;
  };

  const getTrendColor = (change: number) => {
    if (change > 0) return 'text-theme-error';
    if (change < 0) return 'text-theme-success';
    return 'text-theme-tertiary';
  };

  return (
    <div className="bg-theme-background rounded-lg border border-theme p-6">
      <div className="flex items-center gap-2 mb-6">
        <div className="p-1 bg-theme-error-background rounded">
          <AlertTriangle className="w-4 h-4 text-theme-error" />
        </div>
        <div>
          <h3 className="text-lg font-semibold text-theme-primary">Top Security Threats</h3>
          <p className="text-theme-secondary">Most frequent threats for {timeRange.label.toLowerCase()}</p>
        </div>
      </div>

      <div className="space-y-4">
        {threatData.map((threat, index) => (
          <div key={index} className="border border-theme rounded-lg p-4 hover:bg-theme-surface-hover transition-colors duration-200">
            <div className="flex items-start justify-between mb-3">
              <div className="flex items-center gap-3">
                <div className={`p-2 rounded-lg ${getSeverityColor(threat.severity)}`}>
                  {threat.icon}
                </div>
                <div>
                  <div className="flex items-center gap-2">
                    <h4 className="font-semibold text-theme-primary">{threat.type}</h4>
                    <div className={`w-2 h-2 rounded-full ${getSeverityDotColor(threat.severity)}`} />
                    <span className={`text-xs font-medium px-2 py-1 rounded-full ${getSeverityColor(threat.severity)}`}>
                      {threat.severity.toUpperCase()}
                    </span>
                  </div>
                  <p className="text-sm text-theme-secondary mt-1">{threat.description}</p>
                </div>
              </div>
              
              <div className="text-right">
                <div className="text-2xl font-bold text-theme-primary">{threat.count}</div>
                <div className="flex items-center gap-1 justify-end">
                  {getTrendIcon(threat.change)}
                  <span className={`text-xs font-medium ${getTrendColor(threat.change)}`}>
                    {threat.change > 0 ? '+' : ''}{threat.change}%
                  </span>
                </div>
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 pt-3 border-t border-theme">
              <div>
                <h5 className="text-xs font-medium text-theme-secondary mb-2">Top Sources</h5>
                <div className="space-y-1">
                  {threat.sources.slice(0, 3).map((source, sourceIndex) => (
                    <div key={sourceIndex} className="text-xs font-mono bg-theme-surface px-2 py-1 rounded">
                      {source}
                    </div>
                  ))}
                </div>
              </div>
              
              <div>
                <h5 className="text-xs font-medium text-theme-secondary mb-2">Threat Intelligence</h5>
                <div className="space-y-1 text-xs text-theme-tertiary">
                  <div>Last seen: {threat.lastSeen}</div>
                  <div>Frequency: {Math.round(threat.count / timeRange.days)} per day</div>
                  <div>Risk level: {threat.severity}</div>
                </div>
              </div>
            </div>

            {/* Action buttons */}
            <div className="flex items-center gap-2 mt-4 pt-3 border-t border-theme">
              <button className="text-xs bg-theme-interactive-primary text-white px-3 py-1 rounded hover:bg-theme-interactive-primary-hover transition-colors duration-200">
                Block Source
              </button>
              <button className="text-xs bg-theme-background text-theme-primary border border-theme px-3 py-1 rounded hover:bg-theme-surface-hover transition-colors duration-200">
                View Details
              </button>
              <button className="text-xs bg-theme-background text-theme-primary border border-theme px-3 py-1 rounded hover:bg-theme-surface-hover transition-colors duration-200">
                Create Rule
              </button>
            </div>
          </div>
        ))}
      </div>

      {/* Summary stats */}
      <div className="mt-6 pt-4 border-t border-theme">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="text-center">
            <div className="text-2xl font-bold text-theme-primary">
              {threatData.reduce((acc, threat) => acc + threat.count, 0)}
            </div>
            <div className="text-sm text-theme-secondary">Total Threats</div>
          </div>
          
          <div className="text-center">
            <div className="text-2xl font-bold text-theme-error">
              {threatData.filter(t => t.severity === 'critical').length}
            </div>
            <div className="text-sm text-theme-secondary">Critical Threats</div>
          </div>
          
          <div className="text-center">
            <div className="text-2xl font-bold text-theme-primary">
              {Math.round(threatData.reduce((acc, threat) => acc + Math.abs(threat.change), 0) / threatData.length)}%
            </div>
            <div className="text-sm text-theme-secondary">Avg Change</div>
          </div>
        </div>
      </div>
    </div>
  );
};