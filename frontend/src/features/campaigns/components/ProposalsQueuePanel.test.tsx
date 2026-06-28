import { screen, waitFor, fireEvent } from '@testing-library/react';
import { renderWithProviders } from '@/shared/utils/test-utils';
import { ProposalsQueuePanel } from './ProposalsQueuePanel';
import { campaignsApi } from '../api/campaignsApi';
import type { CampaignProposal } from '../types/campaign';

jest.mock('../api/campaignsApi', () => ({
  __esModule: true,
  campaignsApi: {
    getProposals: jest.fn(),
    queueProposal: jest.fn(),
    approveProposal: jest.fn(),
    rejectProposal: jest.fn(),
    spawnProposal: jest.fn(),
  },
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: jest.fn(), showNotification: jest.fn() }),
}));

const api = campaignsApi as jest.Mocked<typeof campaignsApi>;

const proposal = (over: Partial<CampaignProposal> = {}): CampaignProposal => ({
  id: 'p1', title: 'Drain backlog', objective: 'Fix N+1s', source: 'improvement',
  scope: 'core', status: 'queued', suggested_workload: 'improvement-campaign',
  suggested_driver: null, decision_authority: 'trusted', fingerprint: 'fp',
  spawned_campaign_id: null, reviewed_by_id: null, reviewed_at: null,
  rejection_reason: null, created_at: '', updated_at: '', ...over,
});

describe('ProposalsQueuePanel', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    api.getProposals.mockResolvedValue({ success: true, data: { proposals: [proposal()], total_count: 1 } } as never);
    api.approveProposal.mockResolvedValue({ success: true, data: proposal({ status: 'approved' }) } as never);
  });

  it('lists proposals and approves a queued one', async () => {
    renderWithProviders(<ProposalsQueuePanel canManage onSpawned={jest.fn()} />);
    await waitFor(() => expect(screen.getByText('Drain backlog')).toBeInTheDocument());

    fireEvent.click(screen.getByText('Approve'));
    await waitFor(() => expect(api.approveProposal).toHaveBeenCalledWith('p1'));
  });

  it('hides action buttons without manage permission', async () => {
    renderWithProviders(<ProposalsQueuePanel canManage={false} />);
    await waitFor(() => expect(screen.getByText('Drain backlog')).toBeInTheDocument());
    expect(screen.queryByText('Approve')).not.toBeInTheDocument();
  });
});
