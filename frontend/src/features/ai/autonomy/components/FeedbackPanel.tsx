import React, { useState } from 'react';
import {
  Star, MessageSquare, ThumbsUp, ChevronDown, Plus,
} from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useFeedbackList, useSubmitFeedback, useTrustScores } from '../api/autonomyApi';
import type { AgentFeedback } from '../types/autonomy';

function getRatingStars(rating: number, size = 'h-3.5 w-3.5') {
  return Array.from({ length: 5 }, (_, i) => (
    <Star
      key={i}
      className={`${size} ${i < rating ? 'text-theme-warning fill-current' : 'text-theme-muted'}`}
    />
  ));
}

function getFeedbackTypeLabel(type: string): string {
  switch (type) {
    case 'execution_quality': return 'Execution';
    case 'proposal_quality': return 'Proposal';
    case 'communication_quality': return 'Communication';
    default: return type;
  }
}

const FEEDBACK_TYPES = [
  { value: 'execution_quality', label: 'Execution Quality' },
  { value: 'proposal_quality', label: 'Proposal Quality' },
  { value: 'communication_quality', label: 'Communication Quality' },
];

const StarInput: React.FC<{ value: number; onChange: (v: number) => void }> = ({ value, onChange }) => (
  <div className="flex items-center gap-1">
    {Array.from({ length: 5 }, (_, i) => (
      <button
        key={i}
        type="button"
        onClick={() => onChange(i + 1)}
        className="p-0.5"
      >
        <Star className={`h-5 w-5 ${i < value ? 'text-theme-warning fill-current' : 'text-theme-muted hover:text-theme-warning/50'}`} />
      </button>
    ))}
  </div>
);

