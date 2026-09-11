import React, { useState, useCallback, useEffect } from 'react';
import { CheckCircle, XCircle, Clock, AlertTriangle, ChevronDown, ChevronRight } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { OneShotRevealModal } from '@/shared/components/ui/OneShotRevealModal';
import { EntityLink } from '@/shared/components/entity';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotification } from '@/shared/hooks/useNotification';
import { useApproveAction, useRejectAction } from '../api/autonomyApi';
import { useLiveApprovalQueue } from '@/features/platform/status/hooks/useLiveApprovalQueue';
import { useApprovalRequestDetail } from '@/features/platform/status/hooks/useApprovalRequestDetail';
import {
  ApprovalChainSteps,
  ApprovalStepSummary,
} from '@/features/platform/status/components/approvals/ApprovalChainSteps';
import type { ApprovalRequest } from '../types/autonomy';

// The approval queue (C3b part 2). Approvals keep their own surface by the
// lead's C4 ruling; this panel gains what it never had: the chain, step by
// step, and a queue that stays current without a reload.
//
// ── PERMISSIONS, BOTH HIDDEN RATHER THAN DISABLED ───────────────────────────
//
// The list and detail reads need `ai.agents.read` (autonomy_controller.rb
// before_action). Without it the panel does not mount the live queue at all —
// its always-on poll would draw a 403 every 30 s — and says which permission is
// missing. Approve and Reject additionally need `ai.autonomy.approve`, AND the
// server's `current_step_can_approve` for THIS viewer on THIS step — on the list
// row, and on the detail once it has loaded. Offered only when it is true: on
// the permission alone, a holder who is not on the current step (or who has
// already decided it) saw buttons whose click drew a 422 (C3b2 review B1).

// The server's own words for a refused decision. A 422 says "Cannot approve
// this request"; before, nothing showed at all (C3b2 review B1).
const refusalReason = (error: unknown): string => {
  const body = (error as { response?: { data?: { error?: unknown } } } | null)?.response?.data;
  if (typeof body?.error === 'string' && body.error) return body.error;
  return error instanceof Error && error.message ? error.message : 'the server gave no reason';
};

const READ_PERMISSION = 'ai.agents.read';
const APPROVE_PERMISSION = 'ai.autonomy.approve';

const formatDate = (dateStr?: string): string => {
  if (!dateStr) return 'N/A';
  return new Date(dateStr).toLocaleString();
};

// A card must never render a blank title: action_type is only written by one
// producer, so fall through the category, the human description, and finally
// the source type (fleet-signal and gate-parked requests carried an empty
// header until this).
const approvalTitle = (request: ApprovalRequest): string =>
  request.action_type || request.action_category || request.description || request.source_type || 'Approval request';

