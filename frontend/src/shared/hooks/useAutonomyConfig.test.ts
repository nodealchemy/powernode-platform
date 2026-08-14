import { renderHook, act, waitFor } from '@testing-library/react';
import { useAutonomyConfig } from './useAutonomyConfig';

const mockGet = jest.fn();
const mockPatch = jest.fn();
jest.mock('@/shared/services/apiClient', () => ({
  __esModule: true,
  default: {
    get: (...args: unknown[]) => mockGet(...args),
    patch: (...args: unknown[]) => mockPatch(...args),
  },
}));

const source = {
  fetchEndpoint: '/test/autonomy',
  updateEndpoint: '/test/autonomy',
  roleForAgent: (name: string) => name.toLowerCase(),
};

describe('useAutonomyConfig', () => {
  beforeEach(() => {
    mockGet.mockReset();
    mockPatch.mockReset();
  });

  it('fetches policies and exposes per-agent map', async () => {
    mockGet.mockResolvedValue({
      data: {
        data: {
          policies: {
            by_agent: {
              'Agent A': [
                { action_category: 'a.x', policy: 'auto_approve' },
                { action_category: 'a.y', policy: 'require_approval' },
              ],
            },
          },
        },
      },
    });

    const { result } = renderHook(() => useAutonomyConfig(source));

    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(result.current.agentNames).toEqual(['Agent A']);
    expect(result.current.getPolicy('Agent A', 'a.x')).toBe('auto_approve');
    expect(result.current.getPolicy('Agent A', 'a.y')).toBe('require_approval');
    expect(result.current.getPolicy('Agent A', 'unknown')).toBe('require_approval');
  });

  it('local overrides win until save() is called', async () => {
    mockGet.mockResolvedValue({
      data: { data: { policies: { by_agent: { 'A': [{ action_category: 'x', policy: 'auto_approve' }] } } } },
    });

    const { result } = renderHook(() => useAutonomyConfig(source));
    await waitFor(() => expect(result.current.loading).toBe(false));

    act(() => result.current.updatePolicy('A', 'x', 'block'));
    expect(result.current.getPolicy('A', 'x')).toBe('block');
    expect(result.current.isDirty).toBe(true);
  });

  it('save() PATCHes per-agent and clears local overrides', async () => {
    mockGet.mockResolvedValue({
      data: { data: { policies: { by_agent: { 'A': [{ action_category: 'x', policy: 'auto_approve' }] } } } },
    });
    mockPatch.mockResolvedValue({ data: { ok: true } });

    const { result } = renderHook(() => useAutonomyConfig(source));
    await waitFor(() => expect(result.current.loading).toBe(false));

    act(() => result.current.updatePolicy('A', 'x', 'block'));
    await act(async () => { await result.current.save(); });

    expect(mockPatch).toHaveBeenCalledWith('/test/autonomy', {
      policies: { x: 'block' },
      agent_role: 'a',
    });
    expect(result.current.isDirty).toBe(false);
    expect(result.current.getPolicy('A', 'x')).toBe('block');
  });

  // IMP-0874acd5b50c — the by_domain view. A settings panel that renders the
  // categories the SERVER returns needs both halves of this: the grouping
  // itself, and a current verb for rows the by_agent view left out (it keeps
  // only the buckets the endpoint declares, so a row owned by any other agent
  // is absent there).
  describe('by_domain', () => {
    const withDomains = {
      data: {
        data: {
          policies: {
            by_agent: {
              'Agent A': [{ action_category: 'a.x', policy: 'auto_approve' }],
            },
            by_domain: {
              alpha: [
                { action_category: 'a.x', agent_bucket: 'Agent A', policy: 'auto_approve' },
              ],
              beta: [
                { action_category: 'b.y', agent_bucket: 'Unlisted Agent', policy: 'notify_and_proceed' },
              ],
              empty: [],
            },
          },
        },
      },
    };

    it('exposes the server grouping verbatim, empty buckets included', async () => {
      mockGet.mockResolvedValue(withDomains);

      const { result } = renderHook(() => useAutonomyConfig(source));
      await waitFor(() => expect(result.current.loading).toBe(false));

      expect(Object.keys(result.current.domains)).toEqual(['alpha', 'beta', 'empty']);
      expect(result.current.domains.beta[0].action_category).toBe('b.y');
      expect(result.current.domains.empty).toEqual([]);
    });

    it('back-fills a policy for a bucket by_agent omitted', async () => {
      mockGet.mockResolvedValue(withDomains);

      const { result } = renderHook(() => useAutonomyConfig(source));
      await waitFor(() => expect(result.current.loading).toBe(false));

      // 'require_approval' is the miss default, so the seeded verb is what
      // distinguishes "read the row" from "fell through".
      expect(result.current.getPolicy('Unlisted Agent', 'b.y')).toBe('notify_and_proceed');
      expect(result.current.agentNames).toEqual(expect.arrayContaining(['Agent A', 'Unlisted Agent']));
    });

    it('does not disturb a payload that ships by_agent alone', async () => {
      mockGet.mockResolvedValue({
        data: { data: { policies: { by_agent: { A: [{ action_category: 'x', policy: 'block' }] } } } },
      });

      const { result } = renderHook(() => useAutonomyConfig(source));
      await waitFor(() => expect(result.current.loading).toBe(false));

      expect(result.current.domains).toEqual({});
      expect(result.current.getPolicy('A', 'x')).toBe('block');
    });
  });

  it('handles extension-shape (nested object) responses', async () => {
    mockGet.mockResolvedValue({
      data: {
        policies: {
          'Training Session Manager': {
            'demoext.create_session': { policy: 'auto_approve' },
          },
        },
      },
    });

    const { result } = renderHook(() => useAutonomyConfig(source));
    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(result.current.getPolicy('Training Session Manager', 'demoext.create_session')).toBe('auto_approve');
  });
});
