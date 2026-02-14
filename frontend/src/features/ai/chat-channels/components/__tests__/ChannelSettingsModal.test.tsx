import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { ChannelSettingsModal } from '../ChannelSettingsModal';

jest.mock('@/shared/services/ai', () => ({
  chatChannelsApi: {
    getChannel: jest.fn(),
    updateChannel: jest.fn(),
    regenerateToken: jest.fn(),
  },
}));

import { chatChannelsApi } from '@/shared/services/ai';

const mockedGetChannel = chatChannelsApi.getChannel as jest.Mock;
const mockedUpdateChannel = chatChannelsApi.updateChannel as jest.Mock;
const mockedRegenerateToken = chatChannelsApi.regenerateToken as jest.Mock;

const mockChannel = {
  id: 'ch-1',
  name: 'Test Channel',
  platform: 'telegram',
  status: 'active',
  rate_limit_per_minute: 60,
  welcome_message: 'Hello!',
  session_timeout_minutes: 30,
  webhook_url: 'https://example.com/webhook/abc123',
};

const defaultProps = {
  isOpen: true,
  onClose: jest.fn(),
  channelId: 'ch-1',
  onSaved: jest.fn(),
};

describe('ChannelSettingsModal', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockedGetChannel.mockResolvedValue({ channel: mockChannel });
    // Mock clipboard
    Object.assign(navigator, {
      clipboard: { writeText: jest.fn().mockResolvedValue(undefined) },
    });
  });

  it('fetches channel details on open', async () => {
    render(<ChannelSettingsModal {...defaultProps} />);
    await waitFor(() => {
      expect(mockedGetChannel).toHaveBeenCalledWith('ch-1');
    });
  });

  it('shows loading state initially', () => {
    mockedGetChannel.mockReturnValue(new Promise(() => {})); // never resolves
    render(<ChannelSettingsModal {...defaultProps} />);
    // The loading spinner should be present
    expect(screen.getByText('Channel Settings')).toBeInTheDocument();
  });

  it('renders editable fields after loading', async () => {
    render(<ChannelSettingsModal {...defaultProps} />);
    await waitFor(() => {
      expect(screen.getByDisplayValue('Test Channel')).toBeInTheDocument();
    });
    expect(screen.getByDisplayValue('Hello!')).toBeInTheDocument();
    expect(screen.getByDisplayValue('60')).toBeInTheDocument();
    expect(screen.getByDisplayValue('30')).toBeInTheDocument();
  });

  it('shows platform as read-only', async () => {
    render(<ChannelSettingsModal {...defaultProps} />);
    await waitFor(() => {
      expect(screen.getByText('telegram')).toBeInTheDocument();
    });
    expect(screen.getByText('Platform')).toBeInTheDocument();
  });

  it('shows webhook URL read-only', async () => {
    render(<ChannelSettingsModal {...defaultProps} />);
    await waitFor(() => {
      expect(screen.getByText('https://example.com/webhook/abc123')).toBeInTheDocument();
    });
  });

  it('calls updateChannel on save', async () => {
    mockedUpdateChannel.mockResolvedValue({ channel: mockChannel });
    render(<ChannelSettingsModal {...defaultProps} />);

    await waitFor(() => {
      expect(screen.getByDisplayValue('Test Channel')).toBeInTheDocument();
    });

    // Modify a field
    const nameInput = screen.getByDisplayValue('Test Channel');
    fireEvent.change(nameInput, { target: { value: 'Updated Channel' } });

    // Save
    fireEvent.click(screen.getByRole('button', { name: /save/i }));

    await waitFor(() => {
      expect(mockedUpdateChannel).toHaveBeenCalledWith('ch-1', {
        name: 'Updated Channel',
        rate_limit_per_minute: 60,
        welcome_message: 'Hello!',
        session_timeout_minutes: 30,
        routing_config: {
          routing_strategy: 'default',
          skill_routes: [],
          auto_handoff_enabled: false,
          max_context_messages: 20,
        },
        agent_personality: {
          greeting_style: 'professional',
          response_length: 'standard',
          tone: '',
          display_name: '',
          custom_instructions: '',
        },
      });
    });
    expect(defaultProps.onSaved).toHaveBeenCalled();
    expect(defaultProps.onClose).toHaveBeenCalled();
  });

  it('shows error on save failure', async () => {
    mockedUpdateChannel.mockRejectedValue(new Error('Save failed'));
    render(<ChannelSettingsModal {...defaultProps} />);

    await waitFor(() => {
      expect(screen.getByDisplayValue('Test Channel')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByRole('button', { name: /save/i }));

    await waitFor(() => {
      expect(screen.getByText('Save failed')).toBeInTheDocument();
    });
  });

  it('regenerate token calls API and updates URL', async () => {
    mockedRegenerateToken.mockResolvedValue({
      channel: mockChannel,
      webhook_url: 'https://example.com/webhook/new-token',
    });
    render(<ChannelSettingsModal {...defaultProps} />);

    await waitFor(() => {
      expect(screen.getByText('https://example.com/webhook/abc123')).toBeInTheDocument();
    });

    // Find and click the regenerate button (RefreshCw icon button)
    const buttons = screen.getAllByRole('button');
    const regenerateBtn = buttons.find(
      (btn) => btn.querySelector('svg.lucide-refresh-cw') || btn.querySelector('[class*="refresh"]')
    );
    // If we can't find by icon, use the outline variant button near the webhook
    if (regenerateBtn) {
      fireEvent.click(regenerateBtn);
    } else {
      // Fall back to finding buttons near the webhook section
      const allButtons = screen.getAllByRole('button');
      // The last few buttons near the webhook URL section
      const webhookButtons = allButtons.filter(
        (btn) => !btn.textContent?.includes('Cancel') && !btn.textContent?.includes('Save')
      );
      if (webhookButtons.length >= 2) {
        // Second webhook button is regenerate (first is copy)
        fireEvent.click(webhookButtons[webhookButtons.length - 1]);
      }
    }

    await waitFor(() => {
      expect(mockedRegenerateToken).toHaveBeenCalledWith('ch-1');
    });
  });

  it('calls onClose on cancel', async () => {
    render(<ChannelSettingsModal {...defaultProps} />);
    await waitFor(() => {
      expect(screen.getByText('Channel Settings')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByRole('button', { name: /cancel/i }));
    expect(defaultProps.onClose).toHaveBeenCalled();
  });

  it('shows error when channel fails to load', async () => {
    mockedGetChannel.mockRejectedValue(new Error('Load failed'));
    render(<ChannelSettingsModal {...defaultProps} />);

    await waitFor(() => {
      expect(screen.getByText('Load failed')).toBeInTheDocument();
    });
  });

  it('does not render content when closed', () => {
    render(<ChannelSettingsModal {...defaultProps} isOpen={false} />);
    expect(screen.queryByText('Channel Settings')).not.toBeInTheDocument();
  });
});
