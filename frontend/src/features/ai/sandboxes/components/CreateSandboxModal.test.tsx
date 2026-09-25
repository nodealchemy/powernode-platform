import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { CreateSandboxModal } from './CreateSandboxModal';

jest.mock('@/shared/services/ai', () => ({
  agentsApi: { getMyAgents: jest.fn() },
  containerExecutionApi: { createSandbox: jest.fn() },
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: jest.fn() }),
}));

import { agentsApi, containerExecutionApi } from '@/shared/services/ai';
const mockAgentsApi = agentsApi as jest.Mocked<typeof agentsApi>;
const mockApi = containerExecutionApi as jest.Mocked<typeof containerExecutionApi>;

describe('CreateSandboxModal', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (mockAgentsApi.getMyAgents as jest.Mock).mockResolvedValue([
      { id: 'agent-aaa', name: 'Agent A' },
      { id: 'agent-bbb', name: 'Agent B' },
    ]);
    (mockApi.createSandbox as jest.Mock).mockResolvedValue({ id: 'sandbox-1' });
  });

  const renderModal = (props: Partial<React.ComponentProps<typeof CreateSandboxModal>> = {}) =>
    render(<CreateSandboxModal isOpen onClose={jest.fn()} {...props} />);

  it('disables Create Sandbox until an agent is selected', async () => {
    renderModal();
    await waitFor(() => expect(screen.getByText('Agent A')).toBeInTheDocument());

    expect(screen.getByRole('button', { name: /Create Sandbox/i })).toBeDisabled();
  });

  it('calls createSandbox with exactly the selected agent id — not the first, not a hardcoded one', async () => {
    const onCreated = jest.fn();
    const onClose = jest.fn();
    renderModal({ onCreated, onClose });
    await waitFor(() => expect(screen.getByText('Agent B')).toBeInTheDocument());

    // Deliberately pick the SECOND agent so a mutant that always sends
    // agents[0].id, or a hardcoded id, fails this assertion.
    fireEvent.change(screen.getByRole('combobox'), { target: { value: 'agent-bbb' } });

    fireEvent.click(screen.getByRole('button', { name: /Create Sandbox/i }));

    await waitFor(() => expect(mockApi.createSandbox).toHaveBeenCalledTimes(1));
    expect(mockApi.createSandbox).toHaveBeenCalledWith({ agent_id: 'agent-bbb' });
    await waitFor(() => expect(onCreated).toHaveBeenCalledTimes(1));
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('does not call createSandbox when no agent is selected', async () => {
    renderModal();
    await waitFor(() => expect(screen.getByText('Agent A')).toBeInTheDocument());

    fireEvent.click(screen.getByRole('button', { name: /Create Sandbox/i }));

    expect(mockApi.createSandbox).not.toHaveBeenCalled();
  });
});
