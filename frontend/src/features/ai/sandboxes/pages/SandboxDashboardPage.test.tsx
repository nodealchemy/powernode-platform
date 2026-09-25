import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import { ContainerSandboxContent } from './SandboxDashboardPage';

// Mock the API service
jest.mock('@/shared/services/ai', () => ({
  containerExecutionApi: {
    getSandboxStats: jest.fn(),
  },
}));

import { containerExecutionApi } from '@/shared/services/ai';
const mockApi = containerExecutionApi as jest.Mocked<typeof containerExecutionApi>;

// Mock the permissions hook — both permission families gate different actions
// on this merged surface (ai.agents.create for sandboxes, devops.containers.read
// for templates), so tests toggle this per-case rather than hardcoding true.
const mockHasPermission = jest.fn((_perm: string) => true);
jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({
    hasPermission: (perm: string) => mockHasPermission(perm),
  }),
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    addNotification: jest.fn(),
  }),
}));

// Mock TabContainer layout component - render all panels unconditionally for testing
jest.mock('@/shared/components/layout/TabContainer', () => ({
  TabContainer: ({ children, tabs, activeTab, onTabChange }: { children?: React.ReactNode; tabs?: Array<{ id: string; label: string }>; activeTab?: string; onTabChange?: (tabId: string) => void }) => (
    <div data-testid="tabs" data-value={activeTab}>
      <div data-testid="tabs-list">
        {tabs?.map((tab) => (
          <button
            key={tab.id}
            data-testid={`tab-trigger-${tab.id}`}
            onClick={() => onTabChange?.(tab.id)}
          >
            {tab.label}
          </button>
        ))}
      </div>
      {children}
    </div>
  ),
  TabPanel: ({ children, tabId, className }: { children?: React.ReactNode; tabId: string; className?: string }) => (
    <div data-testid={`tab-content-${tabId}`} className={className}>
      {children}
    </div>
  ),
}));

jest.mock('@/features/devops/containers/components/ContainerList', () => ({
  ContainerList: ({ onViewLogs }: { onViewLogs?: (c: { id: string; execution_id: string }) => void }) => (
    <div data-testid="container-list">
      Container List
      <button data-testid="view-logs-btn" onClick={() => onViewLogs?.({ id: 'exec-1', execution_id: 'exec-1' })}>
        View Logs
      </button>
    </div>
  ),
}));

jest.mock('@/features/devops/containers/components/ContainerLogsModal', () => ({
  ContainerLogsModal: ({ container }: { container: { execution_id: string } | null }) =>
    container ? <div data-testid="container-logs-modal">Logs for {container.execution_id}</div> : null,
}));

jest.mock('@/features/devops/containers/components/TemplateList', () => ({
  TemplateList: ({ onSelectTemplate, onExecuteTemplate }: { onSelectTemplate: (t: { id: string; name: string }) => void; onExecuteTemplate?: (t: { id: string; name: string }) => void }) => (
    <div data-testid="template-list">
      Template List
      <button data-testid="select-template-btn" onClick={() => onSelectTemplate({ id: 'template-1', name: 'Test Template' })}>
        Select Template
      </button>
      {onExecuteTemplate && (
        <button data-testid="execute-template-btn" onClick={() => onExecuteTemplate({ id: 'template-1', name: 'Test Template' })}>
          Execute Template
        </button>
      )}
    </div>
  ),
}));

jest.mock('@/features/devops/containers/components/QuotaDisplay', () => ({
  QuotaDisplay: () => <div data-testid="quota-display">Quota Display</div>,
}));

jest.mock('@/features/devops/containers/components/TemplateFormModal', () => ({
  TemplateFormModal: ({ isOpen, mode, templateId }: { isOpen: boolean; mode?: string; templateId?: string | null }) =>
    isOpen ? (
      <div data-testid="template-form-modal" data-mode={mode} data-template-id={templateId}>
        Template Form Modal
      </div>
    ) : null,
}));

jest.mock('@/features/devops/containers/components/ExecuteContainerModal', () => ({
  ExecuteContainerModal: ({ isOpen, template }: { isOpen: boolean; template?: { id: string; name: string } | null }) =>
    isOpen ? (
      <div data-testid="execute-container-modal" data-template-id={template?.id}>
        Execute Container Modal
      </div>
    ) : null,
}));

jest.mock('@/features/ai/sandboxes/components/CreateSandboxModal', () => ({
  CreateSandboxModal: ({ isOpen }: { isOpen: boolean }) =>
    isOpen ? <div data-testid="create-sandbox-modal">Create Sandbox Modal</div> : null,
}));