const FeedbackForm: React.FC<{
  agents: Array<{ id: string; name: string }>;
  onSubmit: (data: { agent_id: string; feedback_type: string; rating: number; comment: string }) => void;
  onCancel: () => void;
  submitting: boolean;
}> = ({ agents, onSubmit, onCancel, submitting }) => {
  const [agentId, setAgentId] = useState('');
  const [feedbackType, setFeedbackType] = useState('execution_quality');
  const [rating, setRating] = useState(0);
  const [comment, setComment] = useState('');

  return (
    <div className="space-y-3 p-4 bg-theme-background border border-theme rounded-lg">
      <div className="flex gap-3">
        <select
          value={agentId}
          onChange={(e) => setAgentId(e.target.value)}
          className="flex-1 px-3 py-1.5 text-sm rounded-md border border-theme bg-theme-surface text-theme-primary"
        >
          <option value="">Select agent...</option>
          {agents.map(a => <option key={a.id} value={a.id}>{a.name}</option>)}
        </select>
        <select
          value={feedbackType}
          onChange={(e) => setFeedbackType(e.target.value)}
          className="flex-1 px-3 py-1.5 text-sm rounded-md border border-theme bg-theme-surface text-theme-primary"
        >
          {FEEDBACK_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
        </select>
      </div>
      <div className="flex items-center gap-2">
        <span className="text-sm text-theme-muted">Rating:</span>
        <StarInput value={rating} onChange={setRating} />
      </div>
      <textarea
        value={comment}
        onChange={(e) => setComment(e.target.value)}
        placeholder="Comment (optional)"
        rows={2}
        className="w-full px-3 py-1.5 text-sm rounded-md border border-theme bg-theme-surface text-theme-primary"
      />
      <div className="flex gap-2">
        <button
          onClick={() => onSubmit({ agent_id: agentId, feedback_type: feedbackType, rating, comment })}
          disabled={submitting || !agentId || rating === 0}
          className="btn-theme btn-theme-primary btn-theme-sm"
        >
          {submitting ? 'Submitting...' : 'Submit Feedback'}
        </button>
        <button onClick={onCancel} className="btn-theme btn-theme-secondary btn-theme-sm">Cancel</button>
      </div>
    </div>
  );
};

const FeedbackCard: React.FC<{ feedback: AgentFeedback; isExpanded: boolean; onToggle: () => void }> = ({ feedback, isExpanded, onToggle }) => (
  <div className="bg-theme-surface border border-theme rounded-lg overflow-hidden">
    {/* Collapsed */}
    <div
      onClick={onToggle}
      className="flex items-center gap-3 p-4 cursor-pointer hover:bg-theme-background/50 transition-colors"
    >
      <MessageSquare className="h-4 w-4 text-theme-info shrink-0" />
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium text-theme-primary">{feedback.agent?.name || 'Unknown Agent'}</span>
          <span className="px-1.5 py-0.5 text-xs rounded bg-theme-surface text-theme-muted">
            {getFeedbackTypeLabel(feedback.feedback_type)}
          </span>
          <span className="text-xs text-theme-muted">{new Date(feedback.created_at).toLocaleDateString()}</span>
        </div>
      </div>
      <div className="flex items-center gap-2 shrink-0">
        <div className="flex items-center gap-0.5">{getRatingStars(feedback.rating)}</div>
        {feedback.applied_to_trust && (
          <span title="Applied to trust"><ThumbsUp className="h-3.5 w-3.5 text-theme-success" /></span>
        )}
        <ChevronDown className={`h-4 w-4 text-theme-muted transition-transform ${isExpanded ? 'rotate-180' : ''}`} />
      </div>
    </div>

    {/* Expanded */}
    {isExpanded && (
      <div className="border-t border-theme p-4 space-y-3">
        {feedback.comment ? (
          <p className="text-sm text-theme-secondary">{feedback.comment}</p>
        ) : (
          <p className="text-sm text-theme-muted italic">No comment provided.</p>
        )}

        <div className="flex items-center gap-1">
          <span className="text-xs text-theme-muted mr-1">Rating:</span>
          {getRatingStars(feedback.rating, 'h-4 w-4')}
          <span className="text-xs text-theme-muted ml-1">({feedback.rating}/5)</span>
        </div>

        <div className="flex flex-wrap gap-4 text-xs text-theme-muted">
          {feedback.user?.email && <span>Submitted by: {feedback.user.email}</span>}
          {feedback.context_type && <span>Context: {feedback.context_type.split('::').pop()}</span>}
          {feedback.context_id && <span>ID: {feedback.context_id.substring(0, 8)}...</span>}
          <span>Created {new Date(feedback.created_at).toLocaleString()}</span>
          {feedback.applied_to_trust && (
            <span className="flex items-center gap-1 text-theme-success">
              <ThumbsUp className="h-3 w-3" /> Applied to trust score
            </span>
          )}
        </div>

        <p className="text-xs text-theme-muted italic">Feedback records are immutable once submitted.</p>
      </div>
    )}
  </div>
);

const FeedbackSummary: React.FC<{ feedbacks: AgentFeedback[] }> = ({ feedbacks }) => {
  if (feedbacks.length === 0) return null;

  const avgRating = feedbacks.reduce((sum, f) => sum + f.rating, 0) / feedbacks.length;
  const appliedCount = feedbacks.filter(f => f.applied_to_trust).length;
  const typeBreakdown = feedbacks.reduce((acc, f) => {
    acc[f.feedback_type] = (acc[f.feedback_type] || 0) + 1;
    return acc;
  }, {} as Record<string, number>);

  return (
    <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-4">
      <Card className="p-3">
        <p className="text-xs text-theme-muted">Total Feedback</p>
        <p className="text-xl font-semibold text-theme-primary">{feedbacks.length}</p>
      </Card>
      <Card className="p-3">
        <p className="text-xs text-theme-muted">Avg Rating</p>
        <div className="flex items-center gap-1">
          <p className="text-xl font-semibold text-theme-primary">{avgRating.toFixed(1)}</p>
          <Star className="h-4 w-4 text-theme-warning fill-current" />
        </div>
      </Card>
      <Card className="p-3">
        <p className="text-xs text-theme-muted">Applied to Trust</p>
        <p className="text-xl font-semibold text-theme-success">{appliedCount}</p>
      </Card>
      <Card className="p-3">
        <p className="text-xs text-theme-muted">Types</p>
        <div className="text-xs text-theme-secondary mt-1">
          {Object.entries(typeBreakdown).map(([type, count]) => (
            <span key={type} className="mr-2">{getFeedbackTypeLabel(type)}: {count}</span>
          ))}
        </div>
      </Card>
    </div>
  );
};

export const FeedbackPanel: React.FC = () => {
  const [agentFilter, setAgentFilter] = useState('');
  const [typeFilter, setTypeFilter] = useState('');
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  const { data: feedbacks, isLoading } = useFeedbackList(agentFilter ? { agent_id: agentFilter } : undefined);
  const { data: trustScores } = useTrustScores();
  const submitFeedback = useSubmitFeedback();
  const { addNotification } = useNotifications();

  const agents = (trustScores ?? []).map(ts => ({ id: ts.agent_id, name: ts.agent_name }));

  const handleSubmit = async (data: { agent_id: string; feedback_type: string; rating: number; comment: string }) => {
    try {
      await submitFeedback.mutateAsync({
        agent_id: data.agent_id,
        feedback_type: data.feedback_type,
        rating: data.rating,
        comment: data.comment || undefined,
      });
      addNotification({ type: 'success', message: 'Feedback submitted' });
      setShowCreate(false);
    } catch {
      addNotification({ type: 'error', message: 'Failed to submit feedback' });
    }
  };

  if (isLoading) return <LoadingSpinner size="lg" className="py-12" message="Loading feedback..." />;

  const safeFeedbacks = feedbacks ?? [];

  // Client-side type filter (API only supports agent_id filter)
  const filteredFeedbacks = typeFilter
    ? safeFeedbacks.filter(f => f.feedback_type === typeFilter)
    : safeFeedbacks;

  // Collect unique agents from feedback for the agent filter dropdown
  const feedbackAgents = Array.from(
    new Map(safeFeedbacks.filter(f => f.agent?.id).map(f => [f.agent!.id, f.agent!])).values()
  );

  return (
    <div className="space-y-4">
      <FeedbackSummary feedbacks={safeFeedbacks} />

      {/* Controls */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <select
            value={agentFilter}
            onChange={(e) => setAgentFilter(e.target.value)}
            className="px-3 py-1.5 text-sm rounded-md border border-theme bg-theme-surface text-theme-primary"
          >
            <option value="">All agents</option>
            {feedbackAgents.map(a => <option key={a.id} value={a.id}>{a.name}</option>)}
          </select>
          <select
            value={typeFilter}
            onChange={(e) => setTypeFilter(e.target.value)}
            className="px-3 py-1.5 text-sm rounded-md border border-theme bg-theme-surface text-theme-primary"
          >
            <option value="">All types</option>
            {FEEDBACK_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
          </select>
          <span className="text-sm text-theme-muted">{filteredFeedbacks.length} record{filteredFeedbacks.length !== 1 ? 's' : ''}</span>
        </div>
        <button
          onClick={() => setShowCreate(prev => !prev)}
          className="btn-theme btn-theme-primary btn-theme-sm flex items-center gap-1"
        >
          <Plus className="h-3.5 w-3.5" /> Submit Feedback
        </button>
      </div>

      {/* Create form */}
      {showCreate && (
        <FeedbackForm
          agents={agents}
          onSubmit={handleSubmit}
          onCancel={() => setShowCreate(false)}
          submitting={submitFeedback.isPending}
        />
      )}

      {/* Feedback list */}
      {filteredFeedbacks.length === 0 ? (
        <Card>
          <CardContent className="p-8 text-center text-theme-muted">
            <Star className="w-12 h-12 mx-auto mb-3 opacity-30" />
            <p>No feedback yet. Submit feedback on agent work to improve trust scores.</p>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-3">
          {filteredFeedbacks.map((feedback) => (
            <FeedbackCard
              key={feedback.id}
              feedback={feedback}
              isExpanded={expandedId === feedback.id}
              onToggle={() => setExpandedId(prev => prev === feedback.id ? null : feedback.id)}
            />
          ))}
        </div>
      )}
    </div>
  );
};
