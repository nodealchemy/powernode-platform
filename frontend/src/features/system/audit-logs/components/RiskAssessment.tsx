
import {
  AlertTriangle,
  Shield,
  TrendingUp,
  TrendingDown,
  Eye,
  Lock,
  Globe,
  Clock,
  Users
} from 'lucide-react';

interface RiskAssessmentProps {
   
  metrics: any;
  timeRange: { label: string; value: string; days: number };
}

interface RiskFactor {
  name: string;
  level: 'low' | 'medium' | 'high' | 'critical';
  score: number;
  trend: number;
  description: string;
  icon: React.ReactNode;
}

interface ThreatIndicator {
  type: string;
  severity: 'low' | 'medium' | 'high' | 'critical';
  count: number;
  lastOccurrence: string;
  mitigation: string;
}

export const RiskAssessment: React.FC<RiskAssessmentProps> = ({ metrics, timeRange }) => {
  // Calculate risk level from score
  const calculateRiskLevel = (score: number): 'low' | 'medium' | 'high' | 'critical' => {
    if (score >= 80) return 'critical';
    if (score >= 60) return 'high';
    if (score >= 40) return 'medium';
    return 'low';
  };

  const riskFactors: RiskFactor[] = [
    {
      name: 'Authentication Failures',
      level: calculateRiskLevel(metrics?.failed_logins || 0),
      score: Math.min(100, (metrics?.failed_logins || 0) * 5), // Scale failed logins to risk score
      trend: metrics?.failed_logins_change || 0,
      description: 'Failed login attempts and authentication errors',
      icon: <Lock className="w-5 h-5" />
    },
    {
      name: 'Privilege Escalation',
      level: calculateRiskLevel(metrics?.privilege_escalation_score || 0),
      score: metrics?.privilege_escalation_score || 0,
      trend: metrics?.privilege_escalation_change || 0,
      description: 'Unauthorized access to elevated permissions',
      icon: <Shield className="w-5 h-5" />
    },
    {
      name: 'Data Access Anomalies',
      level: calculateRiskLevel(metrics?.data_access_anomalies || 0),
      score: metrics?.data_access_anomalies || 0,
      trend: metrics?.data_access_change || 0,
      description: 'Unusual patterns in data access and retrieval',
      icon: <Eye className="w-5 h-5" />
    },
    {
      name: 'External Threats',
      level: calculateRiskLevel(metrics?.external_threats || 0),
      score: metrics?.external_threats || 0,
      trend: metrics?.external_threats_change || 0,
      description: 'Attacks from external IP addresses',
      icon: <Globe className="w-5 h-5" />
    },
    {
      name: 'Off-hours Activity',
      level: calculateRiskLevel(metrics?.off_hours_activity || 0),
      score: metrics?.off_hours_activity || 0,
      trend: metrics?.off_hours_change || 0,
      description: 'System access during unusual hours',
      icon: <Clock className="w-5 h-5" />
    },
    {
      name: 'Account Compromise',
      level: calculateRiskLevel(metrics?.account_compromise_score || 0),
      score: metrics?.account_compromise_score || 0,
      trend: metrics?.account_compromise_change || 0,
      description: 'Indicators of compromised user accounts',
      icon: <Users className="w-5 h-5" />
    }
  ];

  // Calculate threat severity from count
  const calculateSeverity = (count: number): 'low' | 'medium' | 'high' | 'critical' => {
    if (count >= 20) return 'critical';
    if (count >= 10) return 'high';
    if (count >= 5) return 'medium';
    return 'low';
  };

  const formatLastOccurrence = (timestamp: string): string => {
    if (!timestamp) return 'No recent activity';
    const date = new Date(timestamp);
    const now = new Date();
    const diffMinutes = Math.floor((now.getTime() - date.getTime()) / (1000 * 60));
    
    if (diffMinutes < 60) return `${diffMinutes} minutes ago`;
    const diffHours = Math.floor(diffMinutes / 60);
    if (diffHours < 24) return `${diffHours} hours ago`;
    const diffDays = Math.floor(diffHours / 24);
    return `${diffDays} days ago`;
  };

  const threatIndicators: ThreatIndicator[] = [
    {
      type: 'Brute Force Attack',
      severity: calculateSeverity(metrics?.brute_force_attempts || 0),
      count: metrics?.brute_force_attempts || 0,
      lastOccurrence: formatLastOccurrence(metrics?.brute_force_last_occurrence),
      mitigation: metrics?.brute_force_attempts > 0 ? 'Rate limiting activated' : 'No recent activity'
    },
    {
      type: 'SQL Injection Attempt',
      severity: calculateSeverity(metrics?.sql_injection_attempts || 0),
      count: metrics?.sql_injection_attempts || 0,
      lastOccurrence: formatLastOccurrence(metrics?.sql_injection_last_occurrence),
      mitigation: metrics?.sql_injection_attempts > 0 ? 'Input validation enhanced' : 'No recent activity'
    },
    {
      type: 'Suspicious User Agent',
      severity: calculateSeverity(metrics?.suspicious_user_agents || 0),
      count: metrics?.suspicious_user_agents || 0,
      lastOccurrence: formatLastOccurrence(metrics?.suspicious_user_agents_last_occurrence),
      mitigation: metrics?.suspicious_user_agents > 0 ? 'Monitoring activated' : 'No recent activity'
    },
    {
      type: 'Geo-location Anomaly',
      severity: calculateSeverity(metrics?.geo_anomalies || 0),
      count: metrics?.geo_anomalies || 0,
      lastOccurrence: formatLastOccurrence(metrics?.geo_anomalies_last_occurrence),
      mitigation: metrics?.geo_anomalies > 0 ? 'Location verification required' : 'No recent activity'
    }
  ].filter(indicator => indicator.count > 0); // Only show active threats

  const getRiskColor = (level: string) => {
    switch (level) {
      case 'critical': return 'text-theme-status-error bg-theme-status-error-background border-theme-status-error';
      case 'high': return 'text-theme-status-warning bg-theme-status-warning-background border-theme-status-warning';
      case 'medium': return 'text-theme-status-warning bg-theme-status-warning-background border-theme-status-warning';
      case 'low': return 'text-theme-status-success bg-theme-status-success-background border-theme-status-success';
      default: return 'text-theme-secondary bg-theme-surface border-theme';
    }
  };

  const getSeverityColor = (severity: string) => {
    switch (severity) {
      case 'critical': return 'bg-theme-status-error';
      case 'high': return 'bg-theme-status-warning';
      case 'medium': return 'bg-theme-status-warning';
      case 'low': return 'bg-theme-status-success';
      default: return 'bg-theme-secondary';
    }
  };

  const overallRiskScore = Math.round(
    riskFactors.reduce((acc, factor) => acc + factor.score, 0) / riskFactors.length
  );

  const getRiskLevel = (score: number) => {
    if (score >= 80) return { level: 'critical', color: 'text-theme-status-error' };
    if (score >= 60) return { level: 'high', color: 'text-theme-status-warning' };
    if (score >= 40) return { level: 'medium', color: 'text-theme-status-warning' };
    return { level: 'low', color: 'text-theme-status-success' };
  };

  const riskLevel = getRiskLevel(overallRiskScore);

  return (
    <div className="space-y-6">
      {/* Overall Risk Score */}
      <div className="bg-theme-background rounded-lg border border-theme p-6">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h3 className="text-lg font-semibold text-theme-primary">Overall Risk Assessment</h3>
            <p className="text-theme-secondary">Current security risk level for {timeRange.label.toLowerCase()}</p>
          </div>
          <div className="text-right">
            <div className="text-3xl font-bold text-theme-primary">{overallRiskScore}</div>
            <div className={`text-sm font-medium ${riskLevel.color}`}>
              {riskLevel.level.toUpperCase()} RISK
            </div>
          </div>
        </div>

        {/* Risk Score Gauge */}
        <div className="relative">
          <div className="w-full bg-theme-surface rounded-full h-4">
            <div className="relative">
              {/* Score bar */}
              <div 
                className={`h-4 rounded-full transition-all duration-500 ${
                  overallRiskScore >= 80 ? 'bg-theme-status-error' :
                  overallRiskScore >= 60 ? 'bg-theme-status-warning' :
                  overallRiskScore >= 40 ? 'bg-theme-status-warning' : 'bg-theme-status-success'
                }`}
                style={{ width: `${overallRiskScore}%` }}
              />
              {/* Threshold markers */}
              <div className="absolute inset-0 flex justify-between px-1">
                <div className="w-0.5 h-4 bg-theme-background opacity-50" style={{ marginLeft: '40%' }} />
                <div className="w-0.5 h-4 bg-theme-background opacity-50" style={{ marginLeft: '60%' }} />
                <div className="w-0.5 h-4 bg-theme-background opacity-50" style={{ marginLeft: '80%' }} />
              </div>
            </div>
          </div>
          <div className="flex justify-between text-xs text-theme-secondary mt-1">
            <span>Low</span>
            <span>Medium</span>
            <span>High</span>
            <span>Critical</span>
          </div>
        </div>
      </div>

      {/* Risk Factors Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {riskFactors.map((factor, index) => (
          <div key={index} className={`p-4 rounded-lg border ${getRiskColor(factor.level)}`}>
            <div className="flex items-center justify-between mb-2">
              <div className="p-1 rounded bg-theme-background bg-opacity-50">
                {factor.icon}
              </div>
              <div className="flex items-center gap-1 text-sm">
                {factor.trend > 0 ? (
                  <TrendingUp className="w-3 h-3" />
                ) : (
                  <TrendingDown className="w-3 h-3" />
                )}
                <span className={factor.trend > 0 ? 'text-theme-status-error' : 'text-theme-status-success'}>
                  {Math.abs(factor.trend)}%
                </span>
              </div>
            </div>
            <div className="text-lg font-bold text-current mb-1">{factor.score}</div>
            <div className="font-medium text-current mb-1">{factor.name}</div>
            <div className="text-xs opacity-75">{factor.description}</div>
            
            {/* Risk level indicator */}
            <div className="mt-3">
              <div className="w-full bg-theme-background bg-opacity-30 rounded-full h-1">
                <div 
                  className="bg-current h-1 rounded-full transition-all duration-300"
                  style={{ width: `${factor.score}%` }}
                />
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Threat Indicators */}
      <div className="bg-theme-background rounded-lg border border-theme overflow-hidden">
        <div className="px-6 py-4 border-b border-theme">
          <h3 className="text-lg font-semibold text-theme-primary">Active Threat Indicators</h3>
          <p className="text-theme-secondary">Current security threats and mitigation status</p>
        </div>

        <div className="divide-y divide-theme">
          {threatIndicators.map((threat, index) => (
            <div key={index} className="p-6 flex items-center justify-between">
              <div className="flex items-center gap-4">
                <div className={`w-3 h-3 rounded-full ${getSeverityColor(threat.severity)}`} />
                <div>
                  <div className="font-medium text-theme-primary">{threat.type}</div>
                  <div className="text-sm text-theme-secondary">{threat.mitigation}</div>
                </div>
              </div>
              
              <div className="text-right">
                <div className="text-lg font-bold text-theme-primary">{threat.count}</div>
                <div className="text-xs text-theme-secondary">{threat.lastOccurrence}</div>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Risk Mitigation Recommendations */}
      <div className="bg-theme-background rounded-lg border border-theme p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Risk Mitigation Recommendations</h3>
        
        <div className="space-y-4">
          <div className="flex items-start gap-3 p-4 bg-theme-status-error-background rounded-lg border border-theme-status-error">
            <AlertTriangle className="w-5 h-5 text-theme-status-error mt-0.5" />
            <div>
              <div className="font-medium text-theme-status-error">Critical: Account Compromise Detection</div>
              <div className="text-sm text-theme-status-error mb-2">
                Multiple indicators suggest potential account compromise. Immediate action required.
              </div>
              <div className="text-xs text-theme-status-error">
                Recommended: Force password reset for affected accounts, enable 2FA, review access logs
              </div>
            </div>
          </div>
          
          <div className="flex items-start gap-3 p-4 bg-theme-status-warning-background rounded-lg border border-theme-status-warning">
            <Shield className="w-5 h-5 text-theme-status-warning mt-0.5" />
            <div>
              <div className="font-medium text-theme-status-warning">High: Privilege Escalation Monitoring</div>
              <div className="text-sm text-theme-status-warning mb-2">
                Increase monitoring for unauthorized privilege escalation attempts.
              </div>
              <div className="text-xs text-theme-status-warning">
                Recommended: Implement role-based access controls, audit admin permissions
              </div>
            </div>
          </div>
          
          <div className="flex items-start gap-3 p-4 bg-theme-status-warning-background rounded-lg border border-theme-status-warning">
            <Eye className="w-5 h-5 text-theme-status-warning mt-0.5" />
            <div>
              <div className="font-medium text-theme-status-warning">Medium: Enhanced Monitoring</div>
              <div className="text-sm text-theme-status-warning mb-2">
                Strengthen monitoring for authentication failures and data access patterns.
              </div>
              <div className="text-xs text-theme-status-warning">
                Recommended: Tune alert thresholds, implement behavioral analytics
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};