import { buildSyntheticConversation } from './buildSyntheticConversation';
import type { ChatTab } from '../context/chatWindowTypes';

const baseTab = (overrides: Partial<ChatTab> = {}): ChatTab => ({
  id: 'tab-1',
  conversationId: 'conv-1',
  agentId: 'agent-1',
  agentName: 'Helper',
  title: 'My Chat',
  unreadCount: 0,
  createdAt: 1704067200000, // 2024-01-01T00:00:00.000Z
  ...overrides,
});

describe('buildSyntheticConversation', () => {
  describe('conversation_type discriminator (priority order)', () => {
    it("is 'provisioning' when isProvisioning, even if isWorkspace is also set", () => {
      expect(buildSyntheticConversation(baseTab({ isProvisioning: true })).conversation_type)
        .toBe('provisioning');
      expect(
        buildSyntheticConversation(baseTab({ isProvisioning: true, isWorkspace: true })).conversation_type
      ).toBe('provisioning');
    });

    it("is 'team' when isWorkspace (and not provisioning)", () => {
      expect(buildSyntheticConversation(baseTab({ isWorkspace: true })).conversation_type)
        .toBe('team');
    });

    it("defaults to 'agent'", () => {
      expect(buildSyntheticConversation(baseTab()).conversation_type).toBe('agent');
    });
  });

  describe('ai_agent', () => {
    it('mirrors the tab agent fields with agent_type assistant', () => {
      const conv = buildSyntheticConversation(
        baseTab({ agentId: 'a9', agentName: 'Concierge', isConcierge: true })
      );
      expect(conv.ai_agent).toEqual({
        id: 'a9',
        name: 'Concierge',
        agent_type: 'assistant',
        is_concierge: true,
      });
    });
  });

  describe('agent_team', () => {
    it('is undefined when the tab has no teamId', () => {
      expect(buildSyntheticConversation(baseTab()).agent_team).toBeUndefined();
    });

    it("sets team_type 'workspace' when teamId + isWorkspace", () => {
      const conv = buildSyntheticConversation(
        baseTab({ teamId: 'team-7', title: 'Eng Team', isWorkspace: true })
      );
      expect(conv.agent_team).toEqual({ id: 'team-7', name: 'Eng Team', team_type: 'workspace' });
    });

    it('leaves team_type undefined when teamId present but not a workspace', () => {
      const conv = buildSyntheticConversation(baseTab({ teamId: 'team-7' }));
      expect(conv.agent_team?.id).toBe('team-7');
      expect(conv.agent_team?.name).toBe('My Chat');
      expect(conv.agent_team?.team_type).toBeUndefined();
    });
  });

  describe('core fields', () => {
    it('maps id/title/status and derives created_at from the numeric createdAt', () => {
      const conv = buildSyntheticConversation(baseTab());
      expect(conv.id).toBe('conv-1');
      expect(conv.title).toBe('My Chat');
      expect(conv.status).toBe('active');
      expect(conv.created_at).toBe('2024-01-01T00:00:00.000Z');
      expect(typeof conv.updated_at).toBe('string');
      expect(conv.metadata.total_messages).toBe(0);
    });
  });
});
