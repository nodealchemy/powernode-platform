import { useState } from 'react';
import { screen, waitFor, fireEvent, act } from '@testing-library/react';
import { renderWithProviders } from '@/test-utils';
import { ComponentStatusDrawer } from './ComponentStatusDrawer';
import * as api from '@/features/platform/status/api/platformStatusApi';
import { featureRegistry } from '@/shared/services/featureRegistry';
import type {
  ComponentStatusDetail,
  ComponentStatusSummary,
  Investigation,
  InvestigationsData,
  RemediationRouteData,
} from '@/shared/types/platformStatus';

jest.mock('@/features/platform/status/api/platformStatusApi', () => {
  const actual = jest.requireActual('@/features/platform/status/api/platformStatusApi');
  return {
    ...Object.fromEntries(
      Object.keys(actual).map((key) => [key, typeof actual[key] === 'function' ? jest.fn() : actual[key]])
    ),
    // The typed refusal is a CLASS the component `instanceof`-checks. It must be
    // the real one, or the check can never pass and the refusal arms are vacuous.
    InvestigationRefusedError: actual.InvestigationRefusedError,
  };
});

// Mocked so a refusal's WARNING can be told apart from a failure's ERROR
// (C3p2 review R5) — the other observable effects are identical on both paths.
const mockShowNotification = jest.fn();
jest.mock('@/shared/hooks/useNotification', () => ({
  useNotification: () => ({ showNotification: mockShowNotification }),
}));

const mockedApi = api as jest.Mocked<typeof api>;

// C3 part 2 — Runbook, Investigations, Events, and the remediation route's
// `lane_reason`. Every oracle here is one lane 6 flagged as something that will
// bite a renderer, and each is asserted from both sides.

const summary = (overrides: Partial<ComponentStatusSummary> = {}): ComponentStatusSummary => ({
  id: 'row-1',
  component_kind: 'node_instance',
  component_ref: 'i-42',
  display_name: 'build-01',
  verdict: 'degraded',
  held: false,
  held_by_intent: false,
  unhealthy: true,
  shared: false,
  scope: 'account',
  environment_id: null,
  plane: 'none',
  presentation: { icon: 'Server', label: 'Node Instance', group_order: 20 },
  condition_count: 0,
  reason: null,
  remediation_state: 'awaiting_operator',
  observed_at: '2026-09-10T12:00:00Z',
  last_seen_sweep_at: '2026-09-10T12:00:00Z',
  last_transition_at: null,
  ...overrides,
});

const detail = (): ComponentStatusDetail => ({
  ...summary(),
  conditions: [],
  dependencies: [],
  remediation: { state: 'awaiting_operator' },
  links: [],
  actions: [],
  observed_generation: null,
  last_notified_at: null,
});

const routed = (laneReason?: string | null): RemediationRouteData => ({
  component_status_id: 'row-1',
  signal_kind: 'instance.silent',
  routed: true,
  route: {
    state: 'awaiting_operator',
    lane_key: 'fleet_signal',
    policy: 'approval_required',
    consent: 'granted',
    disruption: 'restart',
    environment_ceiling: 'dev',
    blast_radius: 3,
    can_proceed: false,
    reason: 'consent budget exhausted',
    ...(laneReason === undefined ? {} : { lane_reason: laneReason }),
  },
});

const investigation = (overrides: Partial<Investigation> = {}): Investigation => ({
  id: 'inv-1',
  component_kind: 'node_instance',
  component_ref: 'i-42',
  trigger: 'operator',
  status: 'completed',
  open: false,
  hypotheses: [],
  conclusion: null,
  agent_id: null,
  started_at: '2026-09-10T11:00:00Z',
  completed_at: '2026-09-10T11:05:00Z',
  ...overrides,
});

const investigations = (partial: Partial<InvestigationsData> = {}): InvestigationsData => ({
  component_status_id: 'row-1',
  open: [],
  recent: [],
  daily_cap: 20,
  ...partial,
});

const renderDrawer = (permissions: string[] = []) =>
  renderWithProviders(<ComponentStatusDrawer row={summary()} onClose={jest.fn()} />, {
    preloadedState: {
      auth: { user: { id: 'u-1', permissions }, isAuthenticated: true, isLoading: false },
    },
  });

