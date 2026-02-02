import React, { useState } from 'react';
import { X, ClipboardCheck, PlayCircle } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';

type AssessmentType = 'initial' | 'periodic' | 'incident' | 'renewal';

interface StartAssessmentModalProps {
  vendorName: string;
  onClose: () => void;
  onStart: (assessmentType: AssessmentType) => Promise<void>;
}

const assessmentTypes: { value: AssessmentType; label: string; description: string }[] = [
  {
    value: 'initial',
    label: 'Initial Assessment',
    description: 'First-time comprehensive security assessment for new vendors',
  },
  {
    value: 'periodic',
    label: 'Periodic Review',
    description: 'Regular scheduled assessment to maintain compliance',
  },
  {
    value: 'incident',
    label: 'Incident Response',
    description: 'Assessment triggered by a security incident or concern',
  },
  {
    value: 'renewal',
    label: 'Contract Renewal',
    description: 'Assessment before renewing vendor contract',
  },
];

export const StartAssessmentModal: React.FC<StartAssessmentModalProps> = ({
  vendorName,
  onClose,
  onStart,
}) => {
  const [selectedType, setSelectedType] = useState<AssessmentType>('periodic');
  const [starting, setStarting] = useState(false);

  const handleStart = async () => {
    try {
      setStarting(true);
      await onStart(selectedType);
      onClose();
    } catch {
      // Error is silently ignored to keep modal open
    } finally {
      setStarting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      <div className="fixed inset-0 bg-black/50" onClick={onClose} />

      <div className="relative z-10 w-full max-w-lg bg-theme-surface rounded-lg shadow-xl mx-4">
        <div className="border-b border-theme px-6 py-4 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <ClipboardCheck className="w-5 h-5 text-theme-interactive-primary" />
            <h2 className="text-lg font-semibold text-theme-primary">Start Assessment</h2>
          </div>
          <button onClick={onClose} className="p-1 rounded hover:bg-theme-surface-hover">
            <X className="w-5 h-5 text-theme-secondary" />
          </button>
        </div>

        <div className="p-6">
          <div className="mb-6">
            <span className="text-sm text-theme-secondary">Vendor:</span>
            <p className="font-medium text-theme-primary">{vendorName}</p>
          </div>

          <div className="mb-4">
            <label className="block text-sm font-medium text-theme-secondary mb-3">
              Assessment Type
            </label>
            <div className="space-y-2">
              {assessmentTypes.map((type) => (
                <button
                  key={type.value}
                  onClick={() => setSelectedType(type.value)}
                  className={`w-full p-4 rounded-lg border text-left transition-colors ${
                    selectedType === type.value
                      ? 'border-theme-interactive-primary bg-theme-interactive-primary/10'
                      : 'border-theme hover:border-theme-border-hover'
                  }`}
                >
                  <p className="font-medium text-theme-primary">{type.label}</p>
                  <p className="text-sm text-theme-secondary mt-1">{type.description}</p>
                </button>
              ))}
            </div>
          </div>
        </div>

        <div className="border-t border-theme px-6 py-4 flex justify-end gap-3">
          <Button variant="secondary" onClick={onClose} disabled={starting}>
            Cancel
          </Button>
          <Button variant="primary" onClick={handleStart} disabled={starting}>
            <PlayCircle className="w-4 h-4 mr-2" />
            {starting ? 'Starting...' : 'Start Assessment'}
          </Button>
        </div>
      </div>
    </div>
  );
};
