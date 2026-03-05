import React, { useState } from 'react';
import { ShieldCheck, CheckCircle2, XCircle, GitBranch, TestTube, Eye } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import type { Mission, FeatureSuggestion } from '../../types/mission';
import { phaseLabel } from '../../types/mission';

interface ApprovalGateModalProps {
  isOpen: boolean;
  mission: Mission;
  onApprove: (data: { comment?: string; selected_feature?: Record<string, unknown> }) => Promise<void>;
  onReject: (data: { comment?: string }) => Promise<void>;
  onClose: () => void;
}

const gateTitle = (phase: string): string => {
  switch (phase) {
    case 'awaiting_feature_approval': return 'Select Feature';
    case 'awaiting_prd_approval': return 'Review PRD';
    case 'awaiting_code_approval': return 'Review Code Changes';
    case 'previewing': return 'Preview & Approve';
    default: return 'Approval Required';
  }
};

const gateDescription = (phase: string): string => {
  switch (phase) {
    case 'awaiting_feature_approval': return 'Select a feature suggestion to implement, or reject to re-analyze.';
    case 'awaiting_prd_approval': return 'Review the generated PRD and task plan before execution begins.';
    case 'awaiting_code_approval': return 'Review the code changes and test results before deployment.';
    case 'previewing': return 'Preview the deployed application and approve for PR creation.';
    default: return 'Review and approve to continue the mission.';
  }
};

