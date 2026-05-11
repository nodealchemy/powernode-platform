import { useEffect, useState, useCallback } from 'react';
import apiClient from '@/shared/services/apiClient';
import { Button } from '@/shared/components/ui/Button';
import { CheckIcon, XMarkIcon, ClockIcon } from '@heroicons/react/24/outline';
import type { ApprovalRequest } from '@/shared/types/approval';
import { logger } from '@/shared/utils/logger';

interface ApprovalRequestPanelProps {
  approvalRequestId: string;
  onResolved?: () => void;
}

const ENDPOINT = (id: string) => `/ai/autonomy/approvals/${id}`;

/**
 * Step-aware approve/reject UI for a single ApprovalRequest. Renders inside
 * NotificationDetailModal when a notification carries an approval_request_id.
 *
 * Shows step progress ("Step 2 of 3 — Awaiting Manager Approval"), executor
 * preview ("Delete SDWAN peer 10.0.0.5"), and disables Approve/Reject buttons
 * if the current user isn't in the current step's approvers list. After
 * action, refetches state — if more steps remain, displays "Approved your
 * step. Awaiting next step."; if completed/rejected, shows terminal status.
 */
export function ApprovalRequestPanel({ approvalRequestId, onResolved }: ApprovalRequestPanelProps) {
  const [request, setRequest] = useState<ApprovalRequest | null>(null);
  const [loading, setLoading] = useState(true);
  const [acting, setActing] = useState(false);
  const [comments, setComments] = useState('');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const fetchState = useCallback(() => {
    setLoading(true);
    apiClient
      .get(ENDPOINT(approvalRequestId))
      .then((res) => setRequest(res.data?.data || null))
      .catch((err) => {
        logger.error('Failed to load approval request', err);
        setErrorMessage('Failed to load approval request');
      })
      .finally(() => setLoading(false));
  }, [approvalRequestId]);

  useEffect(() => {
    fetchState();
  }, [fetchState]);

  const handleAction = async (decision: 'approve' | 'reject') => {
    setActing(true);
    setErrorMessage(null);
    try {
      const res = await apiClient.post(`${ENDPOINT(approvalRequestId)}/${decision}`, {
        comments: comments.trim() || undefined,
      });
      setRequest(res.data?.data || null);
      setComments('');
      const newStatus = res.data?.data?.status;
      if (newStatus === 'approved' || newStatus === 'rejected') {
        onResolved?.();
      }
    } catch (e) {
      setErrorMessage((e as Error).message || 'Action failed');
    } finally {
      setActing(false);
    }
  };

  if (loading) return <p className="text-sm text-theme-tertiary py-4">Loading…</p>;
  if (!request) return <p className="text-sm text-theme-danger py-4">Approval request not found</p>;

  const stepStatus = request.step_statuses?.[request.current_step];
  const isPending = request.status === 'pending';
  const isCompleted = ['approved', 'rejected', 'expired', 'cancelled'].includes(request.status);
  const canApprove = !!request.current_step_can_approve;
  const totalSteps = request.total_steps ?? request.step_statuses?.length ?? 1;
  const op = request.deferred_operation;

  return (
    <div className="space-y-4">
      {/* Header status bar */}
      <div className="rounded-lg border border-theme p-3 bg-theme-background-secondary">
        <div className="flex items-center gap-2 mb-1">
          <ClockIcon className="h-4 w-4 text-theme-warning" />
          <span className="text-sm font-semibold text-theme-primary">
            {isCompleted
              ? `Status: ${request.status}`
              : `Step ${request.current_step + 1} of ${totalSteps}: ${stepStatus?.step_name || 'Approval'}`}
          </span>
        </div>
        {isPending && stepStatus && (
          <p className="text-xs text-theme-tertiary">
            {stepStatus.current_approvals} of {stepStatus.required_approvals} approval(s) collected
            {request.expires_at && ` · expires ${new Date(request.expires_at).toLocaleString()}`}
          </p>
        )}
      </div>

      {/* Operation preview */}
      {op && (
        <div className="rounded-lg border border-theme p-3">
          <div className="text-xs text-theme-tertiary mb-1">Operation</div>
          <div className="text-sm font-medium text-theme-primary">
            {op.preview?.summary || op.action_category}
          </div>
          {op.preview?.impact && (
            <div className="text-xs text-theme-warning mt-1">Impact: {op.preview.impact}</div>
          )}
          {op.error_message && (
            <div className="text-xs text-theme-danger mt-1">Error: {op.error_message}</div>
          )}
        </div>
      )}

      {/* Decision history */}
      {request.decisions && request.decisions.length > 0 && (
        <div className="rounded-lg border border-theme p-3 max-h-32 overflow-y-auto">
          <div className="text-xs text-theme-tertiary mb-2">Prior decisions</div>
          <ul className="space-y-1">
            {request.decisions.map((d) => (
              <li key={d.id} className="text-xs text-theme-secondary">
                Step {d.step_number + 1}: <strong>{d.decision}</strong>
                {d.comments && <> — "{d.comments}"</>}
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* Action area */}
      {isPending && canApprove && (
        <div className="space-y-2">
          <textarea
            value={comments}
            onChange={(e) => setComments(e.target.value)}
            rows={2}
            placeholder="Optional comments…"
            className="w-full px-3 py-1.5 text-sm rounded border border-theme bg-theme-background text-theme-primary"
          />
          <div className="flex items-center justify-end gap-2">
            <Button
              variant="ghost"
              onClick={() => handleAction('reject')}
              disabled={acting}
            >
              <XMarkIcon className="h-4 w-4" /> Reject
            </Button>
            <Button
              variant="primary"
              onClick={() => handleAction('approve')}
              disabled={acting}
            >
              <CheckIcon className="h-4 w-4" /> Approve
            </Button>
          </div>
        </div>
      )}

      {isPending && !canApprove && (
        <p className="text-sm text-theme-tertiary italic">
          You don't have permission to approve at this step.
        </p>
      )}

      {isCompleted && (
        <p className="text-sm text-theme-secondary">
          {request.status === 'approved' && '✅ Approval complete — operation will execute.'}
          {request.status === 'rejected' && '❌ Approval rejected — operation cancelled.'}
          {request.status === 'expired' && '⏱ Approval expired.'}
          {request.status === 'cancelled' && '⏹ Approval cancelled.'}
        </p>
      )}

      {errorMessage && (
        <p className="text-sm text-theme-danger">{errorMessage}</p>
      )}
    </div>
  );
}
