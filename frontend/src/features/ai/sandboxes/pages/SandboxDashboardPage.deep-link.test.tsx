import { render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { ContainerSandboxContent } from './SandboxDashboardPage';

// Uses the REAL TabContainer/TabPanel (unlike SandboxDashboardPage.test.tsx,
// which mocks them) so a deep link into a sub-tab is proven end to end
// through the actual URL-parsing logic, not a test double that always
// renders every panel.

jest.mock('@/shared/services/ai', () => ({
  containerExecutionApi: { getSandboxStats: jest.fn().mockResolvedValue({ total: 0, running: 0, paused: 0, completed: 0, failed: 0 }) },
}));

jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({ hasPermission: () => true }),
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: jest.fn() }),
}));

jest.mock('@/features/devops/containers/components/ContainerList', () => ({
  ContainerList: () => <div data-testid="container-list">Container List</div>,
}));

jest.mock('@/features/devops/containers/components/TemplateList', () => ({
  TemplateList: () => <div data-testid="template-list">Template List</div>,
}));

jest.mock('@/features/devops/containers/components/QuotaDisplay', () => ({
  QuotaDisplay: () => <div data-testid="quota-display">Quota Display</div>,
}));

jest.mock('@/features/devops/containers/components/TemplateFormModal', () => ({
  TemplateFormModal: () => null,
}));

jest.mock('@/features/devops/containers/components/ExecuteContainerModal', () => ({
  ExecuteContainerModal: () => null,
}));

jest.mock('@/features/ai/sandboxes/components/CreateSandboxModal', () => ({
  CreateSandboxModal: () => null,
}));

const renderAt = (path: string) =>
  render(
    <MemoryRouter initialEntries={[path]}>
      <ContainerSandboxContent />
    </MemoryRouter>
  );

describe('ContainerSandboxContent sub-tab deep links (real TabContainer)', () => {
  it('lands on Executions by default', async () => {
    renderAt('/app/ai/execution/containers');
    await waitFor(() => expect(screen.getByTestId('container-list')).toBeInTheDocument());

    expect(screen.queryByTestId('template-list')).not.toBeInTheDocument();
    expect(screen.queryByTestId('quota-display')).not.toBeInTheDocument();
  });

  it('deep-links directly to the Templates sub-tab', async () => {
    renderAt('/app/ai/execution/containers/templates');
    await waitFor(() => expect(screen.getByTestId('template-list')).toBeInTheDocument());

    expect(screen.queryByTestId('container-list')).not.toBeInTheDocument();
  });

  it('deep-links directly to the Quotas sub-tab', async () => {
    renderAt('/app/ai/execution/containers/quotas');
    await waitFor(() => expect(screen.getByTestId('quota-display')).toBeInTheDocument());

    expect(screen.queryByTestId('container-list')).not.toBeInTheDocument();
  });
});
