import apiClient from '@/shared/services/apiClient';

export interface CodeReviewComment {
  id: string;
  file_path: string;
  line_start: number;
  line_end: number;
  comment_type: 'suggestion' | 'issue' | 'praise' | 'question';
  severity: 'critical' | 'warning' | 'info';
  content: string;
  suggested_fix: string | null;
  category: string;
  resolved: boolean;
  agent_id: string | null;
  created_at: string;
}

export const codeReviewApi = {
  getComments: async (reviewId: string): Promise<CodeReviewComment[]> => {
    const response = await apiClient.get(`/ai/teams/reviews/${reviewId}/comments`);
    return response.data?.data || [];
  },

  resolveComment: async (reviewId: string, commentId: string): Promise<void> => {
    await apiClient.patch(`/ai/teams/reviews/${reviewId}/comments/${commentId}`, { resolved: true });
  },

  addComment: async (reviewId: string, comment: Partial<CodeReviewComment>): Promise<CodeReviewComment> => {
    const response = await apiClient.post(`/ai/teams/reviews/${reviewId}/comments`, comment);
    return response.data?.data;
  }
};