export const ApprovalGateModal: React.FC<ApprovalGateModalProps> = ({
  isOpen,
  mission,
  onApprove,
  onReject,
  onClose,
}) => {
  const [comment, setComment] = useState('');
  const [selectedFeatureIndex, setSelectedFeatureIndex] = useState<number | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const phase = mission.current_phase || '';
  const isFeatureGate = phase === 'awaiting_feature_approval';
  const suggestions = mission.feature_suggestions || [];

  const handleApprove = async () => {
    setSubmitting(true);
    try {
      const data: { comment?: string; selected_feature?: Record<string, unknown> } = {};
      if (comment.trim()) data.comment = comment.trim();
      if (isFeatureGate && selectedFeatureIndex !== null && suggestions[selectedFeatureIndex]) {
        data.selected_feature = suggestions[selectedFeatureIndex] as unknown as Record<string, unknown>;
      }
      await onApprove(data);
    } finally {
      setSubmitting(false);
    }
  };

  const handleReject = async () => {
    setSubmitting(true);
    try {
      await onReject({ comment: comment.trim() || undefined });
    } finally {
      setSubmitting(false);
    }
  };

  const canApprove = !isFeatureGate || selectedFeatureIndex !== null;

  const footer = (
    <>
      <Button
        variant="danger"
        onClick={handleReject}
        disabled={submitting}
      >
        <XCircle className="w-4 h-4 mr-1.5" />
        Reject
      </Button>
      <Button
        onClick={handleApprove}
        disabled={!canApprove || submitting}
        loading={submitting}
      >
        <CheckCircle2 className="w-4 h-4 mr-1.5" />
        Approve
      </Button>
    </>
  );

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={gateTitle(phase)}
      subtitle={phaseLabel(phase)}
      icon={<ShieldCheck />}
      maxWidth="lg"
      footer={footer}
    >
      <div className="space-y-4">
        <p className="text-sm text-theme-secondary">{gateDescription(phase)}</p>

        {/* Feature selection for feature approval gate */}
        {isFeatureGate && suggestions.length > 0 && (
          <div className="space-y-2">
            <label className="text-xs font-medium text-theme-secondary">Select a feature:</label>
            {suggestions.map((feature: FeatureSuggestion, i: number) => (
              <button
                key={i}
                onClick={() => setSelectedFeatureIndex(i)}
                className={`w-full p-3 rounded-lg border text-left transition-all ${
                  selectedFeatureIndex === i
                    ? 'border-theme-interactive-primary bg-theme-interactive-primary/5 ring-1 ring-theme-interactive-primary/30'
                    : 'border-theme bg-theme-surface hover:border-theme-interactive-primary/50'
                }`}
              >
                <div className="flex items-start justify-between">
                  <h4 className="text-sm font-medium text-theme-primary">{feature.title}</h4>
                  <span className="text-xs px-2 py-0.5 rounded bg-theme-interactive-primary/10 text-theme-interactive-primary ml-2">
                    {feature.complexity}
                  </span>
                </div>
                <p className="text-xs text-theme-secondary mt-1">{feature.description}</p>
              </button>
            ))}
          </div>
        )}

        {/* PRD preview for PRD approval */}
        {phase === 'awaiting_prd_approval' && Object.keys(mission.prd_json).length > 0 && (
          <div>
            <label className="text-xs font-medium text-theme-secondary">Generated PRD:</label>
            <pre className="mt-1 text-xs text-theme-primary bg-theme-surface p-3 rounded overflow-x-auto max-h-48">
              {JSON.stringify(mission.prd_json, null, 2)}
            </pre>
          </div>
        )}

        {/* Code review content for code approval gate */}
        {phase === 'awaiting_code_approval' && (
          <div className="space-y-3">
            {mission.branch_name && (
              <div className="flex items-center gap-2 p-2.5 bg-theme-surface rounded-lg border border-theme">
                <GitBranch className="w-4 h-4 text-theme-accent flex-shrink-0" />
                <span className="text-xs text-theme-secondary">Branch:</span>
                <code className="text-xs font-mono text-theme-primary">{mission.branch_name}</code>
              </div>
            )}

            {Object.keys(mission.test_result).length > 0 && (
              <div>
                <div className="flex items-center gap-1.5 mb-1">
                  <TestTube className="w-3.5 h-3.5 text-theme-secondary" />
                  <label className="text-xs font-medium text-theme-secondary">Test Results:</label>
                </div>
                <pre className="text-xs text-theme-primary bg-theme-surface p-3 rounded overflow-y-auto max-h-40 whitespace-pre-wrap break-words">
                  {JSON.stringify(mission.test_result, null, 2)}
                </pre>
              </div>
            )}

            {Object.keys(mission.review_result).length > 0 && (
              <div>
                <div className="flex items-center gap-1.5 mb-1">
                  <Eye className="w-3.5 h-3.5 text-theme-secondary" />
                  <label className="text-xs font-medium text-theme-secondary">Code Review:</label>
                </div>
                <pre className="text-xs text-theme-primary bg-theme-surface p-3 rounded overflow-y-auto max-h-40 whitespace-pre-wrap break-words">
                  {JSON.stringify(mission.review_result, null, 2)}
                </pre>
              </div>
            )}

            {Object.keys(mission.test_result).length === 0 && Object.keys(mission.review_result).length === 0 && (
              <p className="text-xs text-theme-tertiary italic">No test or review results available yet.</p>
            )}
          </div>
        )}

        {/* Preview gate content */}
        {phase === 'previewing' && mission.deployed_url && (
          <div className="p-2.5 bg-theme-surface rounded-lg border border-theme">
            <label className="text-xs font-medium text-theme-secondary">Preview URL:</label>
            <a
              href={mission.deployed_url}
              target="_blank"
              rel="noopener noreferrer"
              className="block text-sm text-theme-accent hover:underline mt-1"
            >
              {mission.deployed_url}
            </a>
          </div>
        )}

        {/* Comment */}
        <div>
          <label className="block text-xs font-medium text-theme-secondary mb-1">
            Comment <span className="text-theme-tertiary">(optional)</span>
          </label>
          <textarea
            value={comment}
            onChange={(e) => setComment(e.target.value)}
            placeholder="Add notes or feedback..."
            className="input-theme w-full min-h-[60px] resize-y text-sm"
            rows={2}
          />
        </div>
      </div>
    </Modal>
  );
};
