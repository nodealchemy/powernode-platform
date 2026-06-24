import { render, screen, waitFor, act } from '@testing-library/react';
import { SkillDetailPanel } from './SkillDetailPanel';
import { skillsApi } from '../services/skillsApi';
import type { AiSkill } from '../types';

// Regression: useEffect(loadSkill, [skillId]) had no cancellation guard, so
// rapidly switching skillId could render a stale skill when an earlier (slower)
// response resolved AFTER a later one (last-response-wins race). The fix adds a
// `cancelled` flag in the effect cleanup so only the latest skillId's response
// is applied.

jest.mock('../services/skillsApi', () => ({
  skillsApi: {
    getSkill: jest.fn(),
    getSkillAgents: jest.fn(),
    getCategoryIcon: jest.fn(() => '🧩'),
    getCategoryLabel: jest.fn(() => 'Category'),
    clone: jest.fn(),
    updateFromSourcePreview: jest.fn(),
    updateFromSource: jest.fn(),
  },
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ showNotification: jest.fn() }),
}));

jest.mock('react-router-dom', () => ({
  useNavigate: () => jest.fn(),
}));

// Keep the scoped-content seam light: non-global, non-clone, no extra UI.
jest.mock('@/features/content/scoped', () => ({
  isGlobal: () => false,
  isClone: () => false,
  CloneToCustomizeButton: () => null,
  UpdateFromSourceModal: () => null,
}));

function makeSkill(id: string, name: string): AiSkill {
  return {
    id,
    name,
    slug: id,
    description: `${name} description`,
    category: 'general' as AiSkill['category'],
    status: 'active' as AiSkill['status'],
    system_prompt: '',
    commands: [],
    connectors: [],
    knowledge_base: null,
    activation_rules: {},
    metadata: {},
    tags: [],
    is_system: false,
    is_enabled: true,
    version: '1.0.0',
    usage_count: 0,
    command_count: 0,
    connector_count: 0,
    has_knowledge_base: false,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    account_id: 'acct-1',
    cloned_from_id: null,
  };
}

describe('SkillDetailPanel last-response-wins race', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (skillsApi.getSkillAgents as jest.Mock).mockResolvedValue({ success: true, data: { agents: [] } });
  });

  it('ignores a stale (slow) response from a previous skillId', async () => {
    // Deferred control over each skill's getSkill resolution.
    let resolveA!: (v: unknown) => void;
    let resolveB!: (v: unknown) => void;
    const aPromise = new Promise((res) => { resolveA = res; });
    const bPromise = new Promise((res) => { resolveB = res; });

    (skillsApi.getSkill as jest.Mock).mockImplementation((id: string) => {
      if (id === 'A') return aPromise;
      if (id === 'B') return bPromise;
      return Promise.resolve({ success: false, error: 'unknown' });
    });

    const props = { onClose: jest.fn(), onUpdated: jest.fn() };

    const { rerender } = render(<SkillDetailPanel skillId="A" {...props} />);

    // Switch to B before A resolves.
    rerender(<SkillDetailPanel skillId="B" {...props} />);

    // B (the latest) resolves first...
    await act(async () => {
      resolveB({ success: true, data: { skill: makeSkill('B', 'Skill Bravo') } });
    });
    await waitFor(() => expect(screen.getByText('Skill Bravo')).toBeInTheDocument());

    // ...then A (the stale, slow one) resolves LAST. Its state update (if any)
    // is flushed inside act; it must NOT overwrite B.
    await act(async () => {
      resolveA({ success: true, data: { skill: makeSkill('A', 'Skill Alpha') } });
    });

    expect(screen.getByText('Skill Bravo')).toBeInTheDocument();
    expect(screen.queryByText('Skill Alpha')).not.toBeInTheDocument();
  });
});
