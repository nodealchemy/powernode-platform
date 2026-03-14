import React from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft, ClipboardCheck, AlertCircle, CheckCircle } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { formatDistanceToNow, format } from 'date-fns';

export const AssessmentDetailPage: React.FC = () => {
  const { id: vendorId, assessmentId } = useParams<{ id: string; assessmentId: string }>();
  const navigate = useNavigate();

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Supply Chain', href: '/app/supply-chain' },
    { label: 'Vendors', href: '/app/supply-chain/vendors' },
    { label: 'Vendor', href: `/app/supply-chain/vendors/${vendorId}` },
    { label: 'Assessment' },
  ];

  const actions = [
    {
      id: 'back',
      label: 'Back to Vendor',
      onClick: () => navigate(`/app/supply-chain/vendors/${vendorId}`),
      variant: 'secondary' as const,
      icon: ArrowLeft,
    },
  ];

  const mockAssessment = {
    id: assessmentId,
    assessment_type: 'periodic',
    status: 'completed',
    security_score: 85,
    compliance_score: 90,
    operational_score: 78,
    overall_score: 84,
    finding_count: 5,
    valid_until: '2025-06-15',
    completed_at: '2025-01-15T10:30:00Z',
    created_at: '2025-01-10T09:00:00Z',
    findings: [
      {
        id: '1',
        severity: 'high',
        category: 'Access Control',
        title: 'Multi-factor authentication not enforced',
        description: 'MFA is available but not required for all users',
        recommendation: 'Enable mandatory MFA for all user accounts',
        status: 'open',
      },
      {
        id: '2',
        severity: 'medium',
        category: 'Data Protection',
        title: 'Encryption at rest not enabled for all storage',
        description: 'Some storage volumes are not encrypted',
        recommendation: 'Enable encryption at rest for all data storage',
        status: 'in_progress',
      },
      {
        id: '3',
        severity: 'low',
        category: 'Logging',
        title: 'Audit log retention period too short',
        description: 'Logs are only retained for 30 days',
        recommendation: 'Extend log retention to at least 90 days',
        status: 'resolved',
      },
    ],
  };

  const getScoreColor = (score: number) => {
    if (score >= 80) return 'text-theme-success';
    if (score >= 60) return 'text-theme-warning';
    return 'text-theme-error';
  };

  const getSeverityVariant = (severity: string) => {
    switch (severity) {
      case 'critical':
      case 'high':
        return 'danger';
      case 'medium':
        return 'warning';
      default:
        return 'info';
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'resolved':
        return <CheckCircle className="w-4 h-4 text-theme-success" />;
      case 'in_progress':
        return <AlertCircle className="w-4 h-4 text-theme-warning" />;
      default:
        return <AlertCircle className="w-4 h-4 text-theme-error" />;
    }
  };

  return (
    <PageContainer
      title="Risk Assessment"
      description={`${mockAssessment.assessment_type.replace('_', ' ')} assessment`}
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="mb-6 flex items-center gap-3">
        <ClipboardCheck className="w-5 h-5 text-theme-interactive-primary" />
        <Badge
          variant={
            mockAssessment.status === 'completed' ? 'success' :
            mockAssessment.status === 'in_progress' ? 'info' :
            'secondary'
          }
        >
          {mockAssessment.status.replace('_', ' ')}
        </Badge>
        {mockAssessment.completed_at && (
          <span className="text-sm text-theme-secondary">
            Completed {formatDistanceToNow(new Date(mockAssessment.completed_at), { addSuffix: true })}
          </span>
        )}
      </div>

      <div className="space-y-6">
        <Card className="p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">Assessment Scores</h3>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <div className="text-center p-4 bg-theme-muted rounded-lg">
              <p className={`text-3xl font-bold ${getScoreColor(mockAssessment.overall_score)}`}>
                {mockAssessment.overall_score}
              </p>
              <p className="text-sm text-theme-secondary mt-1">Overall</p>
            </div>
            <div className="text-center p-4 bg-theme-muted rounded-lg">
              <p className={`text-3xl font-bold ${getScoreColor(mockAssessment.security_score)}`}>
                {mockAssessment.security_score}
              </p>
              <p className="text-sm text-theme-secondary mt-1">Security</p>
            </div>
            <div className="text-center p-4 bg-theme-muted rounded-lg">
              <p className={`text-3xl font-bold ${getScoreColor(mockAssessment.compliance_score)}`}>
                {mockAssessment.compliance_score}
              </p>
              <p className="text-sm text-theme-secondary mt-1">Compliance</p>
            </div>
            <div className="text-center p-4 bg-theme-muted rounded-lg">
              <p className={`text-3xl font-bold ${getScoreColor(mockAssessment.operational_score)}`}>
                {mockAssessment.operational_score}
              </p>
              <p className="text-sm text-theme-secondary mt-1">Operational</p>
            </div>
          </div>
        </Card>

        <Card className="p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">Details</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <span className="text-sm text-theme-secondary">Assessment Type</span>
              <p className="text-theme-primary capitalize">
                {mockAssessment.assessment_type.replace('_', ' ')}
              </p>
            </div>
            <div>
              <span className="text-sm text-theme-secondary">Valid Until</span>
              <p className="text-theme-primary">
                {mockAssessment.valid_until
                  ? format(new Date(mockAssessment.valid_until), 'MMM d, yyyy')
                  : 'N/A'}
              </p>
            </div>
            <div>
              <span className="text-sm text-theme-secondary">Started</span>
              <p className="text-theme-primary">
                {format(new Date(mockAssessment.created_at), 'MMM d, yyyy')}
              </p>
            </div>
            <div>
              <span className="text-sm text-theme-secondary">Completed</span>
              <p className="text-theme-primary">
                {mockAssessment.completed_at
                  ? format(new Date(mockAssessment.completed_at), 'MMM d, yyyy')
                  : 'N/A'}
              </p>
            </div>
          </div>
        </Card>

        <Card className="p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">
            Findings ({mockAssessment.findings.length})
          </h3>
          <div className="space-y-4">
            {mockAssessment.findings.map((finding) => (
              <div
                key={finding.id}
                className="p-4 bg-theme-muted rounded-lg border border-theme"
              >
                <div className="flex items-start justify-between mb-2">
                  <div className="flex items-center gap-2">
                    {getStatusIcon(finding.status)}
                    <h4 className="font-medium text-theme-primary">{finding.title}</h4>
                  </div>
                  <div className="flex items-center gap-2">
                    <Badge variant={getSeverityVariant(finding.severity)} size="sm">
                      {finding.severity}
                    </Badge>
                    <Badge variant="outline" size="sm">
                      {finding.category}
                    </Badge>
                  </div>
                </div>
                <p className="text-sm text-theme-secondary mb-2">{finding.description}</p>
                <p className="text-sm text-theme-primary">
                  <span className="font-medium">Recommendation:</span> {finding.recommendation}
                </p>
              </div>
            ))}
          </div>
        </Card>
      </div>
    </PageContainer>
  );
};
