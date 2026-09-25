import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { ContainerList } from './ContainerList';
import type { ContainerInstanceSummary } from '@/shared/services/ai';

jest.mock('@/shared/services/ai', () => ({
  containerExecutionApi: {
    getContainers: jest.fn(),
    cancelContainer: jest.fn(),
    pauseSandbox: jest.fn(),
    resumeSandbox: jest.fn(),
    destroySandbox: jest.fn(),
  },
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: jest.fn() }),
}));

import { containerExecutionApi } from '@/shared/services/ai';
const mockApi = containerExecutionApi as jest.Mocked<typeof containerExecutionApi>;

const templateExecution: ContainerInstanceSummary = {
  id: 'exec-1',
  execution_id: 'exec-1',
  status: 'running',
  image_name: 'powernode/ai-agent:latest',
  sandbox: false,
};

const agentSandbox: ContainerInstanceSummary = {
  id: 'sandbox-1',
  execution_id: 'sandbox-1',
  status: 'running',
  image_name: 'powernode/ai-agent:latest',
  sandbox: true,
};

const pausedSandbox: ContainerInstanceSummary = {
  id: 'sandbox-2',
  execution_id: 'sandbox-2',
  status: 'paused',
  image_name: 'powernode/ai-agent:latest',
  sandbox: true,
};

describe('ContainerList sandbox filter and actions', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (mockApi.getContainers as jest.Mock).mockResolvedValue({
      items: [templateExecution, agentSandbox, pausedSandbox],
      pagination: { total_count: 3 },
    });
  });

  it('loads with no sandbox filter by default', async () => {
    render(<ContainerList />);
    await waitFor(() => expect(mockApi.getContainers).toHaveBeenCalled());

    const filters = (mockApi.getContainers as jest.Mock).mock.calls[0][0];
    expect(filters.sandbox).toBeUndefined();
  });

  it('filters to agent sandboxes only when "Agent Sandboxes" is selected', async () => {
    render(<ContainerList />);
    await waitFor(() => expect(mockApi.getContainers).toHaveBeenCalledTimes(1));

    fireEvent.change(screen.getByLabelText('Filter by source'), { target: { value: 'true' } });

    await waitFor(() => expect(mockApi.getContainers).toHaveBeenCalledTimes(2));
    const filters = (mockApi.getContainers as jest.Mock).mock.calls[1][0];
    expect(filters.sandbox).toBe(true);
  });

  it('filters to template executions only when "Template Executions" is selected', async () => {
    render(<ContainerList />);
    await waitFor(() => expect(mockApi.getContainers).toHaveBeenCalledTimes(1));

    fireEvent.change(screen.getByLabelText('Filter by source'), { target: { value: 'false' } });

    await waitFor(() => expect(mockApi.getContainers).toHaveBeenCalledTimes(2));
    const filters = (mockApi.getContainers as jest.Mock).mock.calls[1][0];
    expect(filters.sandbox).toBe(false);
  });

  it('only shows Pause/Resume/Destroy on sandbox rows, never on plain executions', async () => {
    render(<ContainerList />);
    await waitFor(() => expect(screen.getAllByText(/powernode\/ai-agent/)).toHaveLength(3));

    // agent-sandbox (running): Pause + Destroy, no Resume
    expect(screen.getAllByText('Pause')).toHaveLength(1);
    // paused sandbox: Resume + Destroy, no Pause for that row (only 1 Pause total, above)
    expect(screen.getAllByText('Resume')).toHaveLength(1);
    // Destroy appears for both sandbox rows, never for the plain template execution
    expect(screen.getAllByText('Destroy')).toHaveLength(2);
  });

  it('pauses a running sandbox via the sandbox-scoped endpoint', async () => {
    render(<ContainerList />);
    await waitFor(() => expect(screen.getAllByText('Pause')).toHaveLength(1));

    fireEvent.click(screen.getByText('Pause'));

    await waitFor(() => expect(mockApi.pauseSandbox).toHaveBeenCalledWith('sandbox-1'));
  });

  it('resumes a paused sandbox via the sandbox-scoped endpoint', async () => {
    render(<ContainerList />);
    await waitFor(() => expect(screen.getAllByText('Resume')).toHaveLength(1));

    fireEvent.click(screen.getByText('Resume'));

    await waitFor(() => expect(mockApi.resumeSandbox).toHaveBeenCalledWith('sandbox-2'));
  });

  it('destroys a sandbox via the sandbox-scoped endpoint', async () => {
    render(<ContainerList />);
    await waitFor(() => expect(screen.getAllByText('Destroy')).toHaveLength(2));

    fireEvent.click(screen.getAllByText('Destroy')[0]);

    await waitFor(() => expect(mockApi.destroySandbox).toHaveBeenCalledWith('sandbox-1'));
  });
});
