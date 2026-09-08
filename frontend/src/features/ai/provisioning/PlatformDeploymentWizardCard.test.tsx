import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { PlatformDeploymentWizardCard } from './PlatformDeploymentWizardCard';
import type { ChatCard } from '@/shared/types/ai';

// IMP-6db06a13b6c5 — Platform::VolumesController is a REST shim whose header
// says it exists so the deployment wizard can "create + list volumes". Only
// the create half was wired: nothing called the index, so the wizard could
// mint a volume but never show the operator which ones already exist — the
// step that stops them minting a duplicate of one they made minutes earlier.

const mockListPlatformVolumes = jest.fn();
const mockCreatePlatformVolume = jest.fn();

jest.mock('./services/provisioningApi', () => ({
  provisioningApi: {
    listPlatformVolumes: (...args: unknown[]) => mockListPlatformVolumes(...args),
    createPlatformVolume: (...args: unknown[]) => mockCreatePlatformVolume(...args),
  },
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: jest.fn() }),
}));

let mockHasPermission = jest.fn((_permission: string) => true);

jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({ hasPermission: (p: string) => mockHasPermission(p) }),
}));

const page = (volumes: unknown[], over: Record<string, unknown> = {}) => ({
  volumes,
  count: volumes.length,
  hasMore: false,
  ...over,
});

const formCard = (storage: Record<string, unknown> = {}): ChatCard => ({
  kind: 'platform_deployment_wizard',
  tool: 'platform_deploy',
  payload: {
    card: {
      kind: 'platform_deployment_wizard',
      phase: 'form',
      fields: [],
      modes: [{ value: 'standalone', label: 'Standalone', help: '' }],
      templates: [{ value: 'powernode-hub', label: 'Hub' }],
      spawn_modes: [{ value: 'managed_child', label: 'Managed child' }],
      defaults: {},
      storage: {
        // 'api' is the default serviceRole, so the storage section renders.
        stateful_roles: ['api'],
        mount_points: { api: '/data' },
        recommended_size_gb_by_role: { api: 10 },
        available_volumes: [],
        ...storage,
      },
    },
  },
});

