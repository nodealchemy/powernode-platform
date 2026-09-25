import { render, screen, fireEvent, waitFor, within } from '@testing-library/react';
import { PolicyDomainSections } from './PolicyDomainSections';
import { featureRegistry } from '@/shared/services/featureRegistry';

// The grouped half of core's intervention-policy panel: one section per policy
// DOMAIN the server groups rows into, one editor group per agent within it.
//
// Ported from the System extension's settings panel, which this replaces. These
// tests drive the REAL useAutonomyConfig hook with only `apiClient` mocked, so
// every section, group and verb on screen comes from the HTTP payload
// (GET /ai/intervention_policies/grouped), and every save is the literal body
// the bulk endpoint receives.
//
// Presentation (label, blurb, order) comes from featureRegistry, where an
// extension presents the domains it owns. Membership never does: the server
// decides which category is in which domain (IMP-0874acd5b50c — a literal list
// in the component had drifted to omit 28 of 119 categories).

const mockGet = jest.fn();
const mockPatch = jest.fn();

jest.mock('@/shared/services/apiClient', () => ({
  apiClient: {
    get: (...args: unknown[]) => mockGet(...args),
    patch: (...args: unknown[]) => mockPatch(...args),
  },
}));

jest.mock('@/shared/utils/logger', () => ({
  logger: { error: jest.fn(), warn: jest.fn(), info: jest.fn(), debug: jest.fn() },
}));

const presentation = (key: string, label: string) => ({ key, label, description: `${label} blurb` });

// Registration order is presentation order. The server's key order is its
// first-match-wins order (a correctness constraint: a prefix extending another
// is declared first), which is why these fixtures put node_lifecycle LAST.
function presentDomains() {
  featureRegistry.registerPolicyDomains('sys', [
    presentation('node_lifecycle', 'Node Lifecycle'),
    presentation('container_runtime', 'Container Runtimes'),
    presentation('gitops', 'GitOps'),
  ]);
  featureRegistry.registerPolicyDomains('biz', [presentation('billing_ops', 'Billing Operations')]);
}

function groupedResponse(byDomain: unknown) {
  return { data: { success: true, data: { chains: [], policies: { by_domain: byDomain } } } };
}

const SERVER_DRIVEN = {
  container_runtime: [
    { action_category: 'system.runtime_docker_provision', agent_bucket: 'Runtime Manager', policy: 'auto_approve',
      scope: 'agent', agent_id: 'rt-uuid' },
  ],
  gitops: [
    { action_category: 'system.gitops_apply_proposal', agent_bucket: 'GitOps Reconciler', policy: 'notify_and_proceed',
      scope: 'agent', agent_id: 'go-uuid' },
  ],
  // A domain key nothing presents. It has to render anyway, under a derived
  // label, or the drift returns the day the server declares a new domain.
  quarantine: [
    { action_category: 'system.made_up_future_action', agent_bucket: 'Manual Operations', policy: 'block',
      scope: 'global', agent_id: null },
  ],
  billing_ops: [
    { action_category: 'billing.refund', agent_bucket: 'Manual Operations', policy: 'require_approval',
      scope: 'global', agent_id: null },
  ],
  // Empty: the server ships every registered domain whether or not the account
  // has a row in it. Nothing to tune, so no section.
  disk_image: [],
  node_lifecycle: [
    { action_category: 'system.cert_rotate', agent_bucket: 'Fleet Autonomy', policy: 'require_approval',
      scope: 'agent', agent_id: 'fleet-uuid' },
    { action_category: 'system.instance_reboot', agent_bucket: 'Fleet Autonomy', policy: 'notify_and_proceed',
      scope: 'agent', agent_id: 'fleet-uuid' },
    { action_category: 'system.task.start', agent_bucket: 'Manual Operations', policy: 'require_approval',
      scope: 'global', agent_id: null },
  ],
  // The catch-all: core's own statics and anything no registered domain claims.
  other: [
    { action_category: 'status_update', agent_bucket: 'Manual Operations', policy: 'notify_and_proceed',
      scope: 'global', agent_id: null },
  ],
};

