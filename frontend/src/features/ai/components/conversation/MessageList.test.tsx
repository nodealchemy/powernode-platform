import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { MessageList } from './MessageList';
import type { AiMessage } from '@/shared/types/ai';

// fc-37: confirmConciergeAction moved from chatApi to the canonical
// conversationsApi, same call shape. This asserts the migrated caller
// still passes the conversationId prop through, not e.g. the message id.
const mockConfirmConciergeAction = jest.fn();
jest.mock('@/shared/services/ai/ConversationsApiService', () => ({
  conversationsApi: {
    confirmConciergeAction: (...args: unknown[]) => mockConfirmConciergeAction(...args),
  },
}));

// Avoid pulling in remark-gfm/remark-breaks ESM (react-markdown itself is
// already globally mocked via jest.config's moduleNameMapper) and other
// heavy children unrelated to this test.
jest.mock('remark-gfm', () => ({ __esModule: true, default: () => {} }));
jest.mock('remark-breaks', () => ({ __esModule: true, default: () => {} }));
jest.mock('@/features/ai/chat/components/ChatStreamingRenderer', () => ({
  ChatStreamingRenderer: ({ content }: { content: string }) => <div>{content}</div>,
}));
jest.mock('@/features/ai/chat/components/MessageEditor', () => ({ MessageEditor: () => null }));
jest.mock('@/features/ai/chat/components/PlanApprovalActions', () => ({ PlanApprovalActions: () => null }));
jest.mock('@/features/ai/provisioning/ChatProvisioningCardSlot', () => ({ ChatProvisioningCardSlot: () => null }));
jest.mock('@/features/ai/a2ui', () => ({ A2uiChatCardSlot: () => null }));
jest.mock('@/shared/components/concierge/ConciergeActionCard', () => ({
  ConciergeActionCard: ({ onConfirm }: { onConfirm: (actionType: string, actionParams: Record<string, unknown>) => void }) => (
    <button onClick={() => onConfirm('approve', { note: 'go' })}>Confirm concierge action</button>
  ),
}));

// The concierge_action metadata shape uses action_context.action_type, which
// the shared ActionContext type doesn't declare (it's typed for the separate
// team-plan-approval flow) — MessageList.tsx itself reads it via a cast for
// the same reason; mirror that here rather than fighting the excess-property
// check on a strictly-typed object literal.
const baseMessage = {
  id: 'msg-1',
  sender_type: 'ai',
  content: 'Ready to provision infrastructure.',
  created_at: '2026-05-07T00:00:00Z',
  metadata: {
    concierge_action: 'provision_infrastructure',
    action_context: { action_type: 'provision_infrastructure', status: 'pending' },
    action_params: { region: 'us-east-1' },
  },
} as unknown as AiMessage;

const noop = () => {};
const noopAsync = async () => {};

function renderList(overrides: Partial<React.ComponentProps<typeof MessageList>> = {}) {
  return render(
    <MessageList
      messages={[baseMessage]}
      currentUser={{ id: 'user-1', name: 'Everett' }}
      editingMessageId={null}
      editSaving={false}
      typingUsers={new Set()}
      messagesEndRef={React.createRef<HTMLDivElement>() as React.RefObject<HTMLDivElement>}
      onCopy={noop}
      onRate={noop}
      onRegenerate={noop}
      onEdit={noop}
      onSetEditing={noop}
      onDelete={noop}
      onOpenThread={noop}
      onPlanAction={noopAsync}
      conversationId="conv-42"
      {...overrides}
    />
  );
}

describe('MessageList confirmConciergeAction (fc-37 migration)', () => {
  beforeEach(() => {
    mockConfirmConciergeAction.mockReset();
  });

  it('passes the conversationId prop, not the message id, to conversationsApi.confirmConciergeAction', () => {
    renderList();

    fireEvent.click(screen.getByText('Confirm concierge action'));

    expect(mockConfirmConciergeAction).toHaveBeenCalledWith('conv-42', 'approve', { note: 'go' });
  });
});
