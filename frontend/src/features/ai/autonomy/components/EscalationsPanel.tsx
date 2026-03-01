import React, { useState } from 'react';
import {
  AlertOctagon, CheckCircle, Eye, ArrowUp, ChevronDown,
} from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useEscalations, useAcknowledgeEscalation, useResolveEscalation } from '../api/autonomyApi';
import type { AgentEscalation, EscalationStatus } from '../types/autonomy';

function getSeverityBorderClass(severity: string): string {
  switch (severity) {
    case 'critical': return 'border-l-4 border-l-theme-error';
    case 'high': return 'border-l-4 border-l-theme-warning';
    case 'medium': return 'border-l-4 border-l-theme-info';
    default: return 'border-l-4 border-l-theme-muted';
  }
}

function getSeverityBadgeClass(severity: string): string {
  switch (severity) {
    case 'critical': return 'text-theme-error bg-theme-error/10';
    case 'high': return 'text-theme-warning bg-theme-warning/10';
    case 'medium': return 'text-theme-info bg-theme-info/10';
    default: return 'text-theme-muted bg-theme-surface';
  }
}

function getStatusBadge(status: EscalationStatus): { class: string; label: string } {
  switch (status) {
    case 'open': return { class: 'text-theme-error bg-theme-error/10', label: 'Open' };
    case 'acknowledged': return { class: 'text-theme-warning bg-theme-warning/10', label: 'Acknowledged' };
    case 'in_progress': return { class: 'text-theme-info bg-theme-info/10', label: 'In Progress' };
    case 'resolved': return { class: 'text-theme-success bg-theme-success/10', label: 'Resolved' };
    case 'auto_resolved': return { class: 'text-theme-success bg-theme-success/10', label: 'Auto-resolved' };
    default: return { class: 'text-theme-secondary bg-theme-surface', label: status };
  }
}

function getCountdownText(nextEscalation: string): string {
  const diff = new Date(nextEscalation).getTime() - Date.now();
  if (diff <= 0) return 'Imminent';
  const hours = Math.floor(diff / 3600000);
  const mins = Math.floor((diff % 3600000) / 60000);
  if (hours > 0) return `${hours}h ${mins}m`;
  return `${mins}m`;
}

const EscalationCard: React.FC<{
  escalation: AgentEscalation;
  isExpanded: boolean;
  onToggle: () => void;
  onAcknowledge: (id: string) => void;
  onResolve: (id: string, resolution?: string) => void;
  actionPending: boolean;
}> = ({ escalation, isExpanded, onToggle, onAcknowledge, onResolve, actionPending }) => {
  const [resolution, setResolution] = useState('');
  const statusBadge = getStatusBadge(escalation.status);
  const isActive = ['open', 'acknowledged', 'in_progress'].includes(escalation.status);

  return (
    <div className={`bg-theme-surface border border-theme rounded-lg overflow-hidden ${getSeverityBorderClass(escalation.severity)}`}>
      {/* Collapsed header */}
      <div
        onClick={onToggle}
        className="flex items-center gap-3 p-4 cursor-pointer hover:bg-theme-background/50 transition-colors"
      >
        <AlertOctagon className="h-4 w-4 shrink-0" />
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <h4 className="font-medium text-theme-primary truncate">{escalation.title}</h4>
            <span className={`px-2 py-0.5 text-xs rounded ${statusBadge.class}`}>{statusBadge.label}</span>
            <span className={`px-1.5 py-0.5 text-xs rounded ${getSeverityBadgeClass(escalation.severity)}`}>{escalation.severity}</span>
            <span className="px-1.5 py-0.5 text-xs rounded bg-theme-surface text-theme-muted">{escalation.escalation_type.replace('_', ' ')}</span>
          </div>
          <div className="flex items-center gap-3 text-xs text-theme-muted mt-0.5">
            {escalation.agent?.name && <span>from {escalation.agent.name}</span>}
            <span>Level {escalation.current_level}</span>
            {escalation.next_escalation_at && isActive && (
              <span className="flex items-center gap-1 text-theme-warning">
                <ArrowUp className="h-3 w-3" /> {getCountdownText(escalation.next_escalation_at)}
              </span>
            )}
          </div>
        </div>
        <ChevronDown className={`h-4 w-4 text-theme-muted shrink-0 transition-transform ${isExpanded ? 'rotate-180' : ''}`} />
      </div>

      {/* Expanded detail */}
      {isExpanded && (
        <div className="border-t border-theme p-4 space-y-4">
          {/* Full context */}
          {escalation.context && Object.keys(escalation.context).length > 0 && (
            <div>
              <h4 className="text-sm font-medium text-theme-primary mb-1">Context</h4>
              <div className="text-xs bg-theme-background border border-theme rounded p-3 space-y-1">
                {Object.entries(escalation.context).map(([key, value]) => (
                  <p key={key} className="text-theme-secondary">
                    <span className="font-medium">{key}: </span>
                    {typeof value === 'string' ? value : JSON.stringify(value)}
                  </p>
                ))}
              </div>
            </div>
          )}

          {/* Escalation chain */}
          <div className="flex items-center gap-2 text-xs text-theme-muted">
            <span className="font-medium text-theme-primary">Escalation Chain:</span>
            {Array.from({ length: escalation.current_level }, (_, i) => (
              <span key={i} className={`px-1.5 py-0.5 rounded ${i + 1 === escalation.current_level ? 'bg-theme-warning/20 text-theme-warning font-medium' : 'bg-theme-surface'}`}>
                L{i + 1}
              </span>
            ))}
            {escalation.next_escalation_at && isActive && (
              <span className="px-1.5 py-0.5 rounded bg-theme-surface border border-dashed border-theme text-theme-muted">
                L{escalation.current_level + 1}?
              </span>
            )}
          </div>

          {/* Metadata */}
          <div className="flex flex-wrap gap-4 text-xs text-theme-muted">
            {escalation.escalated_to?.email && <span>Escalated to: {escalation.escalated_to.email}</span>}
            {escalation.timeout_hours && <span>Timeout: {escalation.timeout_hours}h</span>}
            {escalation.next_escalation_at && isActive && (
              <span>Next escalation: {new Date(escalation.next_escalation_at).toLocaleString()}</span>
            )}
            <span>Created {new Date(escalation.created_at).toLocaleString()}</span>
            {escalation.acknowledged_at && <span>Acknowledged {new Date(escalation.acknowledged_at).toLocaleString()}</span>}
            {escalation.resolved_at && <span>Resolved {new Date(escalation.resolved_at).toLocaleString()}</span>}
          </div>

          {/* Actions */}
          {isActive ? (
            <div className="space-y-3">
              <div className="flex gap-2">
                {escalation.status === 'open' && (
                  <button
                    onClick={() => onAcknowledge(escalation.id)}
                    disabled={actionPending}
                    className="btn-theme btn-theme-warning btn-theme-sm flex items-center gap-1"
                  >
                    <Eye className="h-3 w-3" /> Acknowledge
                  </button>
                )}
              </div>
              {/* Inline resolve form */}
              <div className="flex gap-2">
                <input
                  type="text"
                  value={resolution}
                  onChange={(e) => setResolution(e.target.value)}
                  placeholder="Resolution notes (optional)..."
                  className="flex-1 px-3 py-1.5 text-sm rounded-md border border-theme bg-theme-surface text-theme-primary"
                />
                <button
                  onClick={() => { onResolve(escalation.id, resolution || undefined); setResolution(''); }}
                  disabled={actionPending}
                  className="btn-theme btn-theme-success btn-theme-sm flex items-center gap-1"
                >
                  <CheckCircle className="h-3 w-3" /> Resolve
                </button>
              </div>
            </div>
          ) : (
            <p className="text-xs text-theme-muted italic">
              Resolved escalations cannot be reopened.
            </p>
          )}
        </div>
      )}
    </div>
  );
};

