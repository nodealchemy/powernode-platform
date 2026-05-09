import apiClient from '@/shared/services/apiClient';

export interface ChatConversation {
  id: string;
  agent_id: string;
  status: string;
  created_at: string;
  messages: ChatMessage[];
  ai_agent?: {
    id: string;
    name: string;
  };
}

export interface ChatMessage {
  id: string;
  content: string;
  sender_type: 'user' | 'ai' | 'system';
  created_at: string;
  metadata?: Record<string, unknown>;
}

export const chatApi = {
  getOrCreateConversation: async (agentId: string): Promise<ChatConversation> => {
    // Try to get active conversation first
    try {
      const response = await apiClient.get(`/ai/agents/${agentId}/conversations/active`);
      if (response.data?.data?.[0]) return response.data.data[0];
    } catch {
      /* no active conversation */
    }
    // Create new one
    const response = await apiClient.post(`/ai/agents/${agentId}/conversations`, {
      conversation: { title: 'Chat Session' }
    });
    return response.data?.data?.conversation;
  },

  sendMessage: async (agentId: string, conversationId: string, content: string): Promise<ChatMessage> => {
    const response = await apiClient.post(
      `/ai/agents/${agentId}/conversations/${conversationId}/send_message`,
      { message: { content } }
    );
    return response.data?.data?.assistant_message;
  },

  getHistory: async (agentId: string, conversationId: string): Promise<ChatMessage[]> => {
    const response = await apiClient.get(
      `/ai/agents/${agentId}/conversations/${conversationId}/messages`
    );
    return response.data?.data || [];
  },

  createConciergeConversation: async (): Promise<ChatConversation> => {
    const response = await apiClient.post('/ai/conversations/concierge');
    return response.data?.data?.conversation;
  },

  // M5 conversation unification — always creates a fresh
  // provisioning-typed conversation. Distinct from createConciergeConversation
  // which resumes the user's existing concierge conversation. The new
  // conversation appears in the sidebar's Provisioning group via the
  // conversation_type='provisioning' tag.
  //
  // Optional conversationId materializes a previously-pending tab at a
  // specific id — the lazy-creation flow generates a UUIDv7 client-side
  // when the user clicks the Provisioning quick-launch and only POSTs here
  // when they send their first message.
  createProvisioningConversation: async (conversationId?: string): Promise<ChatConversation> => {
    const body = conversationId ? { conversation_id: conversationId } : undefined;
    const response = await apiClient.post('/ai/conversations/provisioning', body);
    return response.data?.data?.conversation;
  },

  confirmConciergeAction: async (
    conversationId: string,
    actionType: string,
    actionParams: Record<string, unknown> = {}
  ): Promise<void> => {
    await apiClient.post(`/ai/conversations/${conversationId}/confirm_action`, {
      action_type: actionType,
      action_params: actionParams,
    });
  },
};
