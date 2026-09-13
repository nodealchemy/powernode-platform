import { screen, waitFor, fireEvent } from '@testing-library/react';
import { renderWithProviders } from '@/shared/utils/test-utils';
import { CampaignDetailModal } from './CampaignDetailModal';
import { campaignsApi } from '../api/campaignsApi';
import type { CampaignDetail, CampaignStatus } from '../types/campaign';

jest.mock('../api/campaignsApi', () => ({
  __esModule: true,
  campaignsApi: {
    getCampaign: jest.fn(),
    resumeCampaign: jest.fn(),
    stopCampaign: jest.fn(),
    answerQuestion: jest.fn(),
    delegateCampaign: jest.fn(),
  },
}));

const mockAddNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: mockAddNotification, showNotification: jest.fn() }),
}));

const api = campaignsApi as jest.Mocked<typeof campaignsApi>;

const detail = (over: Partial<CampaignDetail> = {}): CampaignDetail => ({
  id: 'c1', name: 'Resumable', status: 'completed', decision_authority: 'trusted',
  loop_count: 1, total_tasks: 2, completed_tasks: 0, failed_tasks: 2, blocked_tasks: 0,
  open_questions: 0, completion_pct: 0, started_at: null, completed_at: null, last_activity_at: null,
  driver_lease: null, description: null, configuration: {}, stop_conditions: { max_failed: 2 },
  open_questions_list: [], recent_decisions: [], activity: [], progress: [], loops: [], ...over,
});

const renderModal = (canManage: boolean) =>
  renderWithProviders(
    <CampaignDetailModal campaignId="c1" isOpen onClose={jest.fn()} canManage={canManage} onChanged={jest.fn()} />,
  );

const openResumeForm = async () => {
  fireEvent.click(await screen.findByRole('button', { name: /^resume$/i }));
  return screen.getByRole('button', { name: /resume campaign/i });
};

describe('CampaignDetailModal — resume', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    api.getCampaign.mockResolvedValue({ success: true, data: detail() } as never);
  });

  it.each<CampaignStatus>(['completed', 'paused'])('offers Resume on a %s campaign to a manager', async (status) => {
    api.getCampaign.mockResolvedValue({ success: true, data: detail({ status }) } as never);
    renderModal(true);
    expect(await screen.findByRole('button', { name: /^resume$/i })).toBeInTheDocument();
  });

  it.each<CampaignStatus>(['active', 'archived', 'created'])('hides Resume on a %s campaign', async (status) => {
    api.getCampaign.mockResolvedValue({ success: true, data: detail({ status }) } as never);
    renderModal(true);
    await screen.findByText('Failed');
    expect(screen.queryByRole('button', { name: /^resume$/i })).not.toBeInTheDocument();
  });

  it('hides Resume without the manage permission', async () => {
    renderModal(false);
    await screen.findByText('Failed');
    expect(screen.queryByRole('button', { name: /^resume$/i })).not.toBeInTheDocument();
  });

  it('requires a reason and sends only the stop conditions the operator filled in', async () => {
    api.resumeCampaign.mockResolvedValue({
      success: true, data: { campaign: detail({ status: 'active' }), decision_id: 'd1', stop_conditions: {} },
    } as never);
    renderModal(true);

    const submit = await openResumeForm();
    expect(submit).toBeDisabled();

    fireEvent.change(screen.getByLabelText('Resume reason'), { target: { value: 'raise the cap' } });
    fireEvent.change(screen.getByLabelText('Max failed tasks'), { target: { value: '6' } });
    expect(submit).not.toBeDisabled();
    fireEvent.click(submit);

    await waitFor(() =>
      expect(api.resumeCampaign).toHaveBeenCalledWith('c1', {
        reason: 'raise the cap',
        stop_conditions: { max_failed: 6 },
      }),
    );
  });

  it("shows the server's refusal reason verbatim on a 422", async () => {
    const reason =
      "campaign_resume refused: campaign 'Resumable' is held by driver 'driver-loop-1' until " +
      "2026-09-11T12:00:00Z; a campaign's own driver cannot re-arm it.";
    api.resumeCampaign.mockRejectedValue({
      response: { status: 422, data: { success: false, error: reason } },
      message: 'Request failed with status code 422',
    });
    renderModal(true);

    const submit = await openResumeForm();
    fireEvent.change(screen.getByLabelText('Resume reason'), { target: { value: 'try' } });
    fireEvent.click(submit);

    await waitFor(() =>
      expect(mockAddNotification).toHaveBeenCalledWith(expect.objectContaining({ type: 'error', message: reason })),
    );
  });
});
