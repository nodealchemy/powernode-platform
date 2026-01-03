import React from 'react';
import { render, screen, waitFor } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import { PipelineSchedulesPage } from '../components/PipelineSchedulesPage';
import { gitProvidersApi } from '@/features/git-providers/services/gitProvidersApi';
import type { GitPipelineSchedule, GitRepository, PaginationInfo } from '@/features/git-providers/types';

// Mock dependencies
jest.mock('@/features/git-providers/services/gitProvidersApi');

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    showNotification: jest.fn(),
  }),
}));

jest.mock('@/shared/hooks/useAuth', () => ({
  useAuth: () => ({
    currentUser: {
      id: 'user-1',
      permissions: ['git.schedules.read', 'git.schedules.manage'],
    },
    isAuthenticated: true,
    isLoading: false,
  }),
}));

// Mock shared components
jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({ children }: { children: React.ReactNode }) => <div data-testid="page-container">{children}</div>,
}));

jest.mock('@/shared/components/error/ErrorBoundary', () => ({
  PageErrorBoundary: ({ children }: { children: React.ReactNode }) => <div data-testid="error-boundary">{children}</div>,
}));

jest.mock('@/shared/components/ui/Button', () => ({
  Button: ({ children, ...props }: { children: React.ReactNode }) => <button {...props}>{children}</button>,
}));

jest.mock('@/shared/components/ui/LoadingSpinner', () => ({
  LoadingSpinner: () => <div data-testid="loading-spinner">Loading...</div>,
}));

// Mock ScheduleModal component
jest.mock('../components/ScheduleModal', () => ({
  ScheduleModal: () => null,
}));

// Mock lucide-react icons
jest.mock('lucide-react', () => ({
  Clock: () => <span data-testid="icon-clock" />,
  Calendar: () => <span data-testid="icon-calendar" />,
  Plus: () => <span data-testid="icon-plus" />,
  Play: () => <span data-testid="icon-play" />,
  Pause: () => <span data-testid="icon-pause" />,
  Trash2: () => <span data-testid="icon-trash" />,
  Edit: () => <span data-testid="icon-edit" />,
  RefreshCw: () => <span data-testid="icon-refresh" />,
  Search: () => <span data-testid="icon-search" />,
  AlertCircle: () => <span data-testid="icon-alert" />,
  Check: () => <span data-testid="icon-check" />,
  X: () => <span data-testid="icon-x" />,
  GitBranch: () => <span data-testid="icon-git-branch" />,
  ChevronDown: () => <span data-testid="icon-chevron-down" />,
  CheckCircle: () => <span data-testid="icon-check-circle" />,
  XCircle: () => <span data-testid="icon-x-circle" />,
}));

const mockStore = configureStore({
  reducer: {
    ui: (state = { notifications: [] }) => state,
    auth: (state = { user: { id: 'user-1', permissions: ['git.schedules.read'] }, isLoading: false }) => state,
  },
});

const mockSchedules: GitPipelineSchedule[] = [
  {
    id: 'schedule-1',
    name: 'Nightly Build',
    cron_expression: '0 2 * * *',
    timezone: 'UTC',
    ref: 'main',
    workflow_file: '.github/workflows/nightly.yml',
    is_active: true,
    next_run_at: new Date(Date.now() + 3600000).toISOString(),
    last_run_at: new Date(Date.now() - 86400000).toISOString(),
    last_run_status: 'success',
    run_count: 100,
    success_rate: 95.0,
    repository_id: 'repo-1',
  },
];

const mockRepositories: GitRepository[] = [
  {
    id: 'repo-1',
    name: 'test-repo',
    full_name: 'owner/test-repo',
    owner: 'owner',
    default_branch: 'main',
    is_private: false,
    is_fork: false,
    is_archived: false,
    webhook_configured: true,
    stars_count: 10,
    forks_count: 2,
    open_issues_count: 5,
    open_prs_count: 1,
    topics: [],
    created_at: new Date().toISOString(),
    provider_type: 'github',
    credential_id: 'cred-1',
  },
];

const mockPagination: PaginationInfo = {
  current_page: 1,
  per_page: 20,
  total_pages: 1,
  total_count: 1,
};

const renderComponent = () => {
  return render(
    <Provider store={mockStore}>
      <BrowserRouter>
        <PipelineSchedulesPage />
      </BrowserRouter>
    </Provider>
  );
};

describe('PipelineSchedulesPage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (gitProvidersApi.getSchedules as jest.Mock).mockResolvedValue({
      schedules: mockSchedules,
      pagination: mockPagination,
    });
    (gitProvidersApi.getRepositories as jest.Mock).mockResolvedValue({
      repositories: mockRepositories,
      pagination: mockPagination,
    });
  });

  it('renders the page', async () => {
    renderComponent();

    await waitFor(() => {
      expect(screen.getByTestId('page-container')).toBeInTheDocument();
    });
  });

  it('displays schedule when data is loaded', async () => {
    renderComponent();

    await waitFor(() => {
      expect(screen.getByText('Nightly Build')).toBeInTheDocument();
    });
  });

  it('displays cron expression', async () => {
    renderComponent();

    await waitFor(() => {
      expect(screen.getByText('0 2 * * *')).toBeInTheDocument();
    });
  });

  it('handles empty state', async () => {
    (gitProvidersApi.getSchedules as jest.Mock).mockResolvedValue({
      schedules: [],
      pagination: { ...mockPagination, total_count: 0 },
    });

    renderComponent();

    await waitFor(() => {
      expect(screen.getByText(/no schedules/i)).toBeInTheDocument();
    });
  });
});
