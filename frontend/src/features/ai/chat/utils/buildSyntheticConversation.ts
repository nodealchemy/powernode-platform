import type { AiConversation } from '@/shared/types/ai';
import type { ChatTab } from '../context/chatWindowTypes';

/**
 * Builds a minimal AiConversation from a ChatTab's stored metadata.
 *
 * Used as the *initial* render shape for the chat surface so it can
 * paint immediately after a tab activates, without waiting for a server
 * fetch. AgentConversationComponent's mount effect then calls
 * conversationsApi.getConversation(id) to load the full row, and stores
 * it in component-local state — derivations (isConcierge, isProvisioning,
 * isWorkspace) prefer the fetched copy over this synthetic one.
 *
 * Single source of truth — previously duplicated in ChatWindow.tsx and
 * SplitPanelContainer.tsx, which had to be kept in sync by hand. Adding
 * a new conversation_type discriminator without updating both copies was
 * the bug shape that hid the M5 'provisioning' greeting from the chat
 * surface even though the backend tag was correct.
 */
export function buildSyntheticConversation(tab: ChatTab): AiConversation {
  const conversation_type: 'agent' | 'team' | 'provisioning' =
    tab.isProvisioning ? 'provisioning' :
    tab.isWorkspace ? 'team' :
    'agent';

  return {
    id: tab.conversationId,
    title: tab.title,
    status: 'active',
    conversation_type,
    ai_agent: {
      id: tab.agentId,
      name: tab.agentName,
      agent_type: 'assistant',
      is_concierge: tab.isConcierge,
    },
    agent_team: tab.teamId
      ? { id: tab.teamId, name: tab.title, team_type: tab.isWorkspace ? 'workspace' : undefined }
      : undefined,
    metadata: {
      created_by: '',
      total_messages: 0,
      total_tokens: 0,
      total_cost: 0,
      last_activity: new Date().toISOString(),
    },
    created_at: new Date(tab.createdAt).toISOString(),
    updated_at: new Date().toISOString(),
  };
}
