import React from 'react';
import { CheckCircle, XCircle, Clock, AlertTriangle } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { useApprovalQueue, useApproveAction, useRejectAction } from '../api/autonomyApi';
import type { ApprovalRequest } from '../types/autonomy';

const formatDate = (dateStr?: string): string => {
  if (!dateStr) return 'N/A';
  return new Date(dateStr).toLocaleString();
};

const ApprovalCard: React.FC<{ request: ApprovalRequest }> = ({ request }) => {
  const approveMutation = useApproveAction();
  const rejectMutation = useRejectAction();

  const handleApprove = () => {
    approveMutation.mutate({ id: request.id });
  };

  const handleReject = () => {
    rejectMutation.mutate({ id: request.id });
  };

  const isPending = request.status === 'pending';

  return (
    <div className="p-4 rounded-lg bg-theme-surface border border-theme-border">
      <div className="flex items-start justify-between mb-3">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <AlertTriangle className="h-4 w-4 text-theme-warning" />
            <span className="text-sm font-medium text-theme-primary">
              {request.action_type}
            </span>
          </div>
          {request.agent_name && (
            <p className="text-xs text-theme-muted">Agent: {request.agent_name}</p>
          )}
          {request.description && (
            <p className="text-xs text-theme-muted mt-1">{request.description}</p>
          )}
        </div>
        <Badge
          variant={request.status === 'pending' ? 'warning' : request.status === 'approved' ? 'success' : 'default'}
          size="sm"
        >
          {request.status}
        </Badge>
      </div>

      <div className="flex items-center justify-between text-xs text-theme-muted">
        <span>Created: {formatDate(request.created_at)}</span>
        {request.expires_at && <span>Expires: {formatDate(request.expires_at)}</span>}
      </div>

      {isPending && (
        <div className="flex gap-2 mt-3">
          <button
            onClick={handleApprove}
            disabled={approveMutation.isPending}
            className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium rounded-md bg-theme-success text-white hover:opacity-90 disabled:opacity-50"
          >
            <CheckCircle className="h-3.5 w-3.5" />
            Approve
          </button>
          <button
            onClick={handleReject}
            disabled={rejectMutation.isPending}
            className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium rounded-md bg-theme-error text-white hover:opacity-90 disabled:opacity-50"
          >
            <XCircle className="h-3.5 w-3.5" />
            Reject
          </button>
        </div>
      )}
    </div>
  );
};

export const ApprovalQueuePanel: React.FC = () => {
  const { data: approvals, isLoading } = useApprovalQueue();

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
              <ApprovalCard key={request.id} request={request} />
            ))}
          </div>
        ) : (
          <div className="py-6 text-center text-theme-muted">
            <Clock className="w-10 h-10 mx-auto mb-2 opacity-30" />
            <p className="text-sm">No pending approvals</p>
          </div>
        )}
      </CardContent>
    </Card>
  );
};