// Old-shape rows (no agent_bucket): a server older than this interface.
const OLD_SHAPE = {
  node_lifecycle: [
    // An operator's own agent, reachable only through by_domain.
    { action_category: 'system.instance_terminate', policy: 'notify_and_proceed', scope: 'agent',
      agent_id: 'ops-custom-uuid', agent_name: 'Ops Team Custom Agent' },
    // Not agent-scoped, yet it names an agent. The server buckets it manual.
    { action_category: 'system.task.ssh_command', policy: 'require_approval', scope: 'action_type',
      agent_id: 'fleet-uuid', agent_name: 'Fleet Autonomy' },
  ],
};

// Rows whose group cannot be determined, or cannot be written back to.
const UNREADABLE = {
  gitops: [
    { action_category: 'system.gitops_sync', policy: 'auto_approve' },
    { action_category: 'system.gitops_apply_proposal', policy: 'notify_and_proceed', scope: 'agent', agent_id: 'u' },
    // Nameable but not addressable: a save would degrade to an ACCOUNT-WIDE row.
    { action_category: 'system.gitops_register_repository', policy: 'auto_approve', scope: 'agent',
      agent_name: 'GitOps Reconciler' },
  ],
};

async function renderSections(props: { namespace?: string } = { namespace: 'sys' }) {
  render(<PolicyDomainSections {...props} />);
  await waitFor(() => expect(screen.queryByText('Loading…')).not.toBeInTheDocument());
}

function openSection(label: string) {
  fireEvent.click(screen.getByRole('button', { name: new RegExp(label) }));
}

function groupBox(label: string): HTMLElement {
  const box = screen.getByText(label).closest('div.rounded-lg');
  if (!box) throw new Error(`no group box rendered for ${label}`);
  return box as HTMLElement;
}

/** The `<select>` next to an action row's label, or null when read-only. */
function selectFor(action: string): HTMLSelectElement | null {
  const row = screen.getByText(action).closest('div');
  return (row?.querySelector('select') as HTMLSelectElement) || null;
}

function sidebarLabels(): string[] {
  return within(screen.getByRole('navigation'))
    .getAllByRole('button')
    .map((b) => (b.textContent || '').replace(/\d+$/, '').trim());
}

beforeEach(() => {
  mockGet.mockReset();
  mockPatch.mockReset();
  presentDomains();
});

afterEach(() => featureRegistry.clear());

