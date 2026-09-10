import { screen, within, waitFor, fireEvent, act } from '@testing-library/react';
import { renderWithProviders } from '@/test-utils';
import { ComponentStatusDrawer } from './ComponentStatusDrawer';
import * as api from '@/features/platform/status/api/platformStatusApi';
import { featureRegistry } from '@/shared/services/featureRegistry';
import type {
  ComponentAction,
  ComponentStatusDetail,
  ComponentStatusImpactData,
  ComponentStatusSummary,
} from '@/shared/types/platformStatus';

jest.mock('@/features/platform/status/api/platformStatusApi');

const mockedApi = api as jest.Mocked<typeof api>;

// ComponentStatusDrawer (C3 part 1).
//
// Three properties here are the ones a screenshot cannot check, and each is
// asserted from BOTH sides:
//
//   1. an action the viewer lacks permission for is not rendered, AND one they
//      hold IS — a filter that hid everything would pass a one-sided test;
//   2. a `requires_reason` action cannot be confirmed with an empty box, AND
//      the typed reason reaches the request;
//   3. a registered rich panel renders, AND nothing renders when none is
//      registered — an "absent panel" that silently rendered a placeholder
//      would look identical in a screenshot.

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
  condition_count: 2,
  reason: 'HeartbeatStale',
  remediation_state: 'none',
  observed_at: '2026-09-10T12:00:00Z',
  last_seen_sweep_at: '2026-09-10T12:00:00Z',
  last_transition_at: '2026-09-10T11:00:00Z',
  ...overrides,
});

const detail = (overrides: Partial<ComponentStatusDetail> = {}): ComponentStatusDetail => ({
  ...summary(),
  conditions: [
    {
      type: 'Reachable',
      status: false,
      reason: 'HeartbeatStale',
      message: 'no heartbeat for 7m 12s',
      severity: 'degraded',
      evidence: { last_heartbeat_seconds: 432, threshold: 300 },
      observed_generation: '7',
      observed_at: '2026-09-10T12:00:00Z',
      last_transition_at: '2026-09-10T11:00:00Z',
    },
    {
      type: 'Held',
      status: false,
      reason: 'NotCordoned',
      message: null,
      severity: null,
      evidence: {},
      observed_generation: null,
      observed_at: '2026-09-10T12:00:00Z',
      last_transition_at: null,
    },
  ],
  dependencies: [{ kind: 'node', ref: 'node-3', relation: 'hosts' }],
  remediation: {},
  links: [],
  actions: [],
  observed_generation: '7',
  last_notified_at: null,
  ...overrides,
});

const impactData = (
  overrides: Partial<ComponentStatusImpactData> = {}
): ComponentStatusImpactData => ({
  component_status: summary(),
  impact: { count: 0, worst_verdict: 'ok', components: [] },
  root_cause_candidates: [],
  heuristic: true,
  heuristic_basis:
    'upstream-most unhealthy components, ranked by unhealthy-dependent count then earliest transition',
  ...overrides,
});

const action = (overrides: Partial<ComponentAction> = {}): ComponentAction => ({
  key: 'cordon',
  label: 'Cordon',
  method: 'POST',
  path: '/system/instances/i-42/cordon',
  permission: 'system.instances.manage',
  destructive: false,
  ...overrides,
});

const renderDrawer = (
  row: ComponentStatusSummary | null = summary(),
  permissions: string[] = []
) =>
  renderWithProviders(<ComponentStatusDrawer row={row} onClose={jest.fn()} />, {
    preloadedState: {
      auth: {
        user: { id: 'u-1', email: 'op@example.com', permissions },
        isAuthenticated: true,
        isLoading: false,
      },
    },
  });

