import React, { useState } from 'react';
import { X, Send, FileQuestion } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';

interface QuestionnaireTemplate {
  id: string;
  name: string;
  description: string;
  questionCount: number;
  category: string;
}

interface SendQuestionnaireModalProps {
  vendorName: string;
  onClose: () => void;
  onSend: (templateId: string) => Promise<void>;
}

const questionnaireTemplates: QuestionnaireTemplate[] = [
  {
    id: 'security-basic',
    name: 'Basic Security Assessment',
    description: 'Essential security controls and practices',
    questionCount: 25,
    category: 'Security',
  },
  {
    id: 'security-comprehensive',
    name: 'Comprehensive Security Review',
    description: 'In-depth security assessment covering all domains',
    questionCount: 85,
    category: 'Security',
  },
  {
    id: 'privacy-gdpr',
    name: 'GDPR Compliance',
    description: 'Data protection and privacy practices for GDPR',
    questionCount: 40,
    category: 'Privacy',
  },
  {
    id: 'compliance-soc2',
    name: 'SOC 2 Readiness',
    description: 'Trust service criteria evaluation',
    questionCount: 60,
    category: 'Compliance',
  },
  {
    id: 'vendor-general',
    name: 'General Vendor Assessment',
    description: 'Comprehensive vendor due diligence questionnaire',
    questionCount: 50,
    category: 'General',
  },
];

export const SendQuestionnaireModal: React.FC<SendQuestionnaireModalProps> = ({
  vendorName,
  onClose,
  onSend,
}) => {
  const [selectedTemplateId, setSelectedTemplateId] = useState<string | null>(null);
  const [sending, setSending] = useState(false);

  const handleSend = async () => {
    if (!selectedTemplateId) return;
    try {
      setSending(true);
      await onSend(selectedTemplateId);
      onClose();
    } catch {
      // Error is silently ignored to keep modal open
    } finally {
      setSending(false);
    }
  };

  const categoryColors: Record<string, string> = {
    Security: 'bg-theme-error/10 text-theme-error',
    Privacy: 'bg-theme-info/10 text-theme-info',
    Compliance: 'bg-theme-warning/10 text-theme-warning',
    General: 'bg-theme-muted/10 text-theme-secondary',
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      <div className="fixed inset-0 bg-black/50" onClick={onClose} />

      <div className="relative z-10 w-full max-w-lg max-h-[90vh] overflow-y-auto bg-theme-surface rounded-lg shadow-xl mx-4">
        <div className="sticky top-0 bg-theme-surface border-b border-theme px-6 py-4 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <FileQuestion className="w-5 h-5 text-theme-interactive-primary" />
            <h2 className="text-lg font-semibold text-theme-primary">Send Questionnaire</h2>
          </div>
          <button onClick={onClose} className="p-1 rounded hover:bg-theme-surface-hover">
            <X className="w-5 h-5 text-theme-secondary" />
          </button>
        </div>

        <div className="p-6">
          <div className="mb-6">
            <span className="text-sm text-theme-secondary">Sending to:</span>
            <p className="font-medium text-theme-primary">{vendorName}</p>
          </div>

          <div className="mb-4">
            <label className="block text-sm font-medium text-theme-secondary mb-3">
              Select Template
            </label>
            <div className="space-y-2">
              {questionnaireTemplates.map((template) => (
                <button
                  key={template.id}
                  onClick={() => setSelectedTemplateId(template.id)}
                  className={`w-full p-4 rounded-lg border text-left transition-colors ${
                    selectedTemplateId === template.id
                      ? 'border-theme-interactive-primary bg-theme-interactive-primary/10'
                      : 'border-theme hover:border-theme-border-hover'
                  }`}
                >
                  <div className="flex items-start justify-between mb-2">
                    <p className="font-medium text-theme-primary">{template.name}</p>
                    <Badge className={categoryColors[template.category]} size="sm">
                      {template.category}
                    </Badge>
                  </div>
                  <p className="text-sm text-theme-secondary">{template.description}</p>
                  <p className="text-xs text-theme-muted mt-2">
                    {template.questionCount} questions
                  </p>
                </button>
              ))}
            </div>
          </div>
        </div>

        <div className="sticky bottom-0 bg-theme-surface border-t border-theme px-6 py-4 flex justify-end gap-3">
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button
            variant="primary"
            onClick={handleSend}
            disabled={!selectedTemplateId || sending}
          >
            <Send className="w-4 h-4 mr-2" />
            {sending ? 'Sending...' : 'Send Questionnaire'}
          </Button>
        </div>
      </div>
    </div>
  );
};
