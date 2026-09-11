import { render, screen, waitFor } from '@testing-library/react';
import { ChannelSessions } from '../ChannelSessions';

jest.mock('@/shared/services/ai', () => ({
  chatChannelsApi: {
    getSessions: jest.fn(),
    closeSession: jest.fn(),
  },
}));

const mockAddNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: mockAddNotification }),
}));

// Default (set in beforeEach below): a manage-capable user, so the base
// tests exercise the same behavior they did before permission gating was
// added. The read-only case gets its own describe block further down.
const mockCurrentUser = jest.fn();
jest.mock('@/shared/hooks/useAuth', () => ({
  useAuth: () => ({ currentUser: mockCurrentUser() }),
}));

import { chatChannelsApi } from '@/shared/services/ai';

const mockedGetSessions = chatChannelsApi.getSessions as jest.Mock;
const mockedCloseSession = chatChannelsApi.closeSession as jest.Mock;

const activeSession = {
  id: 'sess-1',
  channel_id: 'ch-1',
  platform: 'telegram',
  platform_user_id: 'user-1',
  status: 'active',
  message_count: 3,
  last_activity_at: new Date().toISOString(),
};

const defaultProps = { channelId: 'ch-1' };

describe('ChannelSessions', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    // jest.config.js sets resetMocks: true, which strips a mock's
    // constructor-time implementation before every test — so the
    // manage-capable default has to be (re-)established here.
    mockCurrentUser.mockReturnValue({ permissions: ['chat.sessions.read', 'chat.sessions.manage'] });
    mockedGetSessions.mockResolvedValue({
      items: [activeSession],
      pagination: { total_count: 1 },
    });
    mockedCloseSession.mockResolvedValue({ session: { ...activeSession, status: 'closed' } });
  });

  it('shows Transfer and Close for an active session when the user can manage', async () => {
    render(<ChannelSessions {...defaultProps} onTransferSession={jest.fn()} />);
    await waitFor(() => {
      expect(screen.getByLabelText('Close session')).toBeInTheDocument();
    });
    expect(screen.getByLabelText('Transfer session')).toBeInTheDocument();
  });

  // The backend gates transfer/close on chat.sessions.manage
  // (server/app/controllers/api/v1/chat/sessions_controller.rb); chat.sessions.read
  // only lists/reads. Without this gate a read-only operator sees controls
  // that 403 on click.
  describe('without chat.sessions.manage', () => {
    beforeEach(() => {
      mockCurrentUser.mockReturnValue({ permissions: ['chat.sessions.read'] });
    });

    it('hides Transfer and Close for an active session', async () => {
      render(<ChannelSessions {...defaultProps} onTransferSession={jest.fn()} />);
      await waitFor(() => {
        expect(screen.getByText(activeSession.platform_user_id)).toBeInTheDocument();
      });
      expect(screen.queryByLabelText('Close session')).not.toBeInTheDocument();
      expect(screen.queryByLabelText('Transfer session')).not.toBeInTheDocument();
    });

    it('still shows the session list and Refresh', async () => {
      render(<ChannelSessions {...defaultProps} />);
      await waitFor(() => {
        expect(screen.getByText(activeSession.platform_user_id)).toBeInTheDocument();
      });
      expect(screen.getByLabelText('Refresh sessions')).toBeInTheDocument();
    });
  });
});