export const EscalationsPanel: React.FC = () => {
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const { data: escalations, isLoading } = useEscalations(statusFilter ? { status: statusFilter } : undefined);
  const acknowledgeMutation = useAcknowledgeEscalation();
  const resolveMutation = useResolveEscalation();
  const { addNotification } = useNotifications();

  const handleAcknowledge = async (id: string) => {
    try {
      await acknowledgeMutation.mutateAsync(id);
      addNotification({ type: 'success', message: 'Escalation acknowledged' });
    } catch {
      addNotification({ type: 'error', message: 'Failed to acknowledge escalation' });
    }
  };

  const handleResolve = async (id: string, resolution?: string) => {
    try {
      await resolveMutation.mutateAsync({ id, resolution });
      addNotification({ type: 'success', message: 'Escalation resolved' });
    } catch {
      addNotification({ type: 'error', message: 'Failed to resolve escalation' });
    }
  };

  if (isLoading) return <LoadingSpinner size="lg" className="py-12" message="Loading escalations..." />;

  const safeEscalations = escalations ?? [];
  const openCount = safeEscalations.filter(e => ['open', 'acknowledged', 'in_progress'].includes(e.status)).length;
  const actionPending = acknowledgeMutation.isPending || resolveMutation.isPending;

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3">
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          className="px-3 py-1.5 text-sm rounded-md border border-theme bg-theme-surface text-theme-primary"
        >
          <option value="">All statuses</option>
          <option value="open">Open</option>
          <option value="acknowledged">Acknowledged</option>
          <option value="in_progress">In Progress</option>
          <option value="resolved">Resolved</option>
          <option value="auto_resolved">Auto-resolved</option>
        </select>
        {openCount > 0 && (
          <span className="px-2 py-1 text-xs rounded bg-theme-error/10 text-theme-error">
            {openCount} active
          </span>
        )}
      </div>

      {safeEscalations.length === 0 ? (
        <Card>
          <CardContent className="p-8 text-center text-theme-muted">
            <AlertOctagon className="w-12 h-12 mx-auto mb-3 opacity-30" />
            <p>No escalations found. Agents escalate when they encounter issues they cannot resolve.</p>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-3">
          {safeEscalations.map((escalation) => (
            <EscalationCard
              key={escalation.id}
              escalation={escalation}
              isExpanded={expandedId === escalation.id}
              onToggle={() => setExpandedId(prev => prev === escalation.id ? null : escalation.id)}
              onAcknowledge={handleAcknowledge}
              onResolve={handleResolve}
              actionPending={actionPending}
            />
          ))}
        </div>
      )}
    </div>
  );
};