const ApprovalCard: React.FC<{
  request: ApprovalRequest;
  isExpanded: boolean;
  onToggle: () => void;
  onRevealed: (values: Record<string, unknown>) => void;
  /** Holds `ai.autonomy.approve`. */
  canDecide: boolean;
  /** Bumped when a push names this request — the chain may have moved. */
  pushKey: number;
}> = ({ request, isExpanded, onToggle, onRevealed, canDecide, pushKey }) => {
  const approveMutation = useApproveAction();
  const rejectMutation = useRejectAction();
  const { showNotification } = useNotification();
  // Bumped after this viewer's own decision settles: an approval inside a
  // multi-approval step changes nothing the list row shows.
  const [ownDecisions, setOwnDecisions] = useState(0);

  const { detail, error: detailError } = useApprovalRequestDetail(request.id, {
    enabled: isExpanded,
    currentStep: request.current_step ?? null,
    status: request.status,
    refreshKey: `${pushKey}:${ownDecisions}`,
  });

  const handleApprove = () => {
    // The reveal goes straight to the panel, never into this card's state:
    // approving drops the row out of the pending queue, so this card unmounts
    // moments later and would take an unrecoverable secret with it.
    approveMutation.mutate(
      { id: request.id, onRevealedResult: onRevealed },
      {
        onSuccess: () => setOwnDecisions((count) => count + 1),
        onError: (error) => showNotification(`Approval failed: ${refusalReason(error)}`, 'error'),
      }
    );
  };

  const handleReject = () => {
    rejectMutation.mutate(
      { id: request.id },
      {
        onSuccess: () => setOwnDecisions((count) => count + 1),
        onError: (error) => showNotification(`Rejection failed: ${refusalReason(error)}`, 'error'),
      }
    );
  };

  const isPending = request.status === 'pending';
  // The server's answer for THIS viewer: the detail's once loaded (it is
  // re-read on every push for this request), otherwise the list row's.
  const canActOnStep = detail?.current_step_can_approve ?? request.current_step_can_approve;
  const showDecisionButtons = isPending && canDecide && canActOnStep === true;
  const viewerRefused = isPending && canDecide && canActOnStep === false;
  const requestDataKeys = Object.keys(request.request_data ?? {});
  const title = approvalTitle(request);
  // The description is the only operator-readable text on most rows; show it
  // collapsed unless it IS the title.
  const summary = request.description && request.description !== title ? request.description : undefined;

  const decisionButtons = (
    <>
      <button
        onClick={handleApprove}
        disabled={approveMutation.isPending}
        className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium rounded-md bg-theme-success-bg text-white hover:opacity-90 disabled:opacity-50"
      >
        <CheckCircle className="h-3.5 w-3.5" />
        Approve
      </button>
      <button
        onClick={handleReject}
        disabled={rejectMutation.isPending}
        className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium rounded-md bg-theme-error-bg text-white hover:opacity-90 disabled:opacity-50"
      >
        <XCircle className="h-3.5 w-3.5" />
        Reject
      </button>
    </>
  );

  return (
    <div className="rounded-lg bg-theme-surface border border-theme overflow-hidden">
      {/* Collapsed header */}
      <div
        onClick={onToggle}
        className="flex items-start gap-3 p-4 cursor-pointer hover:bg-theme-background/50 transition-colors"
      >
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); onToggle(); }}
          className="p-1 text-theme-secondary hover:text-theme-primary shrink-0"
          title={isExpanded ? 'Collapse' : 'Expand'}
        >
          {isExpanded ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
        </button>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <AlertTriangle className="h-4 w-4 text-theme-warning-fg shrink-0" />
            <span className="text-sm font-medium text-theme-primary truncate">
              {title}
            </span>
            {request.requires_human_session && (
              <Badge variant="default" size="sm">Needs a person</Badge>
            )}
          </div>
          {summary && (
            <p className="text-xs text-theme-secondary mb-1 line-clamp-2">{summary}</p>
          )}
          <div className="flex items-center gap-3 text-xs text-theme-tertiary">
            {request.agent_name && (
              <span className="flex items-center gap-1">
                Agent: <EntityLink type="agent" id={request.agent_id} label={request.agent_name} className="text-xs" />
              </span>
            )}
            <span>Created: {formatDate(request.created_at)}</span>
            <ApprovalStepSummary
              currentStep={request.current_step}
              totalSteps={request.total_steps}
              status={request.status}
            />
          </div>
        </div>
        <Badge
          variant={request.status === 'pending' ? 'warning' : request.status === 'approved' ? 'success' : 'default'}
          size="sm"
        >
          {request.status}
        </Badge>
      </div>

      {/* Expanded own-detail */}
      {isExpanded && (
        <div className="border-t border-theme p-4 space-y-3 bg-theme-background">
          <div className="grid grid-cols-2 md:grid-cols-3 gap-3 text-sm">
            <div>
              <p className="text-xs text-theme-tertiary">Action Type</p>
              <p className="text-theme-primary font-medium">{title}</p>
            </div>
            <div>
              <p className="text-xs text-theme-tertiary">Status</p>
              <p className="text-theme-primary font-medium capitalize">{request.status}</p>
            </div>
            {request.agent_name && (
              <div>
                <p className="text-xs text-theme-tertiary">Agent</p>
                <EntityLink type="agent" id={request.agent_id} label={request.agent_name} className="text-sm font-medium" />
              </div>
            )}
            <div>
              <p className="text-xs text-theme-tertiary">Requested</p>
              <p className="text-theme-primary font-medium">{formatDate(request.created_at)}</p>
            </div>
            {request.expires_at && (
              <div>
                <p className="text-xs text-theme-tertiary">Expires</p>
                <p className="text-theme-primary font-medium">{formatDate(request.expires_at)}</p>
              </div>
            )}
            {request.completed_at && (
              <div>
                <p className="text-xs text-theme-tertiary">Completed</p>
                <p className="text-theme-primary font-medium">{formatDate(request.completed_at)}</p>
              </div>
            )}
          </div>

          {request.description && (
            <div>
              <p className="text-xs text-theme-tertiary mb-1">Description</p>
              <p className="text-sm text-theme-secondary">{request.description}</p>
            </div>
          )}

          {request.requires_human_session && (
            <div data-human-session-note>
              <p className="text-xs text-theme-tertiary mb-1">Needs a person</p>
              <p className="text-sm text-theme-secondary">
                An agent or MCP client asked for this. It runs only after a person approves it here, in
                their own session, and then as the person who approves it.
              </p>
            </div>
          )}

          <div data-approval-chain-section>
            <p className="text-xs text-theme-tertiary mb-1">Approval chain</p>
            {detailError ? (
              // A failed read must never read as an empty chain.
              <p className="text-xs text-theme-warning-fg">
                Could not load the approval chain: {detailError}
              </p>
            ) : !detail ? (
              <p className="text-xs text-theme-secondary">Loading approval chain…</p>
            ) : (
              <ApprovalChainSteps
                stepStatuses={detail.step_statuses ?? []}
                currentStep={detail.current_step}
                requestStatus={detail.status}
                decisions={detail.decisions}
              />
            )}
          </div>

          {requestDataKeys.length > 0 && (
            <div>
              <p className="text-xs text-theme-tertiary mb-1">Request Data</p>
              <pre className="text-xs bg-theme-surface border border-theme rounded p-3 overflow-auto text-theme-secondary">
                {JSON.stringify(request.request_data, null, 2)}
              </pre>
            </div>
          )}

          {viewerRefused && (
            <p className="text-xs text-theme-tertiary">
              You cannot decide the current step: you are not one of its approvers, or you have
              already decided it.
            </p>
          )}

          {showDecisionButtons && <div className="flex gap-2 pt-1">{decisionButtons}</div>}
        </div>
      )}

      {/* Quick approve/reject also available without expanding */}
      {showDecisionButtons && !isExpanded && (
        <div className="flex gap-2 px-4 pb-4">{decisionButtons}</div>
      )}
    </div>
  );
};

