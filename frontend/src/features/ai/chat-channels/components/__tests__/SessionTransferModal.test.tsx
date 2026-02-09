import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { SessionTransferModal } from '../SessionTransferModal';

jest.mock('@/shared/services/ai', () => ({
  chatChannelsApi: {
    transferSession: jest.fn(),
  },
  agentsApi: {
    getAgents: jest.fn(),
  },
}));

import { chatChannelsApi, agentsApi } from '@/shared/services/ai';

const mockedTransferSession = chatChannelsApi.transferSession as jest.Mock;
const mockedGetAgents = (agentsApi as any).getAgents as jest.Mock;

const mockSession = {
  id: 'session-1',
  platform_user_id: 'user123',
  platform_username: 'testuser',
  status: 'active' as const,
  message_count: 10,
  assigned_agent: 'Agent Alpha',
  last_activity_at: new Date().toISOString(),
  created_at: new Date().toISOString(),
};

const defaultProps = {
  isOpen: true,
  onClose: jest.fn(),
  session: mockSession,
  onTransferred: jest.fn(),
};

describe('SessionTransferModal', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockedGetAgents.mockResolvedValue({
      items: [
        { id: 'agent-1', name: 'Agent Alpha' },
        { id: 'agent-2', name: 'Agent Beta' },
      ],
    });
  });

  it('renders modal when open', async () => {
    render(<SessionTransferModal {...defaultProps} />);
    await waitFor(() => {
      expect(screen.getByText('Transfer Session')).toBeInTheDocument();
    });
  });

  it('does not render content when closed', () => {
    render(<SessionTransferModal {...defaultProps} isOpen={false} />);
    expect(screen.queryByText('Transfer Session')).not.toBeInTheDocument();
  });

  it('shows session info', async () => {
    render(<SessionTransferModal {...defaultProps} />);
    await waitFor(() => {
      expect(screen.getByText('user123')).toBeInTheDocument();
      expect(screen.getByText('@testuser')).toBeInTheDocument();
    });
  });

  it('fetches and displays agents', async () => {
    render(<SessionTransferModal {...defaultProps} />);
    await waitFor(() => {
      expect(mockedGetAgents).toHaveBeenCalledWith({ per_page: 100 });
    });
    expect(screen.getByText('Agent Alpha')).toBeInTheDocument();
    expect(screen.getByText('Agent Beta')).toBeInTheDocument();
  });

  it('disables transfer button when no agent selected', async () => {
    render(<SessionTransferModal {...defaultProps} />);
    await waitFor(() => {
      expect(screen.getByText('Agent Alpha')).toBeInTheDocument();
    });
    const transferButton = screen.getByRole('button', { name: /transfer/i });
    expect(transferButton).toBeDisabled();
  });

  it('calls transferSession on submit', async () => {
    mockedTransferSession.mockResolvedValue({ session: {}, message: 'ok' });
    render(<SessionTransferModal {...defaultProps} />);

    await waitFor(() => {
      expect(screen.getByText('Agent Alpha')).toBeInTheDocument();
    });

    // Select an agent from the dropdown
    const select = screen.getByRole('combobox');
    fireEvent.change(select, { target: { value: 'agent-2' } });

    // Click transfer
    const transferButton = screen.getByRole('button', { name: /transfer/i });
    fireEvent.click(transferButton);

    await waitFor(() => {
      expect(mockedTransferSession).toHaveBeenCalledWith('session-1', 'agent-2');
    });
    expect(defaultProps.onTransferred).toHaveBeenCalled();
    expect(defaultProps.onClose).toHaveBeenCalled();
  });

  it('shows error state on failure', async () => {
    mockedTransferSession.mockRejectedValue(new Error('Transfer failed'));
    render(<SessionTransferModal {...defaultProps} />);

    await waitFor(() => {
      expect(screen.getByText('Agent Alpha')).toBeInTheDocument();
    });

    const select = screen.getByRole('combobox');
    fireEvent.change(select, { target: { value: 'agent-1' } });

    fireEvent.click(screen.getByRole('button', { name: /transfer/i }));

    await waitFor(() => {
      expect(screen.getByText('Transfer failed')).toBeInTheDocument();
    });
  });

  it('shows error when agents fail to load', async () => {
    mockedGetAgents.mockRejectedValue(new Error('Network error'));
    render(<SessionTransferModal {...defaultProps} />);

    await waitFor(() => {
      expect(screen.getByText('Failed to load agents')).toBeInTheDocument();
    });
  });

  it('calls onClose on cancel', async () => {
    render(<SessionTransferModal {...defaultProps} />);
    await waitFor(() => {
      expect(screen.getByText('Transfer Session')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByRole('button', { name: /cancel/i }));
    expect(defaultProps.onClose).toHaveBeenCalled();
  });
});
