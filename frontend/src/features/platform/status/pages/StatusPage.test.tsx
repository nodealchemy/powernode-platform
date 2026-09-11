import { render, screen, within, waitFor, fireEvent, act } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { StatusPage } from './StatusPage';
import * as api from '@/features/platform/status/api/platformStatusApi';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { featureRegistry } from '@/shared/services/featureRegistry';
import { BreadcrumbProvider } from '@/shared/hooks/BreadcrumbContext';
import type { ComponentStatusSummary, Verdict } from '@/shared/types/platformStatus';

jest.mock('@/features/platform/status/api/platformStatusApi');
jest.mock('@/shared/hooks/usePageWebSocket');

const mockedApi = api as jest.Mocked<typeof api>;
const mockedSocket = usePageWebSocket as jest.MockedFunction<typeof usePageWebSocket>;

// StatusPage (C2) — the operator screen.
//
// The assertions that matter here are the ones a screenshot would not catch:
// that the page renders a kind it has never heard of purely from the row's
// `presentation` blob, that the environment filter reaches the SERVER rather
// than being applied client-side (the three-valued rule lives server-side, and
// a page that filtered locally would quietly show another plane's rows), and
// that a plane-less row is labelled rather than silently mixed in.

const row = (overrides: Partial<ComponentStatusSummary> = {}): ComponentStatusSummary => ({
  id: 'row-1',
  component_kind: 'ai_provider',
  component_ref: 'provider-1',
  display_name: 'Anthropic',
  verdict: 'ok',
  held: false,
  held_by_intent: false,
  unhealthy: false,
  shared: false,
  scope: 'account',
  environment_id: null,
  plane: 'none',
  presentation: { icon: 'Plug', label: 'AI Provider', group_order: 10 },
  condition_count: 2,
  reason: null,
  remediation_state: 'none',
  observed_at: '2026-09-10T12:00:00Z',
  last_seen_sweep_at: '2026-09-10T12:00:00Z',
  last_transition_at: null,
  ...overrides,
});

const counts = (partial: Partial<Record<Verdict, number>> = {}) => ({
  ok: 0,
  held: 0,
  progressing: 0,
  not_measured: 0,
  degraded: 0,
  down: 0,
  ...partial,
});

const indexResult = (
  rows: ComponentStatusSummary[],
  extra: Partial<api.ComponentStatusIndexResult> = {}
): api.ComponentStatusIndexResult => ({
  component_statuses: rows,
  filters: {},
  unknown_environment: false,
  pagination: { current_page: 1, per_page: 100, total_count: rows.length, total_pages: 1 },
  ...extra,
});

const rollupResult = (verdict: Verdict = 'ok', heldCount = 0) => ({
  rollup: { verdict, held_count: heldCount, counts_by_verdict: counts({ [verdict]: 1 }), total: 1 },
  shared: { verdict: 'ok' as Verdict, held_count: 0, counts_by_verdict: counts(), total: 0 },
  by_kind: {},
  shared_by_kind: {},
  filters: {},
  unknown_environment: false,
  observed_at: '2026-09-10T12:00:00Z',
});

const renderPage = () =>
  render(
    <MemoryRouter>
      <BreadcrumbProvider>
        <StatusPage />
      </BreadcrumbProvider>
    </MemoryRouter>
  );

