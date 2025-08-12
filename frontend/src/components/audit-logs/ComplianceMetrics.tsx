import React from 'react';
import {
  Shield,
  CheckCircle,
  AlertTriangle,
  FileText,
  Download,
  Calendar,
  TrendingUp,
  Activity
} from 'lucide-react';

interface ComplianceMetricsProps {
  timeRange: { label: string; value: string; days: number };
}

interface ComplianceMetric {
  regulation: string;
  score: number;
  events: number;
  lastAudit: string;
  status: 'compliant' | 'warning' | 'non-compliant';
  requirements: { name: string; met: boolean }[];
}

export const ComplianceMetrics: React.FC<ComplianceMetricsProps> = ({ timeRange }) => {
  const complianceData: ComplianceMetric[] = [
    {
      regulation: 'GDPR',
      score: 98,
      events: 45,
      lastAudit: '2024-01-15',
      status: 'compliant',
      requirements: [
        { name: 'Data Processing Records', met: true },
        { name: 'Consent Management', met: true },
        { name: 'Data Subject Rights', met: true },
        { name: 'Breach Notification', met: true },
        { name: 'Privacy by Design', met: false }
      ]
    },
    {
      regulation: 'CCPA',
      score: 95,
      events: 32,
      lastAudit: '2024-01-10',
      status: 'compliant',
      requirements: [
        { name: 'Consumer Rights', met: true },
        { name: 'Data Deletion', met: true },
        { name: 'Opt-out Mechanisms', met: true },
        { name: 'Privacy Policy', met: true },
        { name: 'Data Inventory', met: true }
      ]
    },
    {
      regulation: 'SOX',
      score: 92,
      events: 28,
      lastAudit: '2024-01-08',
      status: 'warning',
      requirements: [
        { name: 'Internal Controls', met: true },
        { name: 'Financial Reporting', met: true },
        { name: 'Audit Trails', met: true },
        { name: 'Management Assessment', met: false },
        { name: 'External Auditor Review', met: true }
      ]
    },
    {
      regulation: 'HIPAA',
      score: 88,
      events: 15,
      lastAudit: '2024-01-05',
      status: 'warning',
      requirements: [
        { name: 'Access Controls', met: true },
        { name: 'Encryption', met: true },
        { name: 'Audit Logs', met: true },
        { name: 'Risk Assessment', met: false },
        { name: 'Training Records', met: false }
      ]
    }
  ];

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'compliant': return 'text-green-700 bg-green-100';
      case 'warning': return 'text-yellow-700 bg-yellow-100';
      case 'non-compliant': return 'text-red-700 bg-red-100';
      default: return 'text-gray-700 bg-gray-100';
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'compliant': return <CheckCircle className="w-4 h-4 text-green-600" />;
      case 'warning': return <AlertTriangle className="w-4 h-4 text-yellow-600" />;
      case 'non-compliant': return <AlertTriangle className="w-4 h-4 text-red-600" />;
      default: return <Shield className="w-4 h-4 text-gray-600" />;
    }
  };

  const overallScore = Math.round(complianceData.reduce((acc, metric) => acc + metric.score, 0) / complianceData.length);
  const totalEvents = complianceData.reduce((acc, metric) => acc + metric.events, 0);

  return (
    <div className="space-y-6">
      {/* Overview Cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div className="bg-theme-background rounded-lg border border-theme p-6">
          <div className="flex items-center justify-between mb-2">
            <div className="text-sm font-medium text-theme-secondary">Overall Compliance Score</div>
            <div className="p-1 bg-green-100 rounded">
              <Shield className="w-4 h-4 text-green-600" />
            </div>
          </div>
          <div className="text-3xl font-bold text-theme-primary">{overallScore}%</div>
          <div className="flex items-center gap-1 mt-1">
            <TrendingUp className="w-3 h-3 text-green-500" />
            <span className="text-xs text-green-600">+2% from last month</span>
          </div>
        </div>

        <div className="bg-theme-background rounded-lg border border-theme p-6">
          <div className="flex items-center justify-between mb-2">
            <div className="text-sm font-medium text-theme-secondary">Compliance Events</div>
            <div className="p-1 bg-blue-100 rounded">
              <Activity className="w-4 h-4 text-blue-600" />
            </div>
          </div>
          <div className="text-3xl font-bold text-theme-primary">{totalEvents}</div>
          <div className="text-xs text-theme-tertiary">in {timeRange.label.toLowerCase()}</div>
        </div>

        <div className="bg-theme-background rounded-lg border border-theme p-6">
          <div className="flex items-center justify-between mb-2">
            <div className="text-sm font-medium text-theme-secondary">Last Audit</div>
            <div className="p-1 bg-purple-100 rounded">
              <Calendar className="w-4 h-4 text-purple-600" />
            </div>
          </div>
          <div className="text-lg font-bold text-theme-primary">Jan 15, 2024</div>
          <div className="text-xs text-theme-tertiary">Next: Feb 15, 2024</div>
        </div>
      </div>

      {/* Compliance Details */}
      <div className="bg-theme-background rounded-lg border border-theme overflow-hidden">
        <div className="px-6 py-4 border-b border-theme">
          <h3 className="text-lg font-semibold text-theme-primary">Regulatory Compliance Status</h3>
          <p className="text-theme-secondary">Detailed compliance metrics for each regulation</p>
        </div>

        <div className="divide-y divide-theme">
          {complianceData.map((metric, index) => (
            <div key={index} className="p-6">
              <div className="flex items-center justify-between mb-4">
                <div className="flex items-center gap-3">
                  <div className="text-lg font-semibold text-theme-primary">{metric.regulation}</div>
                  <div className={`inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs font-medium ${getStatusColor(metric.status)}`}>
                    {getStatusIcon(metric.status)}
                    {metric.status.charAt(0).toUpperCase() + metric.status.slice(1).replace('-', ' ')}
                  </div>
                </div>
                
                <div className="flex items-center gap-4">
                  <div className="text-right">
                    <div className="text-2xl font-bold text-theme-primary">{metric.score}%</div>
                    <div className="text-xs text-theme-secondary">{metric.events} events</div>
                  </div>
                </div>
              </div>

              <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <div>
                  <h4 className="text-sm font-medium text-theme-secondary mb-3">Compliance Requirements</h4>
                  <div className="space-y-2">
                    {metric.requirements.map((req, reqIndex) => (
                      <div key={reqIndex} className="flex items-center justify-between py-2">
                        <span className="text-sm text-theme-primary">{req.name}</span>
                        <div className="flex items-center gap-1">
                          {req.met ? (
                            <CheckCircle className="w-4 h-4 text-green-600" />
                          ) : (
                            <AlertTriangle className="w-4 h-4 text-red-600" />
                          )}
                          <span className={`text-xs font-medium ${
                            req.met ? 'text-green-600' : 'text-red-600'
                          }`}>
                            {req.met ? 'Met' : 'Not Met'}
                          </span>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>

                <div>
                  <h4 className="text-sm font-medium text-theme-secondary mb-3">Recent Activity</h4>
                  <div className="space-y-2">
                    <div className="flex items-center justify-between py-2">
                      <span className="text-sm text-theme-primary">Last Audit Date</span>
                      <span className="text-sm text-theme-secondary">{metric.lastAudit}</span>
                    </div>
                    <div className="flex items-center justify-between py-2">
                      <span className="text-sm text-theme-primary">Compliance Events</span>
                      <span className="text-sm text-theme-secondary">{metric.events} this period</span>
                    </div>
                    <div className="flex items-center justify-between py-2">
                      <span className="text-sm text-theme-primary">Requirements Met</span>
                      <span className="text-sm text-theme-secondary">
                        {metric.requirements.filter(r => r.met).length}/{metric.requirements.length}
                      </span>
                    </div>
                  </div>
                </div>
              </div>

              {/* Progress Bar */}
              <div className="mt-4">
                <div className="flex items-center justify-between mb-1">
                  <span className="text-xs text-theme-secondary">Compliance Score</span>
                  <span className="text-xs font-medium text-theme-primary">{metric.score}%</span>
                </div>
                <div className="w-full bg-theme-surface rounded-full h-2">
                  <div 
                    className={`h-2 rounded-full transition-all duration-300 ${
                      metric.score >= 95 ? 'bg-green-500' :
                      metric.score >= 90 ? 'bg-yellow-500' : 'bg-red-500'
                    }`}
                    style={{ width: `${metric.score}%` }}
                  />
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Quick Actions */}
      <div className="bg-theme-background rounded-lg border border-theme p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Compliance Actions</h3>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <button className="flex items-center gap-3 p-4 bg-theme-surface rounded-lg border border-theme hover:bg-theme-surface-hover transition-colors duration-200">
            <FileText className="w-5 h-5 text-theme-secondary" />
            <div className="text-left">
              <div className="font-medium text-theme-primary">Generate Report</div>
              <div className="text-xs text-theme-secondary">Create compliance report</div>
            </div>
          </button>
          
          <button className="flex items-center gap-3 p-4 bg-theme-surface rounded-lg border border-theme hover:bg-theme-surface-hover transition-colors duration-200">
            <Download className="w-5 h-5 text-theme-secondary" />
            <div className="text-left">
              <div className="font-medium text-theme-primary">Export Data</div>
              <div className="text-xs text-theme-secondary">Download compliance data</div>
            </div>
          </button>
          
          <button className="flex items-center gap-3 p-4 bg-theme-surface rounded-lg border border-theme hover:bg-theme-surface-hover transition-colors duration-200">
            <Calendar className="w-5 h-5 text-theme-secondary" />
            <div className="text-left">
              <div className="font-medium text-theme-primary">Schedule Audit</div>
              <div className="text-xs text-theme-secondary">Plan next compliance audit</div>
            </div>
          </button>
        </div>
      </div>
    </div>
  );
};