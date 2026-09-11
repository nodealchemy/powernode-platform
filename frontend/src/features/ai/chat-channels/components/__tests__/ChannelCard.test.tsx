import { render, screen } from '@testing-library/react';
import { ChannelCard } from '../ChannelCard';
import type { ChatChannelSummary } from '@/shared/services/ai';

// jest.config.js sets resetMocks: true, which strips a jest.fn()'s
// constructor-time implementation before every test, so the default has to
// be (re-)established in beforeEach, not just once at module load.
const mockCurrentUser = jest.fn();
jest.mock('@/shared/hooks/useAuth', () => ({
  useAuth: () => ({ currentUser: mockCurrentUser() }),
}));

const activeChannel: ChatChannelSummary = {
  id: 'ch-1',
  name: 'Test Channel',
  platform: 'telegram',
  status: 'active',
  active_sessions: 2,
  total_sessions: 10,
  last_message_at: undefined,
} as ChatChannelSummary;

const inactiveChannel: ChatChannelSummary = { ...activeChannel, status: 'inactive' } as ChatChannelSummary;

describe('ChannelCard', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  // The backend gates connect/disconnect on chat.channels.manage
  // (Api::V1::Chat::ChannelsController); chat.channels.read only lists/reads.
  // Without this gate a read-only operator sees a button that 403s on click.
  describe('with chat.channels.manage', () => {
    beforeEach(() => {
      mockCurrentUser.mockReturnValue({ permissions: ['chat.channels.read', 'chat.channels.manage'] });
    });

    it('shows Disconnect for an active channel', () => {
      render(<ChannelCard channel={activeChannel} />);
      expect(screen.getByText('Disconnect')).toBeInTheDocument();
      expect(screen.queryByText('Connect')).not.toBeInTheDocument();
    });

    it('shows Connect for an inactive channel', () => {
      render(<ChannelCard channel={inactiveChannel} />);
      expect(screen.getByText('Connect')).toBeInTheDocument();
      expect(screen.queryByText('Disconnect')).not.toBeInTheDocument();
    });
  });

  describe('without chat.channels.manage', () => {
    beforeEach(() => {
      mockCurrentUser.mockReturnValue({ permissions: ['chat.channels.read'] });
    });

    it('hides Disconnect for an active channel', () => {
      render(<ChannelCard channel={activeChannel} />);
      expect(screen.queryByText('Disconnect')).not.toBeInTheDocument();
    });

    it('hides Connect for an inactive channel', () => {
      render(<ChannelCard channel={inactiveChannel} />);
      expect(screen.queryByText('Connect')).not.toBeInTheDocument();
    });

    it('still shows the settings button', () => {
      render(<ChannelCard channel={activeChannel} />);
      expect(screen.getByLabelText('Channel settings')).toBeInTheDocument();
    });
  });
});
