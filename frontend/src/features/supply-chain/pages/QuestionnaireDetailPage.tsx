import React from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft, FileQuestion, CheckCircle, Clock, AlertCircle } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { formatDistanceToNow } from 'date-fns';

export const QuestionnaireDetailPage: React.FC = () => {
  const { id: vendorId, questionnaireId } = useParams<{ id: string; questionnaireId: string }>();
  const navigate = useNavigate();

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Supply Chain', href: '/app/supply-chain' },
    { label: 'Vendors', href: '/app/supply-chain/vendors' },
    { label: 'Vendor', href: `/app/supply-chain/vendors/${vendorId}` },
    { label: 'Questionnaire' },
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

  const mockQuestionnaire = {
    id: questionnaireId,
    template_name: 'Comprehensive Security Review',
    status: 'in_progress',
    sent_at: '2025-01-10T09:00:00Z',
    completed_at: null,
    response_count: 45,
    total_questions: 85,
    sections: [
      {
        name: 'Access Control',
        total: 15,
        answered: 15,
        responses: [
          {
            question: 'Do you require multi-factor authentication for all users?',
            answer: 'Yes, MFA is mandatory for all user accounts.',
            compliant: true,
          },
          {
            question: 'How often are access reviews conducted?',
            answer: 'Quarterly for privileged access, annually for standard access.',
            compliant: true,
          },
        ],
      },
      {
        name: 'Data Protection',
        total: 20,
        answered: 18,
        responses: [
          {
            question: 'Is data encrypted at rest?',
            answer: 'Yes, using AES-256 encryption.',
            compliant: true,
          },
          {
            question: 'Is data encrypted in transit?',
            answer: 'Yes, TLS 1.3 is used for all communications.',
            compliant: true,
          },
        ],
      },
      {
        name: 'Incident Response',
        total: 12,
        answered: 12,
        responses: [
          {
            question: 'Do you have a documented incident response plan?',
            answer: 'Yes, reviewed and updated annually.',
            compliant: true,
          },
        ],
      },
      {
        name: 'Business Continuity',
        total: 10,
        answered: 0,
        responses: [],
      },
      {
        name: 'Compliance',
        total: 18,
        answered: 0,
        responses: [],
      },
      {
        name: 'Vendor Management',
        total: 10,
        answered: 0,
        responses: [],
      },
    ],
  };

  const progressPercent = Math.round(
    (mockQuestionnaire.response_count / mockQuestionnaire.total_questions) * 100
  );

  const getStatusVariant = (status: string) => {
    switch (status) {
      case 'completed':
        return 'success';
      case 'in_progress':
        return 'info';
      case 'sent':
        return 'warning';
      default:
        return 'secondary';
    }
  };

  return (
    <PageContainer
      title={mockQuestionnaire.template_name}
      description="Vendor security questionnaire responses"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="mb-6 flex items-center gap-3">
        <FileQuestion className="w-5 h-5 text-theme-interactive-primary" />
        <Badge variant={getStatusVariant(mockQuestionnaire.status)}>
          {mockQuestionnaire.status.replace('_', ' ')}
        </Badge>
        {mockQuestionnaire.sent_at && (
          <span className="text-sm text-theme-secondary">
            Sent {formatDistanceToNow(new Date(mockQuestionnaire.sent_at), { addSuffix: true })}
          </span>
        )}
      </div>

      <div className="space-y-6">
        <Card className="p-6">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-semibold text-theme-primary">Progress</h3>
            <span className="text-2xl font-bold text-theme-interactive-primary">
              {progressPercent}%
            </span>
          </div>
          <div className="w-full bg-theme-muted rounded-full h-3 mb-2">
            <div
              className="h-3 rounded-full bg-theme-interactive-primary transition-all"
              style={{ width: `${progressPercent}%` }}
            />
          </div>
          <p className="text-sm text-theme-secondary">
            {mockQuestionnaire.response_count} of {mockQuestionnaire.total_questions} questions answered
          </p>
        </Card>

        <Card className="p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">Section Progress</h3>
          <div className="space-y-3">
            {mockQuestionnaire.sections.map((section, index) => {
              const sectionProgress = section.total > 0
                ? Math.round((section.answered / section.total) * 100)
                : 0;
              const isComplete = section.answered === section.total;
              const isStarted = section.answered > 0;

              return (
                <div
                  key={index}
                  className="p-4 bg-theme-muted rounded-lg"
                >
                  <div className="flex items-center justify-between mb-2">
                    <div className="flex items-center gap-2">
                      {isComplete ? (
                        <CheckCircle className="w-5 h-5 text-theme-success" />
                      ) : isStarted ? (
                        <Clock className="w-5 h-5 text-theme-warning" />
                      ) : (
                        <AlertCircle className="w-5 h-5 text-theme-muted" />
                      )}
                      <span className="font-medium text-theme-primary">{section.name}</span>
                    </div>
                    <span className="text-sm text-theme-secondary">
                      {section.answered}/{section.total}
                    </span>
                  </div>
                  <div className="w-full bg-theme-surface rounded-full h-2">
                    <div
                      className={`h-2 rounded-full transition-all ${
                        isComplete ? 'bg-theme-success' : 'bg-theme-interactive-primary'
                      }`}
                      style={{ width: `${sectionProgress}%` }}
                    />
                  </div>
                </div>
              );
            })}
          </div>
        </Card>

        {mockQuestionnaire.sections.filter(s => s.responses.length > 0).map((section, index) => (
          <Card key={index} className="p-6">
            <h3 className="text-lg font-semibold text-theme-primary mb-4">{section.name}</h3>
            <div className="space-y-4">
              {section.responses.map((response, respIndex) => (
                <div
                  key={respIndex}
                  className={`p-4 rounded-lg border ${
                    response.compliant
                      ? 'bg-theme-success/10 border-theme-success/30'
                      : 'bg-theme-error/10 border-theme-error/30'
                  }`}
                >
                  <p className="font-medium text-theme-primary mb-2">{response.question}</p>
                  <p className="text-sm text-theme-secondary">{response.answer}</p>
                  <div className="mt-2">
                    <Badge variant={response.compliant ? 'success' : 'danger'} size="sm">
                      {response.compliant ? 'Compliant' : 'Non-Compliant'}
                    </Badge>
                  </div>
                </div>
              ))}
            </div>
          </Card>
        ))}
      </div>
    </PageContainer>
  );
};