describe('ContainerSandboxContent (merged Sandboxes surface)', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockHasPermission.mockReturnValue(true);
    (mockApi.getSandboxStats as jest.Mock).mockResolvedValue({
      total: 3,
      running: 1,
      paused: 1,
      completed: 1,
      failed: 0,
    });
  });

  const renderComponent = () =>
    render(
      <BrowserRouter>
        <ContainerSandboxContent />
      </BrowserRouter>
    );

  it('renders the merged executions/templates/quotas tabs', async () => {
    renderComponent();
    await waitFor(() => expect(mockApi.getSandboxStats).toHaveBeenCalled());

    expect(screen.getByTestId('tab-trigger-executions')).toBeInTheDocument();
    expect(screen.getByTestId('tab-trigger-templates')).toBeInTheDocument();
    expect(screen.getByTestId('tab-trigger-quotas')).toBeInTheDocument();
    expect(screen.getByTestId('container-list')).toBeInTheDocument();
  });

  it('shows sandbox stats loaded from the sandbox-scoped stats endpoint', async () => {
    renderComponent();
    await waitFor(() => expect(screen.getByText('3')).toBeInTheDocument());

    expect(screen.getByText('Total')).toBeInTheDocument();
    expect(screen.getByText('Running')).toBeInTheDocument();
    expect(screen.getByText('Paused')).toBeInTheDocument();
  });

  it('shows the Create Sandbox action when the user holds ai.agents.create', async () => {
    renderComponent();
    await waitFor(() => expect(mockApi.getSandboxStats).toHaveBeenCalled());

    expect(screen.getByText('Create Sandbox')).toBeInTheDocument();
  });

  it('hides the Create Sandbox action without ai.agents.create', async () => {
    mockHasPermission.mockImplementation((perm: string) => perm !== 'ai.agents.create');
    renderComponent();
    await waitFor(() => expect(mockApi.getSandboxStats).toHaveBeenCalled());

    expect(screen.queryByText('Create Sandbox')).not.toBeInTheDocument();
  });

  it('opens the create sandbox modal on click', async () => {
    renderComponent();
    await waitFor(() => expect(mockApi.getSandboxStats).toHaveBeenCalled());

    expect(screen.queryByTestId('create-sandbox-modal')).not.toBeInTheDocument();
    fireEvent.click(screen.getByText('Create Sandbox'));
    expect(screen.getByTestId('create-sandbox-modal')).toBeInTheDocument();
  });

  it('opens the edit modal when a template is selected', async () => {
    renderComponent();
    await waitFor(() => expect(mockApi.getSandboxStats).toHaveBeenCalled());

    expect(screen.queryByTestId('template-form-modal')).not.toBeInTheDocument();
    fireEvent.click(screen.getByTestId('select-template-btn'));

    const modal = screen.getByTestId('template-form-modal');
    expect(modal).toHaveAttribute('data-mode', 'edit');
    expect(modal).toHaveAttribute('data-template-id', 'template-1');
  });

  it('opens the execute modal when a template execution is requested', async () => {
    renderComponent();
    await waitFor(() => expect(mockApi.getSandboxStats).toHaveBeenCalled());

    expect(screen.queryByTestId('execute-container-modal')).not.toBeInTheDocument();
    fireEvent.click(screen.getByTestId('execute-template-btn'));

    const modal = screen.getByTestId('execute-container-modal');
    expect(modal).toHaveAttribute('data-template-id', 'template-1');
  });

  it('wires View Logs to the logs modal', async () => {
    renderComponent();
    await waitFor(() => expect(screen.getByTestId('container-list')).toBeInTheDocument());

    expect(screen.queryByTestId('container-logs-modal')).not.toBeInTheDocument();
    fireEvent.click(screen.getByTestId('view-logs-btn'));

    expect(screen.getByTestId('container-logs-modal')).toBeInTheDocument();
    expect(screen.getByText('Logs for exec-1')).toBeInTheDocument();
  });

  describe('permission gates (permissions only, never roles)', () => {
    it('does not fetch or show sandbox stats without ai.agents.read', async () => {
      mockHasPermission.mockImplementation((perm: string) => perm !== 'ai.agents.read');
      renderComponent();
      await waitFor(() => expect(screen.getByTestId('container-list')).toBeInTheDocument());

      expect(mockApi.getSandboxStats).not.toHaveBeenCalled();
      expect(screen.queryByText('Total')).not.toBeInTheDocument();
    });

    it('labels the stats as sandbox-only when shown', async () => {
      renderComponent();
      await waitFor(() => expect(screen.getByText('Total')).toBeInTheDocument());

      expect(screen.getByText(/Agent sandboxes only/i)).toBeInTheDocument();
    });

    it('hides the Templates panel without devops.container_templates.read', async () => {
      mockHasPermission.mockImplementation((perm: string) => perm !== 'devops.container_templates.read');
      renderComponent();
      await waitFor(() => expect(mockApi.getSandboxStats).toHaveBeenCalled());

      expect(screen.queryByTestId('template-list')).not.toBeInTheDocument();
    });

    it('hides Create Template without devops.container_templates.write', async () => {
      mockHasPermission.mockImplementation((perm: string) => perm !== 'devops.container_templates.write');
      renderComponent();
      await waitFor(() => expect(mockApi.getSandboxStats).toHaveBeenCalled());

      expect(screen.queryByText('Create Template')).not.toBeInTheDocument();
    });

    it('hides the per-template Execute action without devops.containers.execute', async () => {
      mockHasPermission.mockImplementation((perm: string) => perm !== 'devops.containers.execute');
      renderComponent();
      await waitFor(() => expect(screen.getByTestId('template-list')).toBeInTheDocument());

      expect(screen.queryByTestId('execute-template-btn')).not.toBeInTheDocument();
    });
  });
});
