import { useCallback, useEffect, useRef, useState } from 'react';
import { useApprovalQueue } from '@/features/ai/autonomy/api/autonomyApi';
import { usePageWebSocket, type WebSocketDataUpdate } from '@/shared/hooks/usePageWebSocket';
import { usePolling } from '@/shared/hooks/usePolling';

// The approval queue, kept current without a reload (C3b, checklist row 34).
// The absorbed ApprovalQueuePanel read it once (`useQuery`, no refetch) and
// showed a queue that was only as fresh as the page load.
//
// ── TWO PUSHES, BOTH ON THE VIEWER'S OWN NOTIFICATIONCHANNEL STREAM ────────
//
// 1. The card. `Ai::ApprovalRequest` fans out a Notification to the approvers
//    of the current step on create, on every step advance, and on a decision
//    inside a step (leaving out whoever already decided it). Every such
//    notification carries `metadata.approval_request_id` —
//    `ApprovalRequestNotifier#provenance_for` merges it LAST, so no content
//    handler can strip it. That key is the discriminator; the notification TYPE
//    is not, because a custom handler chooses its own.
// 2. The queue refresh (C3b2 review B2). A decision inside a step also sends
//    `approval_request_changed` — a socket event, not a card — to every viewer
//    who may read the queue, the decider included, carrying the request id.
//
// ── AND STILL THE POLL NEVER STOPS ─────────────────────────────────────────
//
// A step advance and a resolution send cards only to the approvers of the new
// step (a resolution sends none), and the hourly expiry sweep sends nothing. So
// unlike the status page's poll, which stops once its channel is live, this one
// runs always: the pushes make the common changes immediate, and the poll
// bounds the staleness of the rest.

export const APPROVAL_POLL_MS = 30000;

/** The queue-refresh event's type (C3b2 review B2). */
export const APPROVAL_QUEUE_CHANGED = 'approval_request_changed';

/** The approval request a NotificationChannel message is about, if it is about one. */
export const approvalRequestIdOf = (payload: unknown): string | undefined => {
  if (typeof payload !== 'object' || payload === null) return undefined;
  // The queue refresh names its request at the top level, and only its own
  // type counts there: any other message's top-level id is not a claim.
  const direct = payload as { type?: unknown; approval_request_id?: unknown };
  if (direct.type === APPROVAL_QUEUE_CHANGED) {
    return typeof direct.approval_request_id === 'string' && direct.approval_request_id.length > 0
      ? direct.approval_request_id
      : undefined;
  }
  const notification = (payload as { notification?: unknown }).notification;
  if (typeof notification !== 'object' || notification === null) return undefined;
  const metadata = (notification as { metadata?: unknown }).metadata;
  if (typeof metadata !== 'object' || metadata === null) return undefined;
  const id = (metadata as { approval_request_id?: unknown }).approval_request_id;
  return typeof id === 'string' && id.length > 0 ? id : undefined;
};

/** True when a NotificationChannel message is about an approval request. */
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
      if (update.channel !== 'notifications') return;
      if (update.type !== 'new_notification' && update.type !== APPROVAL_QUEUE_CHANGED) return;
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
