import { renderHook, act, waitFor } from '@testing-library/react';
import { useAutonomyConfig } from './useAutonomyConfig';

const mockGet = jest.fn();
const mockPatch = jest.fn();
jest.mock('@/shared/services/apiClient', () => ({
  __esModule: true,
  default: {
    get: (...args: any[]) => mockGet(...args),
    patch: (...args: any[]) => mockPatch(...args),
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