describe('StatusPage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    featureRegistry.clear();
    mockedApi.fetchComponentStatuses.mockResolvedValue(indexResult([row()]));
    mockedApi.fetchStatusRollup.mockResolvedValue(rollupResult());
    mockedSocket.mockReturnValue({
      isConnected: true,
      error: null,
      activeChannels: ['platformStatus'],
      subscribeToChannel: jest.fn(),
      unsubscribeFromChannel: jest.fn(),
    });
  });

  it('renders one card per component, grouped by the presentation label', async () => {
    mockedApi.fetchComponentStatuses.mockResolvedValue(
      indexResult([
        row({ id: 'a', display_name: 'Anthropic' }),
        row({
          id: 'b',
          component_kind: 'docker_host',
          component_ref: 'host-1',
          display_name: 'build-01',
          verdict: 'degraded',
          unhealthy: true,
          presentation: { icon: 'Container', label: 'Docker Host', group_order: 30 },
        }),
      ])
    );
    renderPage();

    await screen.findByText('Anthropic');
    expect(screen.getByText('build-01')).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /AI Provider/ })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /Docker Host/ })).toBeInTheDocument();
  });

  it('renders a verdict badge per card, including one the page has no special case for', async () => {
    mockedApi.fetchComponentStatuses.mockResolvedValue(
      indexResult([
        row({ id: 'a', verdict: 'down', unhealthy: true, display_name: 'Rails API' }),
        row({ id: 'b', component_ref: 'p2', verdict: 'not_measured', unhealthy: true, display_name: 'Blind Spot' }),
        row({ id: 'c', component_ref: 'p3', verdict: 'held', held: true, display_name: 'Drained Node' }),
      ])
    );
    renderPage();

    expect(await screen.findByRole('img', { name: 'Rails API: Down' })).toBeInTheDocument();
    expect(screen.getByRole('img', { name: 'Blind Spot: Not measured' })).toBeInTheDocument();
    expect(screen.getByRole('img', { name: 'Drained Node: Held' })).toBeInTheDocument();
  });

  it('renders a kind it has never heard of from the row alone', async () => {
    // The genericity claim, tested rather than asserted: there is no
    // `wormhole_relay` anywhere in core, and the card still draws.
    mockedApi.fetchComponentStatuses.mockResolvedValue(
      indexResult([
        row({
          id: 'x',
          component_kind: 'wormhole_relay',
          component_ref: 'relay-9',
          display_name: 'Relay 9',
          presentation: { icon: 'NotARealLucideIcon', label: 'Wormhole Relay', group_order: 5 },
        }),
      ])
    );
    renderPage();

    expect(await screen.findByText('Relay 9')).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /Wormhole Relay/ })).toBeInTheDocument();
  });

  describe('the right rail', () => {
    it('derives its three buckets from remediation state, not from the verdict', async () => {
      // The negative arm is the point: a `down` component with remediation
      // state `none` belongs in NO bucket. A rail that inferred "down means
      // someone should decide" would tell the operator a story the platform
      // never told it.
      mockedApi.fetchComponentStatuses.mockResolvedValue(
        indexResult([
          row({ id: 'a', display_name: 'Awaiting', verdict: 'degraded', remediation_state: 'awaiting_operator' }),
          row({ id: 'b', component_ref: 'p2', display_name: 'Working', verdict: 'degraded', remediation_state: 'auto_in_progress' }),
          row({ id: 'c', component_ref: 'p3', display_name: 'Wedged', verdict: 'down', remediation_state: 'stuck' }),
          row({ id: 'd', component_ref: 'p4', display_name: 'Unattended', verdict: 'down', remediation_state: 'none' }),
        ])
      );
      const { container } = renderPage();
      await screen.findAllByText('Awaiting');

      const bucket = (id: string) =>
        container.querySelector(`[data-rail-bucket="${id}"]`) as HTMLElement;

      expect(within(bucket('needs-decision')).getByText('Awaiting')).toBeInTheDocument();
      expect(within(bucket('in-progress')).getByText('Working')).toBeInTheDocument();
      expect(within(bucket('stuck')).getByText('Wedged')).toBeInTheDocument();

      expect(within(bucket('needs-decision')).queryByText('Unattended')).not.toBeInTheDocument();
      expect(within(bucket('in-progress')).queryByText('Unattended')).not.toBeInTheDocument();
      expect(within(bucket('stuck')).queryByText('Unattended')).not.toBeInTheDocument();
    });

    it('puts a progressing verdict in "in progress" even with no remediation lane', async () => {
      mockedApi.fetchComponentStatuses.mockResolvedValue(
        indexResult([
          row({ id: 'p', display_name: 'Provisioning', verdict: 'progressing', remediation_state: 'none' }),
        ])
      );
      const { container } = renderPage();
      await screen.findAllByText('Provisioning');

      const inProgress = container.querySelector('[data-rail-bucket="in-progress"]') as HTMLElement;
      expect(within(inProgress).getByText('Provisioning')).toBeInTheDocument();
    });
  });

  describe('the environment filter', () => {
    it('sends the plane to the SERVER rather than filtering locally', async () => {
      mockedApi.fetchComponentStatuses.mockResolvedValue(
        indexResult([
          row({ id: 'a', display_name: 'In dev', environment_id: 'env-dev', plane: 'in' }),
          row({ id: 'b', component_ref: 'p2', display_name: 'Plane-less', environment_id: null, plane: 'none' }),
        ])
      );
      renderPage();
      await screen.findByText('In dev');

      fireEvent.change(screen.getByLabelText('Filter by environment plane'), {
        target: { value: 'env-dev' },
      });

      await waitFor(() =>
        expect(mockedApi.fetchComponentStatuses).toHaveBeenCalledWith(
          expect.objectContaining({ environment: 'env-dev' })
        )
      );
      // The three-valued rule lives server-side. If this page filtered locally
      // it would have to reimplement "this plane PLUS the plane-less ones, never
      // another plane's", and a reimplementation shares no bugs with the original.
      expect(mockedApi.fetchStatusRollup).toHaveBeenCalledWith(
        expect.objectContaining({ environment: 'env-dev' })
      );
    });

    it('sends no environment param for "all planes" and the literal "none" for plane-less', async () => {
      // Both arms of the three-valued rule at the wire. Absent and "none" are
      // DIFFERENT questions; collapsing them is the bug this asserts against.
      renderPage();
      await screen.findByText('Anthropic');
      expect(mockedApi.fetchComponentStatuses).toHaveBeenLastCalledWith(
        expect.objectContaining({ environment: undefined })
      );

      fireEvent.change(screen.getByLabelText('Filter by environment plane'), {
        target: { value: 'none' },
      });

      await waitFor(() =>
        expect(mockedApi.fetchComponentStatuses).toHaveBeenLastCalledWith(
          expect.objectContaining({ environment: 'none' })
        )
      );
    });

    it('keeps every kind in the Kind selector after a kind is chosen', async () => {
      // C2 review M2, at the surface an operator actually touches. Choosing a
      // kind narrows the response to that kind; a selector derived from the
      // response would then offer only "All kinds" and the one already chosen.
      mockedApi.fetchComponentStatuses.mockResolvedValueOnce(
        indexResult([
          row({ id: 'a', component_kind: 'ai_provider', display_name: 'Anthropic' }),
          row({
            id: 'b',
            component_ref: 'h1',
            component_kind: 'docker_host',
            display_name: 'build-01',
            presentation: { icon: 'Container', label: 'Docker Host', group_order: 30 },
          }),
        ])
      );
      renderPage();
      await screen.findByText('build-01');

      const selector = screen.getByLabelText('Filter by component kind') as HTMLSelectElement;
      expect(Array.from(selector.options).map((o) => o.value)).toEqual([
        '',
        'ai_provider',
        'docker_host',
      ]);

      mockedApi.fetchComponentStatuses.mockResolvedValue(
        indexResult([
          row({
            id: 'b',
            component_ref: 'h1',
            component_kind: 'docker_host',
            display_name: 'build-01',
            presentation: { icon: 'Container', label: 'Docker Host', group_order: 30 },
          }),
        ])
      );
      fireEvent.change(selector, { target: { value: 'docker_host' } });

      await waitFor(() =>
        expect(mockedApi.fetchComponentStatuses).toHaveBeenLastCalledWith(
          expect.objectContaining({ kind: 'docker_host' })
        )
      );
      await waitFor(() => expect(screen.queryByText('Anthropic')).not.toBeInTheDocument());

      // Still three options: the operator can get back without clearing first.
      expect(Array.from(selector.options).map((o) => o.value)).toEqual([
        '',
        'ai_provider',
        'docker_host',
      ]);
    });

    it('labels a plane-less row rather than mixing it in silently', async () => {
      mockedApi.fetchComponentStatuses.mockResolvedValue(
        indexResult([row({ id: 'b', display_name: 'Plane-less', environment_id: null, plane: 'none' })])
      );
      renderPage();
      await screen.findByText('Plane-less');
      expect(screen.getByText('plane-less')).toBeInTheDocument();
    });

    it('says so when the named plane does not exist, instead of showing an empty grid', async () => {
      mockedApi.fetchComponentStatuses.mockResolvedValue(
        indexResult([], { unknown_environment: true })
      );
      renderPage();
      expect(
        await screen.findByText(/That plane does not exist for this account/)
      ).toBeInTheDocument();
    });
  });

  describe('A4b fields', () => {
    it('renders reason_message beside the reason token when the wire carries it', async () => {
      mockedApi.fetchComponentStatuses.mockResolvedValue(
        indexResult([
          row({
            id: 'a',
            verdict: 'down',
            reason: 'HeartbeatStale',
            reason_message: 'no heartbeat for 7m 12s',
          }),
        ])
      );
      renderPage();

      expect(await screen.findByText('HeartbeatStale')).toBeInTheDocument();
      expect(screen.getByText('no heartbeat for 7m 12s')).toBeInTheDocument();
    });

    it('shows the token alone — nothing invented — when reason_message is absent', async () => {
      // Both absent shapes: an older server omitting the key, and a null.
      for (const message of [undefined, null]) {
        mockedApi.fetchComponentStatuses.mockResolvedValue(
          indexResult([row({ id: 'a', verdict: 'down', reason: 'HeartbeatStale', reason_message: message })])
        );
        const { unmount } = renderPage();
        await screen.findByText('HeartbeatStale');
        expect(document.querySelector('[data-reason-message]')).toBeNull();
        unmount();
      }
    });

    it('labels plane options by NAME, keeping the id as the value and in the title', async () => {
      mockedApi.fetchComponentStatuses.mockResolvedValue(
        indexResult([
          row({ id: 'a', environment_id: 'env-dev-0123456789', plane: 'in', environment_name: 'Development', environment_slug: 'dev' }),
          // A plane the server sent no name for (an A4b-predating server).
          row({ id: 'b', component_ref: 'p2', environment_id: 'env-ci-0123456789', plane: 'in' }),
        ])
      );
      renderPage();
      await screen.findAllByText('Anthropic');

      const options = Array.from(
        (screen.getByLabelText('Filter by environment plane') as HTMLSelectElement).options
      );
      const named = options.find((o) => o.value === 'env-dev-0123456789');
      const unnamed = options.find((o) => o.value === 'env-ci-0123456789');

      expect(named?.textContent).toBe('Development');
      expect(named?.title).toBe('env-dev-0123456789');
      // Unnamed: the shortened id, the ONLY true label available — never a
      // fabricated name.
      expect(unnamed?.textContent).toBe('env-ci-0…');
    });

    it('names the plane on an in-plane card, and never shows an id there', async () => {
      mockedApi.fetchComponentStatuses.mockResolvedValue(
        indexResult([
          row({ id: 'a', display_name: 'named', environment_id: 'env-dev-0123456789', plane: 'in', environment_name: 'Development' }),
          row({ id: 'b', component_ref: 'p2', display_name: 'unnamed', environment_id: 'env-ci-0123456789', plane: 'in' }),
        ])
      );
      renderPage();
      await screen.findByText('named');

      const planeLabels = Array.from(document.querySelectorAll('[data-plane-name]')).map(
        (node) => node.textContent
      );
      expect(planeLabels).toEqual(['Development']);
      expect(screen.queryByText(/env-ci-0123456789/)).not.toBeInTheDocument();
    });
  });

  describe('first load and refresh (C4 checklist rows 2-3, from HealthPanel)', () => {
    it('shows the grid skeleton on first load, not a sentence', async () => {
      mockedApi.fetchComponentStatuses.mockReturnValue(new Promise(() => {}));
      renderPage();

      const skeleton = await screen.findByRole('status', { name: 'Loading components' });
      expect(skeleton).toHaveAttribute('data-status-skeleton');
      expect(skeleton.querySelectorAll('.animate-pulse').length).toBeGreaterThan(0);
      expect(screen.queryByText('Loading components…')).not.toBeInTheDocument();
    });

    it('removes the skeleton once the cards land', async () => {
      renderPage();
      await screen.findAllByText('Anthropic');
      expect(document.querySelector('[data-status-skeleton]')).toBeNull();
    });

    it('the Refresh action spins and is disabled while a read is in flight, then recovers', async () => {
      let resolveRead!: (value: api.ComponentStatusIndexResult) => void;
      mockedApi.fetchComponentStatuses.mockReturnValue(
        new Promise((resolve) => {
          resolveRead = resolve;
        })
      );
      renderPage();

      const button = await screen.findByTestId('action-refresh');
      await waitFor(() => expect(button).toBeDisabled());
      expect(button.querySelector('svg')?.getAttribute('class') ?? '').toMatch(/animate-spin/);

      await act(async () => {
        resolveRead(indexResult([row()]));
      });

      await waitFor(() => expect(button).not.toBeDisabled());
      expect(button.querySelector('svg')?.getAttribute('class') ?? '').not.toMatch(/animate-spin/);
    });
  });

  it('separates the shared-infrastructure rollup from the account one', async () => {
    mockedApi.fetchStatusRollup.mockResolvedValue({
      ...rollupResult('ok'),
      shared: {
        verdict: 'down',
        held_count: 0,
        counts_by_verdict: counts({ down: 1 }),
        total: 1,
      },
    });
    renderPage();

    await screen.findByText('Shared infrastructure');
    // The account stays OK while shared infrastructure is down: folding the two
    // together would turn one shared breaker into every tenant's outage.
    expect(screen.getByRole('img', { name: 'This account: OK' })).toBeInTheDocument();
    expect(screen.getByRole('img', { name: 'Shared infrastructure: Down' })).toBeInTheDocument();
  });

  it('states the held count beside the verdict rather than inside it', async () => {
    mockedApi.fetchStatusRollup.mockResolvedValue(rollupResult('ok', 3));
    renderPage();
    await screen.findByText('3 held by intent');
    expect(screen.getByRole('img', { name: 'This account: OK' })).toBeInTheDocument();
  });

  it('renders a kind registered by an extension after first render', async () => {
    renderPage();
    await screen.findByText('Anthropic');
    expect(screen.queryByText('node-7')).not.toBeInTheDocument();

    mockedApi.fetchComponentStatuses.mockResolvedValue(
      indexResult([
        row(),
        row({
          id: 'late',
          component_kind: 'node_instance',
          component_ref: 'i-7',
          display_name: 'node-7',
          presentation: { icon: 'Server', label: 'Node Instance', group_order: 20 },
        }),
      ])
    );

    featureRegistry.registerComponentSlots({
      'platform.status.drawer.node_instance.signals': () => null,
    });

    expect(await screen.findByText('node-7')).toBeInTheDocument();
  });

  it('surfaces a failed read instead of an empty, healthy-looking grid', async () => {
    mockedApi.fetchComponentStatuses.mockRejectedValue(new Error('gateway timeout'));
    renderPage();
    expect(await screen.findByText('gateway timeout')).toBeInTheDocument();
  });

  it('says how many components it is showing when the server has more', async () => {
    mockedApi.fetchComponentStatuses.mockResolvedValue(
      indexResult([row()], {
        pagination: { current_page: 1, per_page: 100, total_count: 187, total_pages: 2 },
      })
    );
    renderPage();
    expect(await screen.findByText('showing 1 of 187')).toBeInTheDocument();
  });

  it('says the total is unknown when the server sent none — never the page length (L1)', async () => {
    mockedApi.fetchComponentStatuses.mockResolvedValue(
      indexResult([row()], {
        pagination: { current_page: 1, per_page: 100, total_count: null, total_pages: 1 },
      })
    );
    renderPage();
    expect(await screen.findByText('showing 1; total not reported')).toBeInTheDocument();
    expect(screen.queryByText(/showing 1 of/)).not.toBeInTheDocument();
  });

  it('adds no count line when the page holds every matching component (the other arm)', async () => {
    renderPage();
    await screen.findAllByText('Anthropic');
    expect(document.querySelector('[data-total-unknown]')).toBeNull();
    expect(screen.queryByText(/^showing /)).not.toBeInTheDocument();
  });

  it('marks a card selected on click, so C3 can hang a drawer off it', async () => {
    renderPage();
    const card = await screen.findByText('Anthropic');
    const button = card.closest('button') as HTMLButtonElement;

    expect(button).toHaveAttribute('aria-pressed', 'false');
    fireEvent.click(button);
    expect(button).toHaveAttribute('aria-pressed', 'true');
  });
});
