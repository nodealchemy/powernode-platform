import React, { useCallback } from 'react';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { logger } from '@/shared/utils/logger';
import type { ChatCard } from '@/shared/types/ai';
import { A2uiRuntime } from './sdk/A2uiRuntime';
import type { A2UIAction } from './sdk/a2uiSdk';
import type { A2uiSurfacePayload } from './types';

/**
 * Renders an `a2ui_surface` ChatCard inline in the conversation — the A2UI
 * analogue of ChatProvisioningCardSlot. Feeds the stored A2UI v0.9 message
 * frames into the themed runtime and routes user actions back.
 *
 * Phase-1 next increment: `onAction` will POST to `chatApi.a2uiAction` →
 * backend action_router → agent re-invocation. For now it surfaces the action
 * so the interaction round-trip is observable end-to-end on the client.
 */
export interface A2uiChatCardSlotProps {
  card: ChatCard;
  conversationId?: string;
  messageId?: string;
}

export const A2uiChatCardSlot: React.FC<A2uiChatCardSlotProps> = ({ card, conversationId, messageId }) => {
  const { addNotification } = useNotifications();
  const payload = card.payload as unknown as A2uiSurfacePayload;

  const handleAction = useCallback(
    (action: A2UIAction) => {
      logger.info('A2UI surface action', { conversationId, messageId, action: action.name });
      addNotification({ type: 'info', message: `Action: ${action.name}` });
    },
    [addNotification, conversationId, messageId]
  );

  if (!payload?.messages?.length) return null;

  return (
    <div className="mt-3" data-testid="chat-card-a2ui_surface">
      <A2uiRuntime messages={payload.messages} surfaceId={payload.surface_id} onAction={handleAction} />
    </div>
  );
};

export default A2uiChatCardSlot;