const LiveApprovalQueue: React.FC<{ canDecide: boolean }> = ({ canDecide }) => {
  const { data: approvals, isLoading, lastPush } = useLiveApprovalQueue();
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set());
  // Transient, panel-scoped, and dropped the moment the operator acknowledges:
  // the plaintext is never persisted, logged or sent anywhere from here.
  //
  // A QUEUE, not a slot. Each card owns its own approve mutation, so nothing
  // stops an operator approving a second row while the first reveal is still
  // open — and a single slot would silently overwrite an unrecoverable value
  // they had not saved yet. Reveals are shown one at a time, in arrival order.
  const [revealQueue, setRevealQueue] = useState<Record<string, unknown>[]>([]);
  // Per-request push counters. A single "last push" key would change for EVERY
  // card on every push; this changes only for the request the push named.
  const [pushKeys, setPushKeys] = useState<Record<string, number>>({});

  useEffect(() => {
    if (!lastPush) return;
    setPushKeys((keys) => ({ ...keys, [lastPush.requestId]: (keys[lastPush.requestId] ?? 0) + 1 }));
  }, [lastPush]);

  const pushReveal = useCallback((values: Record<string, unknown>) => {
    // A named wrapper, not setRevealQueue itself: a state setter treats a
    // function argument as an updater.
    setRevealQueue((queue) => [...queue, values]);
  }, []);

  const toggleExpand = useCallback((id: string) => {
    setExpandedIds(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  }, []);

  if (isLoading) {
    return null;
  }

  return (
    <Card>
      <CardHeader title="Approval Queue" />
      <CardContent>
        {approvals && approvals.length > 0 ? (
          <div className="space-y-3">
            {approvals.map((request) => (
              <ApprovalCard
                key={request.id}
                request={request}
                isExpanded={expandedIds.has(request.id)}
                onToggle={() => toggleExpand(request.id)}
                onRevealed={pushReveal}
                canDecide={canDecide}
                pushKey={pushKeys[request.id] ?? 0}
              />
            ))}
          </div>
        ) : (
          <div className="py-6 text-center text-theme-tertiary">
            <Clock className="w-10 h-10 mx-auto mb-2 opacity-30" />
            <p className="text-sm">No pending approvals</p>
          </div>
        )}
      </CardContent>

      {/* Rendered by the panel, not the card: the approved row leaves the
          pending queue and unmounts its card while this is still open. */}
      {revealQueue.length > 0 && (
        <OneShotRevealModal
          title="Approved — shown once"
          values={revealQueue[0]}
          note="This approval ran an operation that minted new material. It is not stored and cannot be shown again."
          acknowledgeLabel="I have saved this somewhere safe"
          onDone={() => setRevealQueue((queue) => queue.slice(1))}
        />
      )}
    </Card>
  );
};

export const ApprovalQueuePanel: React.FC = () => {
  const { hasPermission } = usePermissions();

  if (!hasPermission(READ_PERMISSION)) {
    // Said, not blank: the capability exists and the missing permission is
    // named. The live queue is not mounted, so nothing polls a door that
    // would refuse.
    return (
      <Card>
        <CardHeader title="Approval Queue" />
        <CardContent>
          <p className="text-sm text-theme-tertiary">
            Viewing the approval queue needs <code>{READ_PERMISSION}</code>.
          </p>
        </CardContent>
      </Card>
    );
  }

  return <LiveApprovalQueue canDecide={hasPermission(APPROVE_PERMISSION)} />;
};
