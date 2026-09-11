import { useCallback, useEffect, useRef, useState } from 'react';
import { useApprovalQueue } from '@/features/ai/autonomy/api/autonomyApi';
import { usePageWebSocket, type WebSocketDataUpdate } from '@/shared/hooks/usePageWebSocket';
import { usePolling } from '@/shared/hooks/usePolling';

// The approval queue, kept current without a reload (C3b, checklist row 34).
// The absorbed ApprovalQueuePanel read it once (`useQuery`, no refetch) and
// showed a queue that was only as fresh as the page load.
//
// ── THERE IS NO APPROVAL BROADCAST, SO THIS RIDES THE NOTIFICATIONS ─────────
//
// Nothing on the server broadcasts "approval created" or "approval decided" to
// an account. What does exist: `Ai::ApprovalRequest` fans out a Notification
// to every approver of the current step on create and on every step advance
// (`fan_out_step_notifications`), and each Notification is pushed on the
// viewer's own NotificationChannel stream. Every such notification carries
// `metadata.approval_request_id` — `ApprovalRequestNotifier#provenance_for`
// merges it LAST, so no content handler can strip it. That key is the
// discriminator; the notification TYPE is not, because a custom handler
// chooses its own.
//
// ── AND THAT IS WHY THE POLL NEVER STOPS ───────────────────────────────────
//
// The push reaches only the approvers of the step. It does not reach a viewer
// who holds `ai.autonomy.approve` but is not named on this step, and nothing is
// pushed when SOMEONE ELSE decides a request or the hourly expiry sweep expires
// it. So unlike the status page's poll, which stops once its channel is live,
// this one runs always: the push makes a new approval immediate for the people
// who must act on it, and the poll bounds everyone else's staleness. An
// account-scoped approval broadcast would let the poll become a fallback; it is
// a server change and is recorded as owed, not faked here.

export const APPROVAL_POLL_MS = 30000;

/** True when a NotificationChannel message is a new notification about an approval request. */
/** The approval request a NotificationChannel message is about, if it is about one. */
export const approvalRequestIdOf = (payload: unknown): string | undefined => {
  if (typeof payload !== 'object' || payload === null) return undefined;
  const notification = (payload as { notification?: unknown }).notification;
  if (typeof notification !== 'object' || notification === null) return undefined;
  const metadata = (notification as { metadata?: unknown }).metadata;
  if (typeof metadata !== 'object' || metadata === null) return undefined;
  const id = (metadata as { approval_request_id?: unknown }).approval_request_id;
  return typeof id === 'string' && id.length > 0 ? id : undefined;
};

export const isApprovalNotification = (payload: unknown): boolean =>
  approvalRequestIdOf(payload) !== undefined;

export function useLiveApprovalQueue() {
  const query = useApprovalQueue();
  const { refetch } = query;
  // WHICH request the last push named, not only when: an expanded card re-reads
  // its chain on a push for its own request (C3b1 review F1).
  const [lastPush, setLastPush] = useState<{ requestId: string; at: Date } | null>(null);

  const refresh = useCallback(() => {
    void refetch();
  }, [refetch]);

  const onDataUpdate = useCallback(
    (update: WebSocketDataUpdate) => {
      if (update.channel !== 'notifications' || update.type !== 'new_notification') return;
      const requestId = approvalRequestIdOf(update.data);
      if (!requestId) return;
      setLastPush({ requestId, at: update.timestamp });
      refresh();
    },
    [refresh]
  );

  // 'dashboard' subscribes the notifications channel and nothing else in core.
  const { isConnected } = usePageWebSocket({
    pageType: 'dashboard',
    subscribeToNotifications: true,
    onDataUpdate,
  });

  // A push sent while the cable was down is LOST, not queued: ActionCable does
  // not replay a stream. One read on reconnect, so a request raised during the
  // outage does not wait for the next poll tick (C3b1 review F5).
  const wasConnected = useRef(isConnected);
  useEffect(() => {
    if (isConnected && !wasConnected.current) refresh();
    wasConnected.current = isConnected;
  }, [isConnected, refresh]);

  usePolling(refresh, APPROVAL_POLL_MS, { deps: [refresh] });

  return {
    ...query,
    isConnected,
    lastPush,
    lastPushAt: lastPush?.at ?? null,
    pollMs: APPROVAL_POLL_MS,
  };
}

export default useLiveApprovalQueue;