const openTab = async (name: string) => {
  await screen.findByText('Conditions');
  fireEvent.click(screen.getByText(name));
};

describe('ComponentStatusDrawer — A9 tabs', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    featureRegistry.clear();
    mockedApi.fetchComponentStatus.mockResolvedValue({
      component_status: detail(),
      impact: { count: 0, worst_verdict: 'ok', components: [] },
    });
    mockedApi.fetchComponentImpact.mockResolvedValue({
      component_status: summary(),
      impact: { count: 0, worst_verdict: 'ok', components: [] },
      root_cause_candidates: [],
      heuristic: true,
      heuristic_basis: 'basis',
    });
    mockedApi.fetchComponentRunbook.mockResolvedValue({
      component_status_id: 'row-1',
      signal_kind: 'instance.silent',
      runbook: { kind: 'doc', doc: 'docs/runbooks/silent.md#triage', path: 'docs/runbooks/silent.md', anchor: 'triage' },
    });
    mockedApi.fetchRemediationRoute.mockResolvedValue(routed(null));
    mockedApi.fetchComponentEvents.mockResolvedValue({
      component_status_id: 'row-1',
      events: [],
      pagination: { current_page: 1, per_page: 20, total_count: 0, total_pages: 1 },
    });
    mockedApi.fetchInvestigations.mockResolvedValue(investigations());
  });

  describe('remediation route and lane_reason', () => {
    it('renders lane_reason beside the lane when the API returns it', async () => {
      mockedApi.fetchRemediationRoute.mockResolvedValue(routed('consent budget exhausted for today'));
      renderDrawer();
      await openTab('Remediation');

      const reason = await waitFor(() => {
        const node = document.querySelector('[data-lane-reason]');
        expect(node).not.toBeNull();
        return node as HTMLElement;
      });
      expect(reason.textContent).toBe('consent budget exhausted for today');
      expect(screen.getByText('fleet_signal')).toBeInTheDocument();
    });

    it('renders NOTHING in its place when lane_reason is null or absent — no placeholder', async () => {
      // Both absent shapes: the key missing, and the key present as null.
      for (const shape of [undefined, null] as const) {
        mockedApi.fetchRemediationRoute.mockResolvedValue(routed(shape));
        const { unmount } = renderDrawer();
        await openTab('Remediation');
        await screen.findByText('fleet_signal');

        expect(document.querySelector('[data-lane-reason]')).toBeNull();
        // STRUCTURAL, not an allow-list of placeholder words (C3p2 review R10):
        // the lane row holds its label and the lane key and NOTHING else, so
        // any stand-in — "—", "n/a", "none given" — changes its text and fails.
        const laneRow = document.querySelector('[data-route-lane]') as HTMLElement;
        expect(laneRow.textContent).toBe('Lanefleet_signal');
        unmount();
      }
    });

    it('branches on `routed`, and says nothing routes the component when route is absent', async () => {
      mockedApi.fetchRemediationRoute.mockResolvedValue({
        component_status_id: 'row-1',
        signal_kind: null,
        routed: false,
        reason: 'NoRoutedSignal',
      });
      renderDrawer();
      await openTab('Remediation');

      expect(await screen.findByText(/Nothing routes this component to a lane/)).toBeInTheDocument();
      expect(document.querySelector('[data-route-section="routed"]')).toBeNull();
    });

    it('treats can_proceed false while awaiting an operator as expected, not as an error', async () => {
      renderDrawer();
      await openTab('Remediation');
      expect(await screen.findByText(/waiting on a decision, as expected/)).toBeInTheDocument();
    });
  });

  describe('Runbook tab', () => {
    it('shows a doc runbook path as text, never as a link', async () => {
      renderDrawer();
      await openTab('Runbook');

      expect(await screen.findByText('docs/runbooks/silent.md')).toBeInTheDocument();
      // Extension-relative: a browser link to it is broken by construction.
      expect(screen.queryByRole('link', { name: /silent\.md/ })).not.toBeInTheDocument();
    });

    it('distinguishes "nothing routed" from "routed but undocumented"', async () => {
      mockedApi.fetchComponentRunbook.mockResolvedValue({
        component_status_id: 'row-1',
        signal_kind: null,
        runbook: { kind: 'none', known: false, reason: 'NoRoutedSignal' },
      });
      const { unmount } = renderDrawer();
      await openTab('Runbook');
      expect(await screen.findByText(/This is not a missing document/)).toBeInTheDocument();
      expect(screen.queryByText(/documentation gap/)).not.toBeInTheDocument();
      unmount();

      mockedApi.fetchComponentRunbook.mockResolvedValue({
        component_status_id: 'row-1',
        signal_kind: 'instance.silent',
        runbook: { kind: 'none', known: true, reason: 'NotRegistered' },
      });
      renderDrawer();
      await openTab('Runbook');
      expect(await screen.findByText(/documentation gap/)).toBeInTheDocument();
      expect(screen.queryByText(/This is not a missing document/)).not.toBeInTheDocument();
    });
  });

  describe('Events tab', () => {
    it('says it could not load the history when the read fails — never "held one verdict" (R2)', async () => {
      mockedApi.fetchComponentEvents.mockRejectedValue(new Error('events door down'));
      renderDrawer();
      await openTab('Events');

      expect(
        await screen.findByText(/Could not load this component's transition history/)
      ).toBeInTheDocument();
      expect(screen.queryByText(/held one verdict/)).not.toBeInTheDocument();
    });

    it('keeps the empty-history sentence for a SUCCESSFUL empty read only', async () => {
      renderDrawer();
      await openTab('Events');

      expect(await screen.findByText(/held one verdict since it was first swept/)).toBeInTheDocument();
      expect(screen.queryByText(/Could not load this component's transition history/)).not.toBeInTheDocument();
    });

    it('renders a null from as "first seen" and a null to as "removed"', async () => {
      mockedApi.fetchComponentEvents.mockResolvedValue({
        component_status_id: 'row-1',
        events: [
          { id: 'e2', kind: 'platform.component_status_changed', from_verdict: 'down', to_verdict: null, occurred_at: '2026-09-10T12:00:00Z', payload: {} },
          { id: 'e1', kind: 'platform.component_status_changed', from_verdict: null, to_verdict: 'ok', occurred_at: '2026-09-10T10:00:00Z', payload: {} },
        ],
        pagination: { current_page: 1, per_page: 20, total_count: 2, total_pages: 1 },
      });
      renderDrawer();
      await openTab('Events');

      expect(await screen.findByText('first seen')).toBeInTheDocument();
      expect(screen.getByText('removed')).toBeInTheDocument();
      expect(screen.queryByText(/unknown/i)).not.toBeInTheDocument();
    });
  });

  describe('Investigations tab', () => {
    describe('ranking outcome (A6 re-verification G2)', () => {
      type Hypothesis = Investigation['hypotheses'][number];
      const rankingRecord = (overrides: Record<string, unknown> = {}) => ({
        state: 'refused',
        reason: 'SecurityGateRefused',
        message: 'the gate refused the call',
        retryable: false,
        attempts: 1,
        recorded_at: '2026-09-10T11:01:00Z',
        ...overrides,
      });
      const withRanking = (
        ranking: Record<string, unknown> | undefined,
        overrides: Partial<Investigation> = {}
      ) =>
        investigation({
          id: 'inv-r',
          status: 'open',
          open: true,
          evidence: {
            assembled_at: '2026-09-10T11:00:00Z',
            window_seconds: 900,
            errors: {},
            ...(ranking ? { ranking } : {}),
          } as Investigation['evidence'],
          ...overrides,
        });
      const evidenceClassNames = () =>
        Array.from(document.querySelectorAll('dt')).map((node) => node.textContent);

      it('with NO ranking record, an open investigation is still waiting on the worker', async () => {
        mockedApi.fetchInvestigations.mockResolvedValue(investigations({ open: [withRanking(undefined)] }));
        renderDrawer();
        await openTab('Investigations');

        expect(await screen.findByText(/No hypotheses yet\. Ranking runs in the worker/)).toBeInTheDocument();
        expect(document.querySelector('[data-ranking-outcome]')).toBeNull();
      });

      it('a refusal that will not be retried promises nothing and is not an evidence gap', async () => {
        mockedApi.fetchInvestigations.mockResolvedValue(investigations({ open: [withRanking(rankingRecord())] }));
        renderDrawer();
        await openTab('Investigations');

        const outcome = await waitFor(() => {
          const node = document.querySelector('[data-ranking-outcome]');
          expect(node).not.toBeNull();
          return node as HTMLElement;
        });
        expect(outcome.getAttribute('data-ranking-reason')).toBe('SecurityGateRefused');
        expect(screen.getByText('Ranking did not run: the security gate refused it.')).toBeInTheDocument();
        expect(screen.getByText('the gate refused the call')).toBeInTheDocument();
        expect(screen.getByText('It will not be retried.')).toBeInTheDocument();
        expect(screen.getByText('No hypotheses were produced.')).toBeInTheDocument();
        expect(screen.queryByText(/No hypotheses yet/)).not.toBeInTheDocument();
        // Not under the evidence-class gap heading, and not listed as a class.
        expect(document.querySelector('[data-evidence-errors]')).toBeNull();
        expect(evidenceClassNames()).not.toContain('ranking');
      });

      it("the automatic-spend refusal says the hypotheses are the platform's own", async () => {
        const hypothesis = {
          cause: 'disk full on /persist',
          confidence: 0.6,
          confidence_state: 'measured',
          evidence_refs: ['conditions'],
          recommended_action_category: null,
        } as unknown as Hypothesis;
        mockedApi.fetchInvestigations.mockResolvedValue(
          investigations({
            recent: [
              withRanking(
                rankingRecord({ state: 'not_run', reason: 'AutomaticSpendNeedsGrant', message: 'auto spend refused' }),
                { status: 'completed', open: false, hypotheses: [hypothesis] }
              ),
            ],
          })
        );
        renderDrawer();
        await openTab('Investigations');

        expect(
          await screen.findByText(/automatic investigations need an agent-scoped spend grant/)
        ).toBeInTheDocument();
        expect(screen.getByText('disk full on /persist')).toBeInTheDocument();
        expect(screen.queryByText(/No hypotheses/)).not.toBeInTheDocument();
      });

      it("reads a CONCLUDED row's top-level ranking — the recent list carries no evidence", async () => {
        mockedApi.fetchInvestigations.mockResolvedValue(
          investigations({
            recent: [
              investigation({
                id: 'inv-c',
                status: 'completed',
                open: false,
                hypotheses: [],
                ranking: rankingRecord() as Investigation['ranking'],
              }),
            ],
          })
        );
        renderDrawer();
        await openTab('Investigations');

        expect(await screen.findByText('Ranking did not run: the security gate refused it.')).toBeInTheDocument();
        expect(screen.getByText('It will not be retried.')).toBeInTheDocument();
        expect(screen.getByText('No hypotheses were produced.')).toBeInTheDocument();
      });

      it('shows a ranking error an older server left in evidence.errors as its own line, never as a gap', async () => {
        mockedApi.fetchInvestigations.mockResolvedValue(
          investigations({
            open: [
              withRanking(undefined, {
                evidence: {
                  assembled_at: '2026-09-10T11:00:00Z',
                  window_seconds: 900,
                  errors: { ranking: 'ranker refused: security gate', metrics_window: 'prometheus timeout' },
                } as Investigation['evidence'],
              }),
            ],
          })
        );
        renderDrawer();
        await openTab('Investigations');

        expect(await screen.findByText('Ranking did not run: ranker refused: security gate')).toBeInTheDocument();
        // The REAL evidence class that failed is still a gap; ranking is not.
        const gap = document.querySelector('[data-evidence-errors]') as HTMLElement;
        expect(gap).not.toBeNull();
        const gapNames = Array.from(gap.querySelectorAll('dt')).map((node) => node.textContent);
        expect(gapNames).toEqual(['metrics_window']);
        // No promise about the worker, and no retry fact that was never recorded.
        expect(screen.queryByText(/Ranking runs in the worker/)).not.toBeInTheDocument();
        expect(screen.getByText('No hypotheses yet.')).toBeInTheDocument();
      });

      it('a retryable failure says it will be retried, not that the worker will finish it', async () => {
        mockedApi.fetchInvestigations.mockResolvedValue(
          investigations({
            open: [
              withRanking(
                rankingRecord({ state: 'failed', reason: 'ProviderError', message: 'provider 503', retryable: true, attempts: 2 })
              ),
            ],
          })
        );
        renderDrawer();
        await openTab('Investigations');

        expect(await screen.findByText('It will be retried (2 attempts so far).')).toBeInTheDocument();
        expect(screen.getByText('provider 503')).toBeInTheDocument();
        expect(screen.getByText('No hypotheses yet. Ranking will be retried.')).toBeInTheDocument();
        expect(screen.queryByText(/Ranking runs in the worker/)).not.toBeInTheDocument();
      });
    });

    it('renders a null confidence as "not measured", never as 0%', async () => {
      mockedApi.fetchInvestigations.mockResolvedValue(
        investigations({
          recent: [
            investigation({
              hypotheses: [
                { cause: 'nothing to go on', evidence_refs: [], confidence: null, confidence_state: 'not_measured' },
                { cause: 'upstream node lost', evidence_refs: ['conditions'], confidence: 0, confidence_state: 'measured' },
              ],
            }),
          ],
        })
      );
      renderDrawer();
      await openTab('Investigations');

      // Both arms, side by side: an unmeasured null and a MEASURED zero are
      // different answers and must read differently.
      expect(await screen.findByText('not measured')).toBeInTheDocument();
      expect(screen.getByText('0% confident')).toBeInTheDocument();
      expect(screen.getAllByText(/% confident/)).toHaveLength(1);
    });

    it('renders hypotheses in stored order, never re-sorted by confidence', async () => {
      mockedApi.fetchInvestigations.mockResolvedValue(
        investigations({
          recent: [
            investigation({
              conclusion: 'Most likely: the LOW-confidence one, by the ranker.',
              hypotheses: [
                { cause: 'first by the ranker', evidence_refs: [], confidence: 0.2, confidence_state: 'measured' },
                { cause: 'second by the ranker', evidence_refs: [], confidence: 0.9, confidence_state: 'measured' },
              ],
            }),
          ],
        })
      );
      renderDrawer();
      await openTab('Investigations');

      const first = await screen.findByText('first by the ranker');
      const second = screen.getByText('second by the ranker');
      // DOCUMENT_POSITION_FOLLOWING: `second` comes after `first`.
      expect(first.compareDocumentPosition(second) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    });

    it('labels an open investigation with no hypotheses as normal, not half-loaded', async () => {
      mockedApi.fetchInvestigations.mockResolvedValue(
        investigations({ open: [investigation({ status: 'open', open: true, evidence: { conditions: [] } })] })
      );
      renderDrawer();
      await openTab('Investigations');
      expect(await screen.findByText(/Ranking runs in the worker/)).toBeInTheDocument();
    });

    it('renders an extension evidence class it has never heard of, and shows errors as a gap', async () => {
      mockedApi.fetchInvestigations.mockResolvedValue(
        investigations({
          open: [
            investigation({
              status: 'open',
              open: true,
              evidence: {
                window_seconds: 3600,
                conditions: [],
                wormhole_telemetry: [{ a: 1 }, { a: 2 }],
                errors: { remediation_history: 'RuntimeError: extension is down' },
              },
            }),
          ],
        })
      );
      renderDrawer();
      await openTab('Investigations');

      // Not allow-listed: an extension's class appears.
      expect(await screen.findByText('wormhole_telemetry')).toBeInTheDocument();
      expect(screen.getByText('2 items')).toBeInTheDocument();
      // Checked-and-empty reads differently from could-not-check.
      expect(screen.getByText('checked, nothing found')).toBeInTheDocument();
      expect(screen.getByText(/could not be checked at all/)).toBeInTheDocument();
      expect(screen.getByText('RuntimeError: extension is down')).toBeInTheDocument();
    });

    it('hides the Investigate button without ai.autonomy.manage and shows it with', async () => {
      const { unmount } = renderDrawer([]);
      await openTab('Investigations');
      await screen.findByText(/Daily cap 20/);
      expect(screen.queryByRole('button', { name: 'Investigate' })).not.toBeInTheDocument();
      expect(screen.getByText('ai.autonomy.manage')).toBeInTheDocument();
      unmount();

      renderDrawer(['ai.autonomy.manage']);
      await openTab('Investigations');
      expect(await screen.findByRole('button', { name: 'Investigate' })).toBeInTheDocument();
    });

    it('opens an investigation and re-reads the list', async () => {
      mockedApi.openInvestigation.mockResolvedValue(investigation({ status: 'open', open: true }));
      renderDrawer(['ai.autonomy.manage']);
      await openTab('Investigations');
      const before = mockedApi.fetchInvestigations.mock.calls.length;

      await act(async () => {
        fireEvent.click(await screen.findByRole('button', { name: 'Investigate' }));
      });

      expect(mockedApi.openInvestigation).toHaveBeenCalledWith('row-1');
      await waitFor(() =>
        expect(mockedApi.fetchInvestigations.mock.calls.length).toBeGreaterThan(before)
      );
    });

    it('treats a 409 refusal as a bound, not a failure, and does not re-read', async () => {
      mockedApi.openInvestigation.mockRejectedValue(
        new api.InvestigationRefusedError('already open', 'AlreadyOpen', 20)
      );
      renderDrawer(['ai.autonomy.manage']);
      await openTab('Investigations');
      const before = mockedApi.fetchInvestigations.mock.calls.length;

      await act(async () => {
        fireEvent.click(await screen.findByRole('button', { name: 'Investigate' }));
      });

      // No success path taken: nothing re-read, and the button is back.
      expect(mockedApi.fetchInvestigations.mock.calls.length).toBe(before);
      expect(screen.getByRole('button', { name: 'Investigate' })).not.toBeDisabled();
      // THE DISCRIMINATING HALF (C3p2 review R5). Both assertions above also
      // hold on the generic failure path. Only this one does not: a bound is
      // announced as a WARNING in the refusal's own words, never as
      // "Investigation failed: …" at error level.
      expect(mockShowNotification).toHaveBeenCalledWith(
        'An investigation of this component is already open — see it above.',
        'warning'
      );
      expect(mockShowNotification).not.toHaveBeenCalledWith(expect.anything(), 'error');
    });

    it("never shows a component's investigation under the component the drawer moved to (R1)", async () => {
      // Click Investigate on alpha, follow an edge to bravo while the POST is in
      // flight, then let the POST land. The re-read must stay alpha's business.
      let resolvePost!: (value: Investigation) => void;
      mockedApi.openInvestigation.mockReturnValue(
        new Promise<Investigation>((resolve) => {
          resolvePost = resolve;
        })
      );
      mockedApi.fetchInvestigations.mockImplementation(async (id: string) =>
        id === 'row-1'
          ? investigations({
              open: [investigation({ id: 'inv-A', status: 'open', open: true, conclusion: 'ALPHA-CONCLUSION' })],
            })
          : investigations({ component_status_id: 'row-2' })
      );
      const bravo = summary({ id: 'row-2', component_ref: 'i-43', display_name: 'build-02' });
      const Switcher = () => {
        const [row, setRow] = useState<ComponentStatusSummary>(summary());
        return (
          <>
            <button type="button" onClick={() => setRow(bravo)}>
              switch to bravo
            </button>
            <ComponentStatusDrawer row={row} onClose={jest.fn()} />
          </>
        );
      };
      renderWithProviders(<Switcher />, {
        preloadedState: {
          auth: { user: { id: 'u-1', permissions: ['ai.autonomy.manage'] }, isAuthenticated: true, isLoading: false },
        },
      });

      await openTab('Investigations');
      await act(async () => {
        fireEvent.click(await screen.findByRole('button', { name: 'Investigate' }));
      });
      await act(async () => {
        fireEvent.click(screen.getByText('switch to bravo'));
      });
      await openTab('Investigations');
      expect(await screen.findByText(/Nothing has been investigated/)).toBeInTheDocument();

      // Alpha's POST lands only now.
      await act(async () => {
        resolvePost(investigation({ id: 'inv-A' }));
      });
      await act(async () => {
        await Promise.resolve();
      });

      expect(screen.queryByText(/ALPHA-CONCLUSION/)).not.toBeInTheDocument();
      expect(screen.getByText(/0 open, 0 recent/)).toBeInTheDocument();
    });
  });

  it('one failing A9 read does not blank the other tabs', async () => {
    // allSettled, not all: the investigations door being down must not take the
    // runbook with it.
    mockedApi.fetchInvestigations.mockRejectedValue(new Error('worker down'));
    renderDrawer();
    await openTab('Runbook');
    expect(await screen.findByText('docs/runbooks/silent.md')).toBeInTheDocument();

    fireEvent.click(screen.getByText('Investigations'));
    expect(await screen.findByText('Investigations could not be read.')).toBeInTheDocument();
  });
});
