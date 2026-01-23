import React, { useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { Edit, PlayCircle, Send, ExternalLink, Shield, FileText, Database, CheckCircle, AlertCircle, Eye } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer } from '@/shared/components/ui/TabContainer';
import { RiskTierBadge } from '../components/shared/RiskTierBadge';
import { StatusBadge } from '../components/shared/StatusBadge';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useVendor, useUpdateVendor, useStartAssessment, useSendQuestionnaire } from '../hooks/useVendorRisk';
import { formatDistanceToNow, format } from 'date-fns';
import { EditVendorModal } from '../components/vendor/EditVendorModal';
import { StartAssessmentModal } from '../components/vendor/StartAssessmentModal';
import { SendQuestionnaireModal } from '../components/vendor/SendQuestionnaireModal';
import { VendorDocumentsPanel } from '../components/vendor/VendorDocumentsPanel';
import { useNotifications } from '@/shared/hooks/useNotifications';

export const VendorDetailPage: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [activeTab, setActiveTab] = useState('overview');
  const { vendor, loading, error, refresh } = useVendor(id || null);
  const [showEditModal, setShowEditModal] = useState(false);
  const [showAssessmentModal, setShowAssessmentModal] = useState(false);
  const [showQuestionnaireModal, setShowQuestionnaireModal] = useState(false);

  const updateVendorMutation = useUpdateVendor();
  const startAssessmentMutation = useStartAssessment();
  const sendQuestionnaireMutation = useSendQuestionnaire();
  const { showNotification } = useNotifications();

  const handleUpdateVendor = async (data: Record<string, unknown>) => {
    if (!id) return;
    try {
      await updateVendorMutation.mutateAsync({ id, data });
      showNotification('Vendor updated successfully', 'success');
      setShowEditModal(false);
      refresh();
    } catch {
      showNotification('Failed to update vendor', 'error');
    }
  };

  const handleStartAssessment = async (assessmentType: 'initial' | 'periodic' | 'incident' | 'renewal') => {
    if (!id) return;
    try {
      await startAssessmentMutation.mutateAsync({ vendorId: id, assessmentType });
      showNotification('Assessment started successfully', 'success');
      setShowAssessmentModal(false);
      refresh();
    } catch {
      showNotification('Failed to start assessment', 'error');
    }
  };

  const handleSendQuestionnaire = async (templateId: string) => {
    if (!id) return;
    try {
      await sendQuestionnaireMutation.mutateAsync({ vendorId: id, templateId });
      showNotification('Questionnaire sent successfully', 'success');
      setShowQuestionnaireModal(false);
      refresh();
    } catch {
      showNotification('Failed to send questionnaire', 'error');
    }
  };

  if (loading) {
    return (
      <div className="flex justify-center items-center h-64">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  if (error || !vendor) {
    return (
      <div className="bg-theme-error bg-opacity-10 text-theme-error p-4 rounded-lg">
        {error || 'Vendor not found'}
      </div>
    );
  }

  const tabs = [
    { id: 'overview', label: 'Overview' },
    { id: 'documents', label: 'Documents' },
    { id: 'assessments', label: 'Assessments', badge: vendor.assessments?.length || 0 },
    { id: 'questionnaires', label: 'Questionnaires', badge: vendor.questionnaires?.length || 0 },
    { id: 'monitoring', label: 'Monitoring Events', badge: vendor.monitoring_events?.length || 0 },
  ];

  const renderOverview = () => (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6 border border-theme">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Contact Information</h3>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="text-sm text-theme-secondary">Contact Name</label>
            <p className="text-theme-primary">{vendor.contact_name || 'Not specified'}</p>
          </div>
          <div>
            <label className="text-sm text-theme-secondary">Contact Email</label>
            <p className="text-theme-primary">{vendor.contact_email || 'Not specified'}</p>
          </div>
          <div>
            <label className="text-sm text-theme-secondary">Website</label>
            {vendor.website ? (
              <a
                href={vendor.website}
                target="_blank"
                rel="noopener noreferrer"
                className="text-theme-interactive-primary hover:underline flex items-center gap-1"
              >
                {vendor.website}
                <ExternalLink className="w-3 h-3" />
              </a>
            ) : (
              <p className="text-theme-muted">Not specified</p>
            )}
          </div>
        </div>
      </div>

      <div className="bg-theme-surface rounded-lg p-6 border border-theme">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Data Handling</h3>
        <div className="flex flex-wrap gap-3">
          {vendor.handles_pii && (
            <div className="flex items-center gap-2 bg-theme-info bg-opacity-10 text-theme-info px-4 py-2 rounded-lg">
              <Shield className="w-5 h-5" />
              <span className="font-medium">Handles PII</span>
            </div>
          )}
          {vendor.handles_phi && (
            <div className="flex items-center gap-2 bg-theme-warning bg-opacity-10 text-theme-warning px-4 py-2 rounded-lg">
              <FileText className="w-5 h-5" />
              <span className="font-medium">Handles PHI</span>
            </div>
          )}
          {vendor.handles_pci && (
            <div className="flex items-center gap-2 bg-theme-error bg-opacity-10 text-theme-error px-4 py-2 rounded-lg">
              <Database className="w-5 h-5" />
              <span className="font-medium">Handles PCI Data</span>
            </div>
          )}
          {!vendor.handles_pii && !vendor.handles_phi && !vendor.handles_pci && (
            <p className="text-theme-muted">No sensitive data handling declared</p>
          )}
        </div>
      </div>

      <div className="bg-theme-surface rounded-lg p-6 border border-theme">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Certifications</h3>
        {vendor.certifications && vendor.certifications.length > 0 ? (
          <div className="flex flex-wrap gap-2">
            {vendor.certifications.map((cert, index) => (
              <Badge key={index} variant="success" size="md">
                <CheckCircle className="w-3 h-3 mr-1" />
                {cert}
              </Badge>
            ))}
          </div>
        ) : (
          <p className="text-theme-muted">No certifications on file</p>
        )}
      </div>

      <div className="bg-theme-surface rounded-lg p-6 border border-theme">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Assessment Timeline</h3>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="text-sm text-theme-secondary">Last Assessment</label>
            <p className="text-theme-primary">
              {vendor.last_assessment_at
                ? format(new Date(vendor.last_assessment_at), 'MMM d, yyyy')
                : 'Never assessed'}
            </p>
          </div>
          <div>
            <label className="text-sm text-theme-secondary">Next Assessment Due</label>
            <p className="text-theme-primary">
              {vendor.next_assessment_due
                ? format(new Date(vendor.next_assessment_due), 'MMM d, yyyy')
                : 'Not scheduled'}
            </p>
          </div>
        </div>
      </div>
    </div>
  );

  const renderAssessments = () => (
    <div className="space-y-4">
      {vendor.assessments && vendor.assessments.length > 0 ? (
        vendor.assessments.map((assessment) => (
          <div key={assessment.id} className="bg-theme-surface rounded-lg p-6 border border-theme">
            <div className="flex items-start justify-between mb-4">
              <div>
                <h4 className="text-lg font-semibold text-theme-primary capitalize">
                  {assessment.assessment_type.replace('_', ' ')} Assessment
                </h4>
                <p className="text-sm text-theme-secondary">
                  {formatDistanceToNow(new Date(assessment.created_at), { addSuffix: true })}
                </p>
              </div>
              <div className="flex items-center gap-2">
                <Badge
                  variant={
                    assessment.status === 'completed'
                      ? 'success'
                      : assessment.status === 'in_progress'
                      ? 'info'
                      : 'secondary'
                  }
                >
                  {assessment.status.replace('_', ' ')}
                </Badge>
                <button
                  onClick={() => navigate(`/app/supply-chain/vendors/${id}/assessments/${assessment.id}`)}
                  className="text-theme-interactive-primary hover:text-theme-interactive-primary-hover"
                  title="View Details"
                >
                  <Eye className="w-4 h-4" />
                </button>
              </div>
            </div>

            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <div>
                <label className="text-sm text-theme-secondary">Security Score</label>
                <p className="text-2xl font-bold text-theme-primary">{assessment.security_score}</p>
              </div>
              <div>
                <label className="text-sm text-theme-secondary">Compliance Score</label>
                <p className="text-2xl font-bold text-theme-primary">{assessment.compliance_score}</p>
              </div>
              <div>
                <label className="text-sm text-theme-secondary">Operational Score</label>
                <p className="text-2xl font-bold text-theme-primary">{assessment.operational_score}</p>
              </div>
              <div>
                <label className="text-sm text-theme-secondary">Overall Score</label>
                <p className="text-2xl font-bold text-theme-interactive-primary">
                  {assessment.overall_score}
                </p>
              </div>
            </div>

            {assessment.finding_count > 0 && (
              <div className="mt-4 flex items-center gap-2 text-theme-warning">
                <AlertCircle className="w-4 h-4" />
                <span className="text-sm">{assessment.finding_count} findings identified</span>
              </div>
            )}
          </div>
        ))
      ) : (
        <div className="text-center py-12 text-theme-muted">
          No assessments have been conducted yet
        </div>
      )}
    </div>
  );

  const renderQuestionnaires = () => (
    <div className="space-y-4">
      {vendor.questionnaires && vendor.questionnaires.length > 0 ? (
        vendor.questionnaires.map((questionnaire) => (
          <div key={questionnaire.id} className="bg-theme-surface rounded-lg p-6 border border-theme">
            <div className="flex items-start justify-between mb-4">
              <div>
                <h4 className="text-lg font-semibold text-theme-primary">
                  {questionnaire.template_name}
                </h4>
                <p className="text-sm text-theme-secondary">
                  {questionnaire.sent_at
                    ? `Sent ${formatDistanceToNow(new Date(questionnaire.sent_at), { addSuffix: true })}`
                    : 'Not sent yet'}
                </p>
              </div>
              <div className="flex items-center gap-2">
                <Badge
                  variant={
                    questionnaire.status === 'completed'
                      ? 'success'
                      : questionnaire.status === 'in_progress'
                      ? 'info'
                      : questionnaire.status === 'sent'
                      ? 'warning'
                      : 'secondary'
                  }
                >
                  {questionnaire.status}
                </Badge>
                <button
                  onClick={() => navigate(`/app/supply-chain/vendors/${id}/questionnaires/${questionnaire.id}`)}
                  className="text-theme-interactive-primary hover:text-theme-interactive-primary-hover"
                  title="View Details"
                >
                  <Eye className="w-4 h-4" />
                </button>
              </div>
            </div>

            <div className="flex items-center gap-6">
              <div>
                <label className="text-sm text-theme-secondary">Progress</label>
                <p className="text-theme-primary font-medium">
                  {questionnaire.response_count} / {questionnaire.total_questions} questions
                </p>
              </div>
              {questionnaire.completed_at && (
                <div>
                  <label className="text-sm text-theme-secondary">Completed</label>
                  <p className="text-theme-primary">
                    {format(new Date(questionnaire.completed_at), 'MMM d, yyyy')}
                  </p>
                </div>
              )}
            </div>
          </div>
        ))
      ) : (
        <div className="text-center py-12 text-theme-muted">
          No questionnaires have been sent yet
        </div>
      )}
    </div>
  );

  const renderMonitoring = () => (
    <div className="space-y-4">
      {vendor.monitoring_events && vendor.monitoring_events.length > 0 ? (
        vendor.monitoring_events.map((event) => (
          <div key={event.id} className="bg-theme-surface rounded-lg p-4 border border-theme">
            <div className="flex items-start justify-between">
              <div className="flex-1">
                <div className="flex items-center gap-2 mb-2">
                  <Badge
                    variant={
                      event.severity === 'critical'
                        ? 'danger'
                        : event.severity === 'high'
                        ? 'warning'
                        : 'info'
                    }
                    size="xs"
                  >
                    {event.severity}
                  </Badge>
                  <span className="text-sm text-theme-secondary capitalize">
                    {event.event_type.replace('_', ' ')}
                  </span>
                </div>
                <p className="text-theme-primary">{event.message}</p>
              </div>
              <span className="text-sm text-theme-muted whitespace-nowrap ml-4">
                {formatDistanceToNow(new Date(event.created_at), { addSuffix: true })}
              </span>
            </div>
          </div>
        ))
      ) : (
        <div className="text-center py-12 text-theme-muted">No monitoring events recorded</div>
      )}
    </div>
  );

  return (
    <PageContainer
      title={vendor.name}
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'Supply Chain', href: '/app/supply-chain' },
        { label: 'Vendors', href: '/app/supply-chain/vendors' },
        { label: vendor.name },
      ]}
      actions={[
        {
          id: 'edit',
          label: 'Edit',
          onClick: () => setShowEditModal(true),
          variant: 'secondary',
          icon: Edit,
        },
        {
          id: 'send-questionnaire',
          label: 'Send Questionnaire',
          onClick: () => setShowQuestionnaireModal(true),
          variant: 'secondary',
          icon: Send,
        },
        {
          id: 'start-assessment',
          label: 'Start Assessment',
          onClick: () => setShowAssessmentModal(true),
          variant: 'primary',
          icon: PlayCircle,
        },
      ]}
    >
      <div className="mb-6 flex items-center gap-3">
        <Badge variant="secondary" size="md">
          {vendor.vendor_type.toUpperCase()}
        </Badge>
        <RiskTierBadge tier={vendor.risk_tier} />
        <StatusBadge status={vendor.status} />
        <div className="ml-auto">
          <span className="text-sm text-theme-secondary mr-2">Risk Score:</span>
          <span
            className={`text-2xl font-bold ${
              vendor.risk_score >= 80
                ? 'text-theme-error'
                : vendor.risk_score >= 60
                ? 'text-theme-warning'
                : vendor.risk_score >= 40
                ? 'text-theme-info'
                : 'text-theme-success'
            }`}
          >
            {vendor.risk_score}/100
          </span>
        </div>
      </div>

      <TabContainer tabs={tabs} activeTab={activeTab} onTabChange={setActiveTab} variant="underline" showContent={false} />
        <div className="mt-6">
          {activeTab === 'overview' && renderOverview()}
          {activeTab === 'documents' && <VendorDocumentsPanel vendorId={vendor.id} vendorName={vendor.name} />}
          {activeTab === 'assessments' && renderAssessments()}
          {activeTab === 'questionnaires' && renderQuestionnaires()}
          {activeTab === 'monitoring' && renderMonitoring()}
        </div>

      {vendor && showEditModal && (
        <EditVendorModal
          onClose={() => setShowEditModal(false)}
          onSave={handleUpdateVendor}
          vendor={{
            id: vendor.id,
            name: vendor.name,
            vendor_type: vendor.vendor_type,
            contact_name: vendor.contact_name,
            contact_email: vendor.contact_email,
            website: vendor.website,
            handles_pii: vendor.handles_pii,
            handles_phi: vendor.handles_phi,
            handles_pci: vendor.handles_pci,
            certifications: vendor.certifications || [],
          }}
        />
      )}

      {vendor && showAssessmentModal && (
        <StartAssessmentModal
          onClose={() => setShowAssessmentModal(false)}
          onStart={handleStartAssessment}
          vendorName={vendor.name}
        />
      )}

      {vendor && showQuestionnaireModal && (
        <SendQuestionnaireModal
          onClose={() => setShowQuestionnaireModal(false)}
          onSend={handleSendQuestionnaire}
          vendorName={vendor.name}
        />
      )}
    </PageContainer>
  );
};
