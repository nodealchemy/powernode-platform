import { apiClient } from '@/shared/services/apiClient';

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
};