describe('PolicyDomainSections — renders the server\'s rows', () => {
  beforeEach(() => mockGet.mockResolvedValue(groupedResponse(SERVER_DRIVEN)));

  it('reads the grouped view (guards the negative assertions below)', async () => {
    await renderSections();

    expect(mockGet).toHaveBeenCalledWith('/ai/intervention_policies/grouped');
    expect(screen.getByText('system.cert_rotate')).toBeInTheDocument();
  });

  it('orders sections by presentation, then unpresented keys, opening on the first', async () => {
    await renderSections();

    expect(sidebarLabels()).toEqual(['Node Lifecycle', 'Container Runtimes', 'GitOps', 'Quarantine']);
    expect(screen.getByRole('heading', { name: 'Node Lifecycle' })).toBeInTheDocument();
  });

  it('renders a domain nothing presents, under a derived label', async () => {
    await renderSections();

    openSection('Quarantine');

    expect(screen.getByText('system.made_up_future_action')).toBeInTheDocument();
  });

  it('hides empty domains', async () => {
    await renderSections();

    expect(screen.queryByRole('button', { name: /Disk Image/ })).not.toBeInTheDocument();
  });

  it('shows the row\'s own verb, not the hook\'s miss default', async () => {
    await renderSections();

    openSection('GitOps');

    expect(selectFor('system.gitops_apply_proposal')?.value).toBe('notify_and_proceed');
  });

  it('renders one group per agent in the domain, carrying that agent\'s rows', async () => {
    await renderSections();

    const fleet = groupBox('Node Lifecycle · Fleet Autonomy');
    const manual = groupBox('Node Lifecycle · Manual Operations');
    expect(within(fleet).getByText('system.cert_rotate')).toBeInTheDocument();
    expect(within(fleet).getByText('system.instance_reboot')).toBeInTheDocument();
    expect(within(manual).getByText('system.task.start')).toBeInTheDocument();
  });

  it('badges each section with the rows it lists', async () => {
    await renderSections();

    expect(screen.getByRole('button', { name: /Node Lifecycle/ })).toHaveTextContent('3');
  });

  describe('scoped to a namespace', () => {
    it('offers no catch-all section and none another namespace presents', async () => {
      await renderSections();

      expect(screen.queryByRole('button', { name: /Other/ })).not.toBeInTheDocument();
      expect(screen.queryByRole('button', { name: /Billing Operations/ })).not.toBeInTheDocument();
      expect(screen.queryByText('status_update')).not.toBeInTheDocument();
      expect(screen.queryByText('billing.refund')).not.toBeInTheDocument();
    });
  });

  describe('unscoped (the core Autonomy page)', () => {
    it('shows every namespace\'s domains and the catch-all, last', async () => {
      await renderSections({});

      expect(sidebarLabels()).toEqual([
        'Node Lifecycle', 'Container Runtimes', 'GitOps', 'Billing Operations', 'Quarantine', 'Other policies',
      ]);
      openSection('Other policies');
      expect(screen.getByText('status_update')).toBeInTheDocument();
    });
  });

  it('saves every edit in one bulk request, each entry addressed to its own row', async () => {
    mockPatch.mockResolvedValue({ data: { success: true } });
    await renderSections();

    fireEvent.change(selectFor('system.cert_rotate') as HTMLSelectElement, { target: { value: 'block' } });
    fireEvent.change(selectFor('system.task.start') as HTMLSelectElement, { target: { value: 'auto_approve' } });
    fireEvent.click(screen.getAllByText('Save Permissions')[0]);

    await waitFor(() => expect(mockPatch).toHaveBeenCalledTimes(1));
    const [url, body] = mockPatch.mock.calls[0] as [string, { updates: Array<Record<string, unknown>> }];
    expect(url).toBe('/ai/intervention_policies/bulk');
    expect(body.updates).toEqual(
      expect.arrayContaining([
        { action_category: 'system.cert_rotate', policy: 'block', scope: 'agent', agent_id: 'fleet-uuid' },
        { action_category: 'system.task.start', policy: 'auto_approve', scope: 'global', agent_id: null },
      ])
    );
    expect(body.updates).toHaveLength(2);
  });

  it('marks the groups dirty after an edit and clean after the save', async () => {
    mockPatch.mockResolvedValue({ data: { success: true } });
    await renderSections();

    expect(screen.queryByText(/unsaved/i)).not.toBeInTheDocument();
    expect(screen.getAllByText('Save Permissions')[0].closest('button')).toBeDisabled();
    fireEvent.change(selectFor('system.cert_rotate') as HTMLSelectElement, { target: { value: 'block' } });
    expect(screen.getByTestId('policy-unsaved-changes')).toBeInTheDocument();
    expect(screen.getAllByText('Save Permissions')[0].closest('button')).toBeEnabled();

    fireEvent.click(screen.getAllByText('Save Permissions')[0]);
    await waitFor(() => expect(screen.queryByText(/unsaved/i)).not.toBeInTheDocument());
  });
});

describe('PolicyDomainSections — loading and empty', () => {
  it('shows a loading state until the payload arrives', async () => {
    let resolve: (v: unknown) => void = () => undefined;
    mockGet.mockReturnValue(new Promise((r) => { resolve = r; }));
    render(<PolicyDomainSections namespace="sys" />);

    expect(screen.getByText('Loading…')).toBeInTheDocument();
    resolve(groupedResponse(SERVER_DRIVEN));
    await waitFor(() => expect(screen.queryByText('Loading…')).not.toBeInTheDocument());
  });

  it('explains itself rather than rendering blank when there are no rows', async () => {
    mockGet.mockResolvedValue(groupedResponse({ node_lifecycle: [], other: [] }));
    await renderSections();

    expect(screen.getByText(/No intervention policies are configured/)).toBeInTheDocument();
  });
});

