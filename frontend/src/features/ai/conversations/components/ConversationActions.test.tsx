import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { ConversationActions } from './ConversationActions';
import type { AiConversation } from '@/shared/types/ai';

// fc-37: exportConversation now returns the export payload inline
// ({conversation, export_format, exported_at}), not a download_url — this
// asserts the component downloads it via a client-side Blob instead of
// window.open()-ing a URL the server never sends.
const mockArchiveConversation = jest.fn();
const mockResumeConversation = jest.fn();
const mockExportConversation = jest.fn();
jest.mock('@/shared/services/ai', () => ({
  agentsApi: {
    archiveConversation: (...args: unknown[]) => mockArchiveConversation(...args),
    resumeConversation: (...args: unknown[]) => mockResumeConversation(...args),
    exportConversation: (...args: unknown[]) => mockExportConversation(...args),
  },
}));

const mockAddNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: mockAddNotification }),
}));

const mockDownloadJson = jest.fn();
jest.mock('@/shared/utils/downloadJson', () => ({
  downloadJson: (...args: unknown[]) => mockDownloadJson(...args),
}));

const baseConversation: AiConversation = {
  id: 'conv-1',
  title: 'Test',
  status: 'active',
  ai_agent: { id: 'agent-1', name: 'Assistant', agent_type: 'general' },
  metadata: { created_by: 'user-1', total_messages: 1, total_tokens: 10, total_cost: 0, last_activity: '2024-01-01T00:00:00Z' },
  created_at: '2024-01-01T00:00:00Z',
  updated_at: '2024-01-01T00:00:00Z',
};

describe('ConversationActions export (fc-37)', () => {
  beforeEach(() => {
    mockArchiveConversation.mockReset();
    mockResumeConversation.mockReset();
    mockExportConversation.mockReset();
    mockAddNotification.mockReset();
    mockDownloadJson.mockReset();
    mockExportConversation.mockResolvedValue({
      conversation: baseConversation,
      export_format: 'json',
      exported_at: '2024-01-02T00:00:00Z',
    });
  });

  it('exports via agentsApi.exportConversation(agentId, conversationId) and triggers a Blob download', async () => {
    render(
      <ConversationActions
        conversation={baseConversation}
        agentId="agent-1"
        canManageConversations
        canContinueConversations={false}
        onClose={jest.fn()}
      />
    );

    fireEvent.click(screen.getByText('Export'));

    await waitFor(() => {
      expect(mockExportConversation).toHaveBeenCalledWith('agent-1', 'conv-1');
    });
    expect(mockDownloadJson).toHaveBeenCalledWith(
      expect.objectContaining({ export_format: 'json' }),
      expect.stringContaining('conv-1')
    );
  });
});