describe('ComponentStatusDrawer', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    featureRegistry.clear();
    mockedApi.fetchComponentStatus.mockResolvedValue({
      component_status: detail(),
      impact: { count: 0, worst_verdict: 'ok', components: [] },
    });
    mockedApi.fetchComponentImpact.mockResolvedValue(impactData());
    mockedApi.runComponentAction.mockResolvedValue({});
  });

  it('renders nothing at all when no component is selected', async () => {
    // The drawer is a portal, so `container` is not where it would appear —
    // assert on the document, and on the read NOT being issued. The second half
    // is the one that matters: a drawer that fetched for a null selection would
    // hammer the detail route on every page load.
    renderDrawer(null);
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(mockedApi.fetchComponentStatus).not.toHaveBeenCalled();
  });

  it('opens as a labelled dialog carrying the component and its verdict', async () => {
    renderDrawer();
    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getAllByText('build-01').length).toBeGreaterThan(0);
    expect(within(dialog).getByRole('img', { name: 'build-01: Degraded' })).toBeInTheDocument();
  });

  it('closes on Escape', async () => {
    const onClose = jest.fn();
    renderWithProviders(<ComponentStatusDrawer row={summary()} onClose={onClose} />, {
      preloadedState: { auth: { user: { id: 'u', permissions: [] }, isAuthenticated: true, isLoading: false } },
    });
    await screen.findByRole('dialog');

    fireEvent.keyDown(document, { key: 'Escape' });
    expect(onClose).toHaveBeenCalled();
  });

  describe('Conditions tab', () => {
    it('shows type, reason, message, evidence and the transition time', async () => {
      renderDrawer();
      expect(await screen.findByText('Reachable')).toBeInTheDocument();
      expect(screen.getByText('HeartbeatStale')).toBeInTheDocument();
      expect(screen.getByText('no heartbeat for 7m 12s')).toBeInTheDocument();
      expect(screen.getByText('last_heartbeat_seconds')).toBeInTheDocument();
      expect(screen.getByText('432')).toBeInTheDocument();
    });

    it('renders a false Held the same way it renders a false Reachable, and lets the reason say which is bad', async () => {
      // The polarity trap: `status: false` is ordinary on Held and a problem on
      // Reachable. The badge reports the STATUS; nothing here decides which way
      // a type points, because nothing here knows.
      renderDrawer();
      await screen.findByText('Reachable');

      // Portal: query the document, not the render container.
      const held = document.querySelector('[data-condition-type="Held"]') as HTMLElement;
      const reachable = document.querySelector('[data-condition-type="Reachable"]') as HTMLElement;
      expect(held.getAttribute('data-condition-status')).toBe('false');
      expect(reachable.getAttribute('data-condition-status')).toBe('false');
      // Only the one that declared a severity shows one.
      expect(within(reachable).getByText('degraded')).toBeInTheDocument();
      expect(within(held).queryByText('degraded')).not.toBeInTheDocument();
    });

    it('says a component reported no conditions rather than implying it is healthy', async () => {
      mockedApi.fetchComponentStatus.mockResolvedValue({
        component_status: detail({ conditions: [] }),
        impact: { count: 0, worst_verdict: 'ok', components: [] },
      });
      renderDrawer();
      expect(await screen.findByText(/not a clean bill of health/)).toBeInTheDocument();
    });
  });

  describe('Dependencies tab', () => {
    it('shows upstream edges as identifiers and downstream rows with verdicts', async () => {
      mockedApi.fetchComponentImpact.mockResolvedValue(
        impactData({
          impact: {
            count: 1,
            worst_verdict: 'down',
            components: [summary({ id: 'd1', display_name: 'api-01', verdict: 'down' })],
          },
        })
      );
      renderDrawer();
      await screen.findByText('Reachable');
      fireEvent.click(screen.getByText('Dependencies'));

      const upstream = document.querySelector('[data-dependency-section="upstream"]') as HTMLElement;
      expect(within(upstream).getByText('hosts')).toBeInTheDocument();
      expect(within(upstream).getByText('node-3')).toBeInTheDocument();

      const downstream = document.querySelector('[data-dependency-section="downstream"]') as HTMLElement;
      expect(within(downstream).getByText('api-01')).toBeInTheDocument();
      expect(within(downstream).getByRole('img', { name: 'api-01: Down' })).toBeInTheDocument();
    });

    it('renders an unknown relation as text rather than dropping the edge', async () => {
      // `relation` is validated nowhere server-side, so an undocumented one can
      // arrive. An edge whose label you do not know is still an edge.
      mockedApi.fetchComponentStatus.mockResolvedValue({
        component_status: detail({
          dependencies: [{ kind: 'node', ref: 'node-3', relation: 'peers' }],
        }),
        impact: { count: 0, worst_verdict: 'ok', components: [] },
      });
      renderDrawer();
      await screen.findByText('Reachable');
      fireEvent.click(screen.getByText('Dependencies'));

      expect(screen.getByText('peers')).toBeInTheDocument();
      expect(screen.getByText('node-3')).toBeInTheDocument();
    });

    it('labels the root-cause ranking as a heuristic, with its basis', async () => {
      mockedApi.fetchComponentImpact.mockResolvedValue(
        impactData({
          root_cause_candidates: [summary({ id: 'rc', display_name: 'switch-1', verdict: 'down' })],
        })
      );
      renderDrawer();
      await screen.findByText('Reachable');
      fireEvent.click(screen.getByText('Dependencies'));

      expect(screen.getByText(/Heuristic, not a diagnosis/)).toBeInTheDocument();
      expect(screen.getByText(/ranked by unhealthy-dependent count/)).toBeInTheDocument();
      expect(screen.getByText('switch-1')).toBeInTheDocument();
    });
  });

  describe('Remediation tab', () => {
    it('explains not_actuatable rather than leaving the panel blank', async () => {
      mockedApi.fetchComponentStatus.mockResolvedValue({
        component_status: detail({
          remediation_state: 'not_actuatable',
          remediation: { state: 'not_actuatable', signal_kind: 'fleet.heartbeat_stale' },
        }),
        impact: { count: 0, worst_verdict: 'ok', components: [] },
      });
      renderDrawer();
      await screen.findByText('Reachable');
      fireEvent.click(screen.getByText('Remediation'));

      expect(screen.getByText(/No remediation lane is bound to this signal kind/)).toBeInTheDocument();
      expect(screen.getByText('fleet.heartbeat_stale')).toBeInTheDocument();
    });

    it('offers the approval link only when a decision is actually parked', async () => {
      // Both arms. An approval link on a component nobody is waiting on invites
      // a click that leads nowhere.
      mockedApi.fetchComponentStatus.mockResolvedValue({
        component_status: detail({
          remediation_state: 'awaiting_operator',
          remediation: { state: 'awaiting_operator', approval_request_id: 'ar-9' },
        }),
        impact: { count: 0, worst_verdict: 'ok', components: [] },
      });
      const { unmount } = renderDrawer();
      await screen.findByText('Reachable');
      fireEvent.click(screen.getByText('Remediation'));
      expect(screen.getByRole('link', { name: 'Open the approval request' })).toBeInTheDocument();
      unmount();

      mockedApi.fetchComponentStatus.mockResolvedValue({
        component_status: detail({
          remediation_state: 'auto_in_progress',
          remediation: { state: 'auto_in_progress', approval_request_id: 'ar-9' },
        }),
        impact: { count: 0, worst_verdict: 'ok', components: [] },
      });
      renderDrawer();
      await screen.findByText('Reachable');
      fireEvent.click(screen.getByText('Remediation'));
      expect(screen.queryByRole('link', { name: 'Open the approval request' })).not.toBeInTheDocument();
    });
  });

  describe('Actions tab', () => {
    const withActions = (actions: ComponentAction[]) =>
      mockedApi.fetchComponentStatus.mockResolvedValue({
        component_status: detail({ actions }),
        impact: { count: 0, worst_verdict: 'ok', components: [] },
      });

    it('hides an action the viewer has no permission for and shows one they hold', async () => {
      withActions([
        action({ key: 'cordon', label: 'Cordon', permission: 'system.instances.manage' }),
        action({ key: 'reap', label: 'Reap', permission: 'system.instances.destroy' }),
      ]);
      renderDrawer(summary(), ['system.instances.manage']);
      await screen.findByText('Reachable');
      fireEvent.click(screen.getByText('Actions'));

      expect(screen.getByRole('button', { name: 'Cordon' })).toBeInTheDocument();
      expect(screen.queryByRole('button', { name: 'Reap' })).not.toBeInTheDocument();
      // Said out loud rather than silently omitted, so an operator knows there
      // is something they cannot do rather than that there is nothing to do.
      expect(screen.getByText(/1 further action is declared but hidden/)).toBeInTheDocument();
    });

    it('distinguishes "no actions declared" from "none you may run"', async () => {
      withActions([]);
      const { unmount } = renderDrawer(summary(), ['system.instances.manage']);
      await screen.findByText('Reachable');
      fireEvent.click(screen.getByText('Actions'));
      expect(screen.getByText(/declares no actions/)).toBeInTheDocument();
      unmount();

      withActions([action()]);
      renderDrawer(summary(), []);
      await screen.findByText('Reachable');
      fireEvent.click(screen.getByText('Actions'));
      expect(screen.getByText(/none of which your permissions allow/)).toBeInTheDocument();
    });

    it('issues an unconfirmed action straight through, with the declared method and path', async () => {
      withActions([action()]);
      renderDrawer(summary(), ['system.instances.manage']);
      await screen.findByText('Reachable');
      fireEvent.click(screen.getByText('Actions'));

      await act(async () => {
        fireEvent.click(screen.getByRole('button', { name: 'Cordon' }));
      });

      expect(mockedApi.runComponentAction).toHaveBeenCalledWith(
        expect.objectContaining({ method: 'POST', path: '/system/instances/i-42/cordon' }),
        { reason: undefined }
      );
    });

    it('will not confirm a requires_reason action until a reason is typed, and sends it', async () => {
      withActions([
        action({
          key: 'reap',
          label: 'Reap',
          destructive: true,
          permission: 'system.instances.destroy',
          confirm: { prompt: 'This destroys the instance.', requires_reason: true },
        }),
      ]);
      renderDrawer(summary(), ['system.instances.destroy']);
      await screen.findByText('Reachable');
      fireEvent.click(screen.getByText('Actions'));
      fireEvent.click(screen.getByRole('button', { name: 'Reap' }));

      expect(await screen.findByText('This destroys the instance.')).toBeInTheDocument();

      // The drawer is itself a role="dialog", so the confirmation is the LAST
      // one in the document. Scoping to it is what separates the confirm button
      // from the tab's own "Reap" button — a looser selector clicked the tab
      // button and merely re-opened the dialog, which looked like a pass until
      // the call count said otherwise.
      const confirmDialog = () => {
        const dialogs = screen.getAllByRole('dialog');
        return dialogs[dialogs.length - 1];
      };

      // Arm one: empty reason, confirm disabled.
      expect(within(confirmDialog()).getByRole('button', { name: 'Reap' })).toBeDisabled();
      expect(mockedApi.runComponentAction).not.toHaveBeenCalled();

      fireEvent.change(screen.getByLabelText('Reason'), {
        target: { value: 'decommissioning the rack' },
      });

      // Arm two: reason typed, confirm enabled, and the reason reaches the wire.
      const confirmButton = within(confirmDialog()).getByRole('button', { name: 'Reap' });
      expect(confirmButton).not.toBeDisabled();
      await act(async () => {
        fireEvent.click(confirmButton);
      });

      expect(mockedApi.runComponentAction).toHaveBeenCalledWith(
        expect.objectContaining({ method: 'POST', path: '/system/instances/i-42/cordon' }),
        { reason: 'decommissioning the rack' }
      );
    });

    it('does not issue the request when a confirmed action is cancelled', async () => {
      withActions([
        action({ confirm: { prompt: 'Sure?', requires_reason: false } }),
      ]);
      renderDrawer(summary(), ['system.instances.manage']);
      await screen.findByText('Reachable');
      fireEvent.click(screen.getByText('Actions'));
      fireEvent.click(screen.getByRole('button', { name: 'Cordon' }));
      await screen.findByText('Sure?');

      fireEvent.click(screen.getByRole('button', { name: /cancel/i }));
      expect(mockedApi.runComponentAction).not.toHaveBeenCalled();
    });

    it('re-reads the drawer after an action succeeds', async () => {
      withActions([action()]);
      renderDrawer(summary(), ['system.instances.manage']);
      await screen.findByText('Reachable');
      const before = mockedApi.fetchComponentStatus.mock.calls.length;

      fireEvent.click(screen.getByText('Actions'));
      await act(async () => {
        fireEvent.click(screen.getByRole('button', { name: 'Cordon' }));
      });

      await waitFor(() =>
        expect(mockedApi.fetchComponentStatus.mock.calls.length).toBeGreaterThan(before)
      );
    });

    it('surfaces a failed action rather than looking like it worked', async () => {
      withActions([action()]);
      mockedApi.runComponentAction.mockRejectedValue(new Error('403 Forbidden'));
      renderDrawer(summary(), ['system.instances.manage']);
      await screen.findByText('Reachable');
      fireEvent.click(screen.getByText('Actions'));

      await act(async () => {
        fireEvent.click(screen.getByRole('button', { name: 'Cordon' }));
      });

      // The button is still there and the drawer did not close — nothing about
      // the UI claims success.
      expect(screen.getByRole('button', { name: 'Cordon' })).toBeInTheDocument();
    });
  });

  describe('the derived rich-panel slot', () => {
    it('renders no extra tab when no slot is registered for the kind', async () => {
      renderDrawer();
      await screen.findByText('Reachable');
      expect(screen.queryByText('Details')).not.toBeInTheDocument();
    });

    it('renders a slot registered under platform.status.drawer.<kind>', async () => {
      featureRegistry.registerComponentSlots({
        'platform.status.drawer.node_instance': () => <p>instance internals</p>,
      });
      renderDrawer();
      await screen.findByText('Reachable');

      fireEvent.click(screen.getByText('Details'));
      expect(screen.getByText('instance internals')).toBeInTheDocument();
    });

    it('ignores a slot registered for a DIFFERENT kind', async () => {
      // The negative arm of the derivation. A resolver that ignored the kind
      // would render another kind's panel here and look perfectly fine.
      featureRegistry.registerComponentSlots({
        'platform.status.drawer.docker_host': () => <p>host internals</p>,
      });
      renderDrawer();
      await screen.findByText('Reachable');
      expect(screen.queryByText('Details')).not.toBeInTheDocument();
    });

    it('picks up a slot registered after the drawer opened', async () => {
      renderDrawer();
      await screen.findByText('Reachable');
      expect(screen.queryByText('Details')).not.toBeInTheDocument();

      act(() => {
        featureRegistry.registerComponentSlots({
          'platform.status.drawer.node_instance': () => <p>late internals</p>,
        });
      });

      expect(await screen.findByText('Details')).toBeInTheDocument();
    });
  });

  it('reports a failed detail read instead of an empty drawer', async () => {
    mockedApi.fetchComponentStatus.mockRejectedValue(new Error('gateway timeout'));
    renderDrawer();
    expect(await screen.findByText('gateway timeout')).toBeInTheDocument();
  });
});