describe('PolicyDomainSections — a server that predates agent_bucket', () => {
  beforeEach(() => mockGet.mockResolvedValue(groupedResponse(OLD_SHAPE)));

  it('groups an old-shape agent row under its own agent, not Manual Operations', async () => {
    await renderSections();

    const agentGroup = groupBox('Node Lifecycle · Ops Team Custom Agent');
    const manualGroup = groupBox('Node Lifecycle · Manual Operations');
    expect(within(agentGroup).getByText('system.instance_terminate')).toBeInTheDocument();
    expect(within(manualGroup).queryByText('system.instance_terminate')).not.toBeInTheDocument();
    expect(within(manualGroup).getByText('system.task.ssh_command')).toBeInTheDocument();
    expect(selectFor('system.instance_terminate')?.value).toBe('notify_and_proceed');
  });

  it('keys on scope, not agent_name, so a non-agent row stays manual', async () => {
    mockGet.mockResolvedValue(groupedResponse({ node_lifecycle: [OLD_SHAPE.node_lifecycle[1]] }));
    await renderSections();

    expect(screen.getByText('Node Lifecycle · Manual Operations')).toBeInTheDocument();
    expect(screen.queryByText('Node Lifecycle · Fleet Autonomy')).not.toBeInTheDocument();
  });

  // "Set all" applies one verb to every action IN ITS GROUP, so a mis-grouped
  // agent row would receive a verb the operator never chose for it.
  it('a bulk set in the manual group cannot reach an agent-scoped row', async () => {
    mockPatch.mockResolvedValue({ data: { success: true } });
    await renderSections();

    const manualGroup = groupBox('Node Lifecycle · Manual Operations');
    const setAll = manualGroup.querySelector('select') as HTMLSelectElement;
    expect(within(setAll).getByText('Set all')).toBeInTheDocument();
    fireEvent.change(setAll, { target: { value: 'auto_approve' } });
    fireEvent.click(within(manualGroup).getByText('Save Permissions'));

    await waitFor(() => expect(mockPatch).toHaveBeenCalled());
    const [, body] = mockPatch.mock.calls[0] as [string, { updates: Array<Record<string, unknown>> }];
    expect(body.updates.map((u) => u.action_category)).toEqual(['system.task.ssh_command']);
  });
});

describe('PolicyDomainSections — rows whose posture cannot be read', () => {
  beforeEach(() => mockGet.mockResolvedValue(groupedResponse(UNREADABLE)));

  it('says so instead of showing a confident posture', async () => {
    await renderSections();

    expect(screen.getByText('GitOps · Posture unknown')).toBeInTheDocument();
    expect(screen.getByTestId('autonomy-skew-warning')).toBeInTheDocument();
    expect(screen.queryByText('GitOps · Manual Operations')).not.toBeInTheDocument();
  });

  it('offers no control, bulk or single, over state it cannot read, and never saves', async () => {
    await renderSections();

    expect(selectFor('system.gitops_sync')).toBeNull();
    expect(selectFor('system.gitops_apply_proposal')).toBeNull();
    expect(selectFor('system.gitops_register_repository')).toBeNull();
    expect(screen.queryByText('GitOps · GitOps Reconciler')).not.toBeInTheDocument();
    expect(screen.queryByText('Save Permissions')).not.toBeInTheDocument();
    expect(screen.queryByText('Set all')).not.toBeInTheDocument();
    expect(mockPatch).not.toHaveBeenCalled();
  });

  it('counts unreadable rows in the sidebar badge', async () => {
    await renderSections();

    expect(screen.getByRole('button', { name: /GitOps/ })).toHaveTextContent('3');
  });
});

describe('PolicyDomainSections — the stale-version warning covers every section', () => {
  it('warns while a fully readable section is on screen', async () => {
    mockGet.mockResolvedValue(
      groupedResponse({ ...OLD_SHAPE, gitops: [{ action_category: 'system.gitops_sync', policy: 'auto_approve' }] })
    );
    await renderSections();

    expect(screen.getByText('Node Lifecycle · Ops Team Custom Agent')).toBeInTheDocument();
    expect(screen.queryByText('GitOps · Posture unknown')).not.toBeInTheDocument();
    expect(screen.getByTestId('autonomy-skew-warning')).toBeInTheDocument();
  });

  it('does not warn when every row was placeable', async () => {
    mockGet.mockResolvedValue(groupedResponse(OLD_SHAPE));
    await renderSections();

    expect(screen.queryByTestId('autonomy-skew-warning')).not.toBeInTheDocument();
  });
});
