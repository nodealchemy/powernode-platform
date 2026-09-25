import { render, screen, waitFor } from '@testing-library/react';
import { ContainerLogsModal } from './ContainerLogsModal';
import type { ContainerInstanceSummary } from '@/shared/services/ai';

jest.mock('@/shared/services/ai', () => ({
  containerExecutionApi: { getContainerLogs: jest.fn() },
}));

import { containerExecutionApi } from '@/shared/services/ai';
const mockApi = containerExecutionApi as jest.Mocked<typeof containerExecutionApi>;

const container: ContainerInstanceSummary = {
  id: 'exec-1',
  execution_id: 'exec-1',
  status: 'running',
  image_name: 'powernode/ai-agent:latest',
  sandbox: true,
};

describe('ContainerLogsModal', () => {
  it('fetches and displays logs for the given container', async () => {
    (mockApi.getContainerLogs as jest.Mock).mockResolvedValue({
      execution_id: 'exec-1',
      logs: 'line one\nline two',
      status: 'running',
    });

    render(<ContainerLogsModal container={container} onClose={jest.fn()} />);

    await waitFor(() => expect(screen.getByText(/line one/)).toBeInTheDocument());
    expect(mockApi.getContainerLogs).toHaveBeenCalledWith('exec-1');
  });

  it('shows an error message when the fetch fails', async () => {
    (mockApi.getContainerLogs as jest.Mock).mockRejectedValue(new Error('boom'));

    render(<ContainerLogsModal container={container} onClose={jest.fn()} />);

    await waitFor(() => expect(screen.getByText('boom')).toBeInTheDocument());
  });

  it('renders nothing open when container is null', () => {
    render(<ContainerLogsModal container={null} onClose={jest.fn()} />);
    expect(screen.queryByText(/Logs/)).not.toBeInTheDocument();
  });
});
