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

const mockHasPermission = jest.fn((_perm: string) => true);
jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({ hasPermission: (perm: string) => mockHasPermission(perm) }),
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
  agent_name: 'My Test Agent',
  memory_used_mb: 128,
  cpu_used_millicores: 250,
};

const pausedSandbox: ContainerInstanceSummary = {
  id: 'sandbox-2',
  execution_id: 'sandbox-2',
  status: 'paused',
  image_name: 'powernode/ai-agent:latest',
  sandbox: true,
};

const completedSandbox: ContainerInstanceSummary = {
  id: 'sandbox-3',
  execution_id: 'sandbox-3',
  status: 'completed',
  image_name: 'powernode/ai-agent:latest',
  sandbox: true,
};

describe('ContainerList sandbox filter and actions', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockHasPermission.mockReturnValue(true);
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

  it('shows the agent name and resource usage on a sandbox row', async () => {
    render(<ContainerList />);
    await waitFor(() => expect(screen.getByText('My Test Agent')).toBeInTheDocument());

    expect(screen.getByText('Mem: 128MB')).toBeInTheDocument();
    expect(screen.getByText('CPU: 250m')).toBeInTheDocument();
  });

  it('never shows Destroy on a terminal sandbox row (completed/failed/cancelled)', async () => {
    (mockApi.getContainers as jest.Mock).mockResolvedValue({
      items: [completedSandbox],
      pagination: { total_count: 1 },
    });

    render(<ContainerList />);
    await waitFor(() => expect(screen.getByText(/powernode\/ai-agent/)).toBeInTheDocument());

    expect(screen.queryByText('Destroy')).not.toBeInTheDocument();
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

  describe('destroy confirmation (paused sandbox — no row-level Cancel button to disambiguate from)', () => {
    beforeEach(() => {
      (mockApi.getContainers as jest.Mock).mockResolvedValue({
        items: [pausedSandbox],
        pagination: { total_count: 1 },
      });
    });

    it('asks for confirmation before destroying, and does not call the API on cancel', async () => {
      render(<ContainerList />);
      await waitFor(() => expect(screen.getByText('Destroy')).toBeInTheDocument());

      fireEvent.click(screen.getByText('Destroy'));

      expect(screen.getByText(/Destroy sandbox sandbox-2/)).toBeInTheDocument();
      expect(mockApi.destroySandbox).not.toHaveBeenCalled();

      fireEvent.click(screen.getByText('Cancel'));
      expect(mockApi.destroySandbox).not.toHaveBeenCalled();
    });

    it('destroys a sandbox via the sandbox-scoped endpoint after confirming', async () => {
      render(<ContainerList />);
      await waitFor(() => expect(screen.getByText('Destroy')).toBeInTheDocument());

      fireEvent.click(screen.getByText('Destroy'));
      fireEvent.click(screen.getByRole('button', { name: 'Destroy Sandbox' }));

      await waitFor(() => expect(mockApi.destroySandbox).toHaveBeenCalledWith('sandbox-2'));
    });
  });

  describe('permission gates (permissions only, never roles)', () => {
    it('hides Pause/Resume without ai.agents.execute', async () => {
      mockHasPermission.mockImplementation((perm: string) => perm !== 'ai.agents.execute');

      render(<ContainerList />);
      await waitFor(() => expect(screen.getAllByText(/powernode\/ai-agent/)).toHaveLength(3));

      expect(screen.queryByText('Pause')).not.toBeInTheDocument();
      expect(screen.queryByText('Resume')).not.toBeInTheDocument();
    });

    it('hides Destroy without ai.agents.delete', async () => {
      mockHasPermission.mockImplementation((perm: string) => perm !== 'ai.agents.delete');

      render(<ContainerList />);
      await waitFor(() => expect(screen.getAllByText(/powernode\/ai-agent/)).toHaveLength(3));

      expect(screen.queryByText('Destroy')).not.toBeInTheDocument();
    });

    it('hides Cancel without devops.containers.cancel', async () => {
      mockHasPermission.mockImplementation((perm: string) => perm !== 'devops.containers.cancel');

      render(<ContainerList />);
      await waitFor(() => expect(screen.getAllByText(/powernode\/ai-agent/)).toHaveLength(3));

      expect(screen.queryByText('Cancel')).not.toBeInTheDocument();
    });
  });
});