describe('PlatformDeploymentWizardCard existing volumes', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockHasPermission = jest.fn((_permission: string) => true);
    mockListPlatformVolumes.mockResolvedValue(page([]));
  });

  it('lists the volumes that already exist on the account', async () => {
    mockListPlatformVolumes.mockResolvedValue(
      page([{ id: 'v-1', name: 'pg-data', size_gb: 50, status: 'available', transport: 'nfs' }]),
    );

    render(<PlatformDeploymentWizardCard card={formCard()} />);

    expect(await screen.findByText('pg-data')).toBeInTheDocument();
    expect(mockListPlatformVolumes).toHaveBeenCalledTimes(1);
  });

  it('says so when the account has no volumes yet', async () => {
    render(<PlatformDeploymentWizardCard card={formCard()} />);

    expect(await screen.findByText(/no volumes on this account/i)).toBeInTheDocument();
  });

  it('surfaces a failed fetch without hiding the rest of the form', async () => {
    mockListPlatformVolumes.mockRejectedValue(new Error('volume service unavailable'));

    render(<PlatformDeploymentWizardCard card={formCard()} />);

    expect(await screen.findByText('volume service unavailable')).toBeInTheDocument();
    // Still usable: a failed listing must not block deploying. The section
    // header alone would not show that — it renders on the role regardless —
    // so the picker and the submit are what get asserted.
    // The Auto-pick entry belongs to the volume picker alone, so finding it
    // proves the picker rendered rather than that some select did.
    expect(screen.getByRole('option', { name: /Auto-pick/ })).toBeInTheDocument();

    // And the form still submits: Deploy is gated on the name being filled in,
    // not on whether the volume read succeeded.
    fireEvent.change(screen.getByPlaceholderText('e.g. west-hub-1'), {
      target: { value: 'west-hub-1' },
    });
    expect(screen.getByRole('button', { name: /deploy/i })).toBeEnabled();
  });

  it('offers a retry when the read failed', async () => {
    mockListPlatformVolumes.mockRejectedValueOnce(new Error('volume service unavailable'));
    mockListPlatformVolumes.mockResolvedValue(
      page([{ id: 'v-1', name: 'pg-data', size_gb: 50, status: 'available' }]),
    );

    render(<PlatformDeploymentWizardCard card={formCard()} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Try again' }));

    expect(await screen.findByText('pg-data')).toBeInTheDocument();
  });

  it('prefers the server sentence over the axios status line', async () => {
    mockListPlatformVolumes.mockRejectedValue(
      Object.assign(new Error('Request failed with status code 403'), {
        response: { data: { error: 'Forbidden' } },
      }),
    );

    render(<PlatformDeploymentWizardCard card={formCard()} />);

    expect(await screen.findByText('Forbidden')).toBeInTheDocument();
    expect(screen.queryByText(/status code 403/)).not.toBeInTheDocument();
  });

  it('shows a loading state before the read lands', async () => {
    let resolve: (v: unknown) => void = () => {};
    mockListPlatformVolumes.mockReturnValue(new Promise((r) => { resolve = r; }));

    render(<PlatformDeploymentWizardCard card={formCard()} />);

    // Not "no volumes": the account is unread, not empty.
    expect(screen.getByText(/loading volumes/i)).toBeInTheDocument();
    expect(screen.queryByText(/no volumes on this account/i)).not.toBeInTheDocument();

    await act(async () => { resolve(page([])); });
    expect(screen.getByText(/no volumes on this account/i)).toBeInTheDocument();
  });

  it('never offers a volume that is attached or not yet available', async () => {
    // The card payload's snapshot is already narrowed to available+unattached;
    // the live read is not narrowed at all. Offering a volume mounted on
    // another instance as the target of a new deployment is worse than not
    // listing it — the orchestrator would never auto-pick it either.
    mockListPlatformVolumes.mockResolvedValue(
      page([
        { id: 'v-att', name: 'busy-vol', size_gb: 100, status: 'available', attached_to: 'i-1' },
        { id: 'v-new', name: 'still-creating', size_gb: 100, status: 'creating' },
        { id: 'v-ok', name: 'free-vol', size_gb: 100, status: 'available', attached_to: null },
      ]),
    );

    render(<PlatformDeploymentWizardCard card={formCard()} />);

    expect(await screen.findByRole('option', { name: /free-vol/ })).toBeInTheDocument();
    expect(screen.queryByRole('option', { name: /busy-vol/ })).not.toBeInTheDocument();
    expect(screen.queryByRole('option', { name: /still-creating/ })).not.toBeInTheDocument();

    // They are still LISTED, though: seeing that a name is taken is how an
    // operator learns not to reuse it.
    expect(screen.getByText('busy-vol')).toBeInTheDocument();
  });

  it('does not offer a volume smaller than the role needs', async () => {
    mockListPlatformVolumes.mockResolvedValue(
      page([
        { id: 'v-small', name: 'tiny-vol', size_gb: 1, status: 'available' },
        { id: 'v-big', name: 'roomy-vol', size_gb: 50, status: 'available' },
      ]),
    );

    render(<PlatformDeploymentWizardCard card={formCard()} />);

    expect(await screen.findByRole('option', { name: /roomy-vol/ })).toBeInTheDocument();
    expect(screen.queryByRole('option', { name: /tiny-vol/ })).not.toBeInTheDocument();
  });

  it('says so when the page it read is only part of the account', async () => {
    // A partial list cannot answer "does this already exist?", which is the
    // question the panel is here for.
    mockListPlatformVolumes.mockResolvedValue(
      page([{ id: 'v-1', name: 'pg-data', size_gb: 50, status: 'available' }], {
        count: 340,
        hasMore: true,
      }),
    );

    render(<PlatformDeploymentWizardCard card={formCard()} />);

    expect(await screen.findByText(/showing 1 of 340/i)).toBeInTheDocument();
  });

  it('says nothing about volumes without system.volumes.read', async () => {
    mockHasPermission = jest.fn((p: string) => p !== 'system.volumes.read');

    render(<PlatformDeploymentWizardCard card={formCard()} />);

    expect(await screen.findByText(/do not have permission to list volumes/i)).toBeInTheDocument();
    expect(mockListPlatformVolumes).not.toHaveBeenCalled();
  });

  it('does not ask for volumes when the role is not stateful', async () => {
    render(<PlatformDeploymentWizardCard card={formCard({ stateful_roles: ['worker'] })} />);

    await waitFor(() => expect(screen.queryByText('Persistent Storage')).not.toBeInTheDocument());
    expect(mockListPlatformVolumes).not.toHaveBeenCalled();
  });

  it('offers a fetched volume as a choice, not just as a row', async () => {
    // The card payload carries a snapshot taken when the card was rendered.
    // A volume created since then is only reachable if the fetched list feeds
    // the picker too.
    mockListPlatformVolumes.mockResolvedValue(
      page([{ id: 'v-9', name: 'made-five-minutes-ago', size_gb: 100, status: 'available' }]),
    );

    render(<PlatformDeploymentWizardCard card={formCard()} />);

    expect(
      await screen.findByRole('option', { name: /made-five-minutes-ago/ }),
    ).toBeInTheDocument();
  });
});
