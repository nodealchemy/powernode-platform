import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { TemplateList } from './TemplateList';
import { containerExecutionApi } from '@/shared/services/ai';

jest.mock('@/shared/services/ai', () => ({
  containerExecutionApi: {
    getTemplates: jest.fn(),
    triggerBuild: jest.fn(),
  },
}));

const mockAddNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: mockAddNotification }),
}));

let mockHasPermission: (permission: string) => boolean;
jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({ hasPermission: (p: string) => mockHasPermission(p) }),
}));

const TEMPLATE = {
  id: 'tpl-1',
  name: 'Analyzer',
  description: 'Analyzes code',
  image_name: 'powernode/analyzer:latest',
  visibility: 'account',
  status: 'active',
  execution_count: 3,
  gitea_repo_full_name: 'org/analyzer',
};

const renderList = (canWrite: boolean, onSelectTemplate = jest.fn()) => {
  mockHasPermission = (p: string) => (p === 'devops.container_templates.write' ? canWrite : true);
  (containerExecutionApi.getTemplates as jest.Mock).mockResolvedValue({
    items: [TEMPLATE],
    pagination: { total_count: 1 },
  });
  return { onSelectTemplate, ...render(<TemplateList onSelectTemplate={onSelectTemplate} />) };
};

describe('TemplateList write-permission gating', () => {
  beforeEach(() => jest.clearAllMocks());

  it('hides the Build button for a read-only user', async () => {
    renderList(false);
    await waitFor(() => expect(screen.getByText('Analyzer')).toBeInTheDocument());
    expect(screen.queryByText('Build')).not.toBeInTheDocument();
  });

  it('shows the Build button and surfaces its error for a user with write access', async () => {
    (containerExecutionApi.triggerBuild as jest.Mock).mockRejectedValue(new Error('Build queue full'));
    renderList(true);
    await waitFor(() => expect(screen.getByText('Build')).toBeInTheDocument());

    fireEvent.click(screen.getByText('Build'));

    await waitFor(() =>
      expect(mockAddNotification).toHaveBeenCalledWith(
        expect.objectContaining({ type: 'error', message: expect.stringContaining('Build queue full') })
      )
    );
  });

  it('does not open the editor when a read-only user clicks a template card', async () => {
    const onSelectTemplate = jest.fn();
    renderList(false, onSelectTemplate);
    await waitFor(() => expect(screen.getByText('Analyzer')).toBeInTheDocument());

    fireEvent.click(screen.getByText('Analyzer'));

    expect(onSelectTemplate).not.toHaveBeenCalled();
  });

  it('opens the editor when a user with write access clicks a template card', async () => {
    const onSelectTemplate = jest.fn();
    renderList(true, onSelectTemplate);
    await waitFor(() => expect(screen.getByText('Analyzer')).toBeInTheDocument());

    fireEvent.click(screen.getByText('Analyzer'));

    expect(onSelectTemplate).toHaveBeenCalledWith(expect.objectContaining({ id: 'tpl-1' }));
  });
});
