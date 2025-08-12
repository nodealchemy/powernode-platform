import React from 'react';
import {
  AlertTriangle,
  Shield,
  TrendingUp,
  TrendingDown,
  Eye,
  Lock,
  Globe,
  Clock,
  Activity,
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
  const riskFactors: RiskFactor[] = [
    {
      name: 'Authentication Failures',
      level: 'medium',
      score: 65,
      trend: +12,
      description: 'Failed login attempts and authentication errors',
      icon: <Lock className="w-5 h-5" />
    },
    {
      name: 'Privilege Escalation',
      level: 'high',
      score: 78,
      trend: -5,
      description: 'Unauthorized access to elevated permissions',
      icon: <Shield className="w-5 h-5" />
    },
    {
      name: 'Data Access Anomalies',
      level: 'medium',
      score: 58,
      trend: +8,
      description: 'Unusual patterns in data access and retrieval',
      icon: <Eye className="w-5 h-5" />
    },
    {
      name: 'External Threats',
      level: 'low',
      score: 35,
      trend: -15,
      description: 'Attacks from external IP addresses',
      icon: <Globe className="w-5 h-5" />
    },
    {
      name: 'Off-hours Activity',
      level: 'medium',
      score: 42,
      trend: +3,
      description: 'System access during unusual hours',
      icon: <Clock className="w-5 h-5" />
    },
    {
      name: 'Account Compromise',
      level: 'critical',
      score: 85,
      trend: +25,
      description: 'Indicators of compromised user accounts',
      icon: <Users className="w-5 h-5" />
    }
  ];

  const threatIndicators: ThreatIndicator[] = [
    {
      type: 'Brute Force Attack',
      severity: 'high',
      count: 23,
      lastOccurrence: '2 hours ago',
      mitigation: 'Rate limiting activated'
    },
    {
      type: 'SQL Injection Attempt',
      severity: 'critical',
      count: 5,
      lastOccurrence: '6 hours ago',
      mitigation: 'Input validation enhanced'
    },
    {
      type: 'Suspicious User Agent',
      severity: 'medium',
      count: 15,
      lastOccurrence: '1 hour ago',
      mitigation: 'Monitoring activated'
    },
    {
      type: 'Geo-location Anomaly',
      severity: 'medium',
      count: 8,
      lastOccurrence: '4 hours ago',
      mitigation: 'Location verification required'
    }
  ];

  const getRiskColor = (level: string) => {
    switch (level) {
      case 'critical': return 'text-red-700 bg-red-100 border-red-200';
      case 'high': return 'text-orange-700 bg-orange-100 border-orange-200';
      case 'medium': return 'text-yellow-700 bg-yellow-100 border-yellow-200';
      case 'low': return 'text-green-700 bg-green-100 border-green-200';
      default: return 'text-gray-700 bg-gray-100 border-gray-200';
    }
  };

  const getSeverityColor = (severity: string) => {
    switch (severity) {
      case 'critical': return 'bg-red-500';
      case 'high': return 'bg-orange-500';
      case 'medium': return 'bg-yellow-500';
      case 'low': return 'bg-green-500';
      default: return 'bg-gray-500';
    }
  };

  const overallRiskScore = Math.round(
    riskFactors.reduce((acc, factor) => acc + factor.score, 0) / riskFactors.length
  );

  const getRiskLevel = (score: number) => {
    if (score >= 80) return { level: 'critical', color: 'text-red-600' };
    if (score >= 60) return { level: 'high', color: 'text-orange-600' };
    if (score >= 40) return { level: 'medium', color: 'text-yellow-600' };
    return { level: 'low', color: 'text-green-600' };
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
                  overallRiskScore >= 80 ? 'bg-red-500' :
                  overallRiskScore >= 60 ? 'bg-orange-500' :
                  overallRiskScore >= 40 ? 'bg-yellow-500' : 'bg-green-500'
                }`}
                style={{ width: `${overallRiskScore}%` }}
              />
              {/* Threshold markers */}
              <div className="absolute inset-0 flex justify-between px-1">
                <div className="w-0.5 h-4 bg-white opacity-50" style={{ marginLeft: '40%' }} />
                <div className="w-0.5 h-4 bg-white opacity-50" style={{ marginLeft: '60%' }} />
                <div className="w-0.5 h-4 bg-white opacity-50" style={{ marginLeft: '80%' }} />
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
              <div className="p-1 rounded bg-white bg-opacity-50">
                {factor.icon}
              </div>
              <div className="flex items-center gap-1 text-sm">
                {factor.trend > 0 ? (
                  <TrendingUp className="w-3 h-3" />
                ) : (
                  <TrendingDown className="w-3 h-3" />
                )}
                <span className={factor.trend > 0 ? 'text-red-600' : 'text-green-600'}>
                  {Math.abs(factor.trend)}%
                </span>
              </div>
            </div>
            <div className="text-lg font-bold text-current mb-1">{factor.score}</div>
            <div className="font-medium text-current mb-1">{factor.name}</div>
            <div className="text-xs opacity-75">{factor.description}</div>
            
            {/* Risk level indicator */}
            <div className="mt-3">
              <div className="w-full bg-white bg-opacity-30 rounded-full h-1">
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
          <div className="flex items-start gap-3 p-4 bg-red-50 rounded-lg border border-red-200">
            <AlertTriangle className="w-5 h-5 text-red-600 mt-0.5" />
            <div>
              <div className="font-medium text-red-800">Critical: Account Compromise Detection</div>
              <div className="text-sm text-red-700 mb-2">
                Multiple indicators suggest potential account compromise. Immediate action required.
              </div>
              <div className="text-xs text-red-600">
                Recommended: Force password reset for affected accounts, enable 2FA, review access logs
              </div>
            </div>
          </div>
          
          <div className="flex items-start gap-3 p-4 bg-orange-50 rounded-lg border border-orange-200">
            <Shield className="w-5 h-5 text-orange-600 mt-0.5" />
            <div>
              <div className="font-medium text-orange-800">High: Privilege Escalation Monitoring</div>
              <div className="text-sm text-orange-700 mb-2">
                Increase monitoring for unauthorized privilege escalation attempts.
              </div>
              <div className="text-xs text-orange-600">
                Recommended: Implement role-based access controls, audit admin permissions
              </div>
            </div>
          </div>
          
          <div className="flex items-start gap-3 p-4 bg-yellow-50 rounded-lg border border-yellow-200">
            <Eye className="w-5 h-5 text-yellow-600 mt-0.5" />
            <div>
              <div className="font-medium text-yellow-800">Medium: Enhanced Monitoring</div>
              <div className="text-sm text-yellow-700 mb-2">
                Strengthen monitoring for authentication failures and data access patterns.
              </div>
              <div className="text-xs text-yellow-600">
                Recommended: Tune alert thresholds, implement behavioral analytics
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};