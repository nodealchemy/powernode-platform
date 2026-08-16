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

  // A payload shape that ships no row identity at all — the nested-object
  // extension shape's sibling. The category and the verb are all the server can
  // be given, and save() must still go out rather than being suppressed.
  it('save() PATCHes and clears local overrides when rows carry no identity', async () => {
    mockGet.mockResolvedValue({
      data: { data: { policies: { by_agent: { 'A': [{ action_category: 'x', policy: 'auto_approve' }] } } } },
    });
    mockPatch.mockResolvedValue({ data: { ok: true } });

    const { result } = renderHook(() => useAutonomyConfig(source));
    await waitFor(() => expect(result.current.loading).toBe(false));

    act(() => result.current.updatePolicy('A', 'x', 'block'));
    await act(async () => { await result.current.save(); });

    expect(mockPatch).toHaveBeenCalledWith('/test/autonomy', {
      updates: [{ action_category: 'x', policy: 'block' }],
    });
    expect(result.current.isDirty).toBe(false);
    expect(result.current.getPolicy('A', 'x')).toBe('block');
  });

  // IMP-bef43160636f — what save() puts ON THE WIRE.
  //
  // These pin the request body literally, because the body is a cross-language
  // contract with `System::AutonomyActions#update` and nothing in this suite
  // can execute the Ruby side. The server half is pinned by
  // extensions/system/server/spec/controllers/api/v1/system/
  // autonomy_panel_write_coherence_spec.rb; a rename on ONE side is only caught
  // by the two literals disagreeing, so both are deliberately spelled out
  // rather than derived.
  describe('save() request contract', () => {
    // Rows as `serialize_policy` actually ships them: every one carries the
    // `scope` + `agent_id` that identify WHICH row the control was rendered
    // from. Editing a control has to write back to that row — a body naming
    // only the category lands a scope-"global" row, and
    // Ai::InterventionPolicy#specificity_key ranks `ai_agent_id.present?`
    // ABOVE priority, so such a row can never outrank the agent-scoped one the
    // seeds created. The operator's change would be permanently decorative.
    const identified = {
      data: {
        data: {
          policies: {
            by_agent: {
              'Fleet Autonomy': [
                {
                  action_category: 'system.sdwan_peer_remediate',
                  policy: 'notify_and_proceed',
                  scope: 'agent',
                  agent_id: 'agent-fleet-uuid',
                },
              ],
            },
            by_domain: {
              sdwan: [
                {
                  action_category: 'system.sdwan_peer_remediate',
                  agent_bucket: 'Fleet Autonomy',
                  policy: 'notify_and_proceed',
                  scope: 'agent',
                  agent_id: 'agent-fleet-uuid',
                },
                {
                  action_category: 'sdwan.peer_delete',
                  agent_bucket: 'Manual Operations',
                  policy: 'require_approval',
                  scope: 'action_type',
                  agent_id: null,
                },
              ],
            },
          },
        },
      },
    };

    it('PATCHes the updates array the server parses, carrying each row identity', async () => {
      mockGet.mockResolvedValue(identified);
      mockPatch.mockResolvedValue({ data: { ok: true } });

      const { result } = renderHook(() => useAutonomyConfig(source));
      await waitFor(() => expect(result.current.loading).toBe(false));

      act(() =>
        result.current.updatePolicy('Fleet Autonomy', 'system.sdwan_peer_remediate', 'auto_approve')
      );
      await act(async () => {
        await result.current.save();
      });

      expect(mockPatch).toHaveBeenCalledTimes(1);
      expect(mockPatch).toHaveBeenCalledWith('/test/autonomy', {
        updates: [
          {
            action_category: 'system.sdwan_peer_remediate',
            policy: 'auto_approve',
            scope: 'agent',
            agent_id: 'agent-fleet-uuid',
          },
        ],
      });
    });

    // The operator path. `agent_id: null` is a VALUE the server must receive —
    // dropping the key would let it infer scope from agent_id's absence.
    it('preserves a null agent_id and a non-agent scope', async () => {
      mockGet.mockResolvedValue(identified);
      mockPatch.mockResolvedValue({ data: { ok: true } });

      const { result } = renderHook(() => useAutonomyConfig(source));
      await waitFor(() => expect(result.current.loading).toBe(false));

      act(() => result.current.updatePolicy('Manual Operations', 'sdwan.peer_delete', 'block'));
      await act(async () => {
        await result.current.save();
      });

      expect(mockPatch).toHaveBeenCalledWith('/test/autonomy', {
        updates: [
          {
            action_category: 'sdwan.peer_delete',
            policy: 'block',
            scope: 'action_type',
            agent_id: null,
          },
        ],
      });
    });

    // THE invariant the identity map exists to hold: whichever row supplied the
    // verb a control DISPLAYS is the row save() writes to. Two rows for one
    // (bucket, category) is the case that can separate them — the parser is
    // last-wins for the verb, so an identity captured on a different pass, or
    // kept from an earlier row, would send the edit to a row the operator was
    // never shown.
    it('writes to the row whose verb is displayed when a bucket carries two', async () => {
      mockGet.mockResolvedValue({
        data: {
          data: {
            policies: {
              by_agent: {
                'Fleet Autonomy': [
                  { action_category: 'x', policy: 'auto_approve', scope: 'agent', agent_id: 'first-row' },
                  { action_category: 'x', policy: 'block', scope: 'global', agent_id: null },
                ],
              },
            },
          },
        },
      });
      mockPatch.mockResolvedValue({ data: { ok: true } });

      const { result } = renderHook(() => useAutonomyConfig(source));
      await waitFor(() => expect(result.current.loading).toBe(false));

      // Last row won the display...
      expect(result.current.getPolicy('Fleet Autonomy', 'x')).toBe('block');

      act(() => result.current.updatePolicy('Fleet Autonomy', 'x', 'require_approval'));
      await act(async () => { await result.current.save(); });

      // ...so the last row's identity is the one edited.
      expect(mockPatch).toHaveBeenCalledWith('/test/autonomy', {
        updates: [
          { action_category: 'x', policy: 'require_approval', scope: 'global', agent_id: null },
        ],
      });
    });

    // Same invariant, opposite direction: a row that carries NO identity must
    // clear the one an earlier row left, not inherit it. Otherwise the edit is
    // addressed to a row that is not the one being shown — which is the defect
    // class this whole change is about, reintroduced one layer down.
    it('does not inherit an identity from a row it replaced', async () => {
      mockGet.mockResolvedValue({
        data: {
          data: {
            policies: {
              by_agent: {
                'Fleet Autonomy': [
                  { action_category: 'x', policy: 'auto_approve', scope: 'agent', agent_id: 'first-row' },
                  { action_category: 'x', policy: 'block' },
                ],
              },
            },
          },
        },
      });
      mockPatch.mockResolvedValue({ data: { ok: true } });

      const { result } = renderHook(() => useAutonomyConfig(source));
      await waitFor(() => expect(result.current.loading).toBe(false));

      act(() => result.current.updatePolicy('Fleet Autonomy', 'x', 'require_approval'));
      await act(async () => { await result.current.save(); });

      expect(mockPatch).toHaveBeenCalledWith('/test/autonomy', {
        updates: [{ action_category: 'x', policy: 'require_approval' }],
      });
    });

    // A scope-"agent" row with no agent id is not a row this can address. Sending
    // the pair would upsert (scope "agent", ai_agent_id nil) — the malformed row
    // Ai::InterventionPolicyService#resolve's audience allowlist is written to
    // keep from binding every agent in the account. Degrade to category-only.
    it('refuses to send an agent scope with no agent id', async () => {
      mockGet.mockResolvedValue({
        data: {
          data: {
            policies: {
              by_agent: {
                'Fleet Autonomy': [
                  { action_category: 'x', policy: 'auto_approve', scope: 'agent', agent_id: null },
                ],
              },
            },
          },
        },
      });
      mockPatch.mockResolvedValue({ data: { ok: true } });

      const { result } = renderHook(() => useAutonomyConfig(source));
      await waitFor(() => expect(result.current.loading).toBe(false));

      act(() => result.current.updatePolicy('Fleet Autonomy', 'x', 'block'));
      await act(async () => { await result.current.save(); });

      expect(mockPatch).toHaveBeenCalledWith('/test/autonomy', {
        updates: [{ action_category: 'x', policy: 'block' }],
      });
    });

    // POSITIVE CONTROL for the refusal above: a nil agent id on a NON-agent
    // scope is the ordinary operator-path row and must keep its identity.
    // Without this, tightening identityOf into "drop every null agent_id" would
    // pass the refusal test while silently breaking Manual Operations.
    it('keeps a null agent id on a non-agent scope', async () => {
      mockGet.mockResolvedValue({
        data: {
          data: {
            policies: {
              by_agent: {
                'Manual Operations': [
                  { action_category: 'x', policy: 'auto_approve', scope: 'global', agent_id: null },
                ],
              },
            },
          },
        },
      });
      mockPatch.mockResolvedValue({ data: { ok: true } });

      const { result } = renderHook(() => useAutonomyConfig(source));
      await waitFor(() => expect(result.current.loading).toBe(false));

      act(() => result.current.updatePolicy('Manual Operations', 'x', 'block'));
      await act(async () => { await result.current.save(); });

      expect(mockPatch).toHaveBeenCalledWith('/test/autonomy', {
        updates: [{ action_category: 'x', policy: 'block', scope: 'global', agent_id: null }],
      });
    });

    // Edits to several buckets are ONE request: the endpoint takes a bulk array
    // across agents, and per-agent requests made a partial save possible where
    // the server offers an all-or-nothing error report.
    it('sends edits across buckets in a single request', async () => {
      mockGet.mockResolvedValue(identified);
      mockPatch.mockResolvedValue({ data: { ok: true } });

      const { result } = renderHook(() => useAutonomyConfig(source));
      await waitFor(() => expect(result.current.loading).toBe(false));

      act(() => {
        result.current.updatePolicy('Fleet Autonomy', 'system.sdwan_peer_remediate', 'block');
        result.current.updatePolicy('Manual Operations', 'sdwan.peer_delete', 'block');
      });
      await act(async () => {
        await result.current.save();
      });

      expect(mockPatch).toHaveBeenCalledTimes(1);
      expect(mockPatch.mock.calls[0][1].updates).toEqual(
        expect.arrayContaining([
          expect.objectContaining({
            action_category: 'system.sdwan_peer_remediate',
            scope: 'agent',
            agent_id: 'agent-fleet-uuid',
          }),
          expect.objectContaining({
            action_category: 'sdwan.peer_delete',
            scope: 'action_type',
            agent_id: null,
          }),
        ])
      );
    });
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
                {
                  action_category: 'a.x',
                  agent_bucket: 'Agent A',
                  policy: 'auto_approve',
                  scope: 'agent',
                  agent_id: 'agent-a-uuid',
                },
              ],
              beta: [
                {
                  action_category: 'b.y',
                  agent_bucket: 'Unlisted Agent',
                  policy: 'notify_and_proceed',
                  scope: 'agent',
                  agent_id: 'unlisted-uuid',
                },
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

    // The bucket by_agent omitted is the one whose edits are MOST at risk of
    // going to the wrong row: its identity exists only on the by_domain row, so
    // an identity captured anywhere other than beside the back-filled verb
    // would be missing here while every by_agent-sourced control looked fine.
    it('writes a back-filled row back to its own identity', async () => {
      mockGet.mockResolvedValue(withDomains);
      mockPatch.mockResolvedValue({ data: { ok: true } });

      const { result } = renderHook(() => useAutonomyConfig(source));
      await waitFor(() => expect(result.current.loading).toBe(false));

      act(() => result.current.updatePolicy('Unlisted Agent', 'b.y', 'block'));
      await act(async () => { await result.current.save(); });

      expect(mockPatch).toHaveBeenCalledWith('/test/autonomy', {
        updates: [
          { action_category: 'b.y', policy: 'block', scope: 'agent', agent_id: 'unlisted-uuid' },
        ],
      });
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
