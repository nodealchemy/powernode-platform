import React from 'react';
import { render, screen, waitFor } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import { RunnersPage } from '../components/RunnersPage';
import { gitProvidersApi } from '@/features/git-providers/services/gitProvidersApi';
import type { GitRunner, RunnerStats, PaginationInfo } from '@/features/git-providers/types';

// Mock dependencies
jest.mock('@/features/git-providers/services/gitProvidersApi');
jest.mock('@/shared/hooks/useAuth', () => ({
  useAuth: () => ({
    currentUser: {
      id: 'user-1',
      permissions: ['git.runners.read', 'git.runners.manage', 'git.runners.delete'],
    },
    isAuthenticated: true,
  }),
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    showNotification: jest.fn(),
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

jest.mock('@/shared/components/ui/Input', () => ({
  Input: (props: Record<string, unknown>) => <input {...props} />,
}));

jest.mock('@/shared/components/ui/LoadingSpinner', () => ({
  LoadingSpinner: () => <div data-testid="loading-spinner">Loading...</div>,
}));

// Mock lucide-react icons
jest.mock('lucide-react', () => ({
  Server: () => <span data-testid="icon-server" />,
  Search: () => <span data-testid="icon-search" />,
  RefreshCw: () => <span data-testid="icon-refresh" />,
  Play: () => <span data-testid="icon-play" />,
  Trash2: () => <span data-testid="icon-trash" />,
  Activity: () => <span data-testid="icon-activity" />,
  Cpu: () => <span data-testid="icon-cpu" />,
  ChevronLeft: () => <span data-testid="icon-chevron-left" />,
  ChevronRight: () => <span data-testid="icon-chevron-right" />,
}));

const mockStore = configureStore({
  reducer: {
    ui: (state = { notifications: [] }) => state,
  },
});

const mockRunners: GitRunner[] = [
  {
    id: 'runner-1',
    external_id: 'ext-1',
    name: 'Runner 1',
    status: 'online',
    busy: false,
    runner_scope: 'repository',
    labels: ['self-hosted', 'linux'],
    os: 'linux',
    architecture: 'x64',
    version: '2.300.0',
    success_rate: 95.5,
    total_jobs_run: 100,
    last_seen_at: new Date().toISOString(),
    provider_type: 'github',
    credential_id: 'cred-1',
  },
];

const mockStats: RunnerStats = {
  total: 1,
  online: 1,
  offline: 0,
  busy: 0,
};

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
        <RunnersPage />
      </BrowserRouter>
    </Provider>
  );
};

describe('RunnersPage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (gitProvidersApi.getRunners as jest.Mock).mockResolvedValue({
      runners: mockRunners,
      stats: mockStats,
      pagination: mockPagination,
    });
  });

  it('renders the page', async () => {
    renderComponent();

    await waitFor(() => {
      expect(screen.getByText(/runners/i)).toBeInTheDocument();
    });
  });

  it('displays runner when data is loaded', async () => {
    renderComponent();

    await waitFor(() => {
      expect(screen.getByText('Runner 1')).toBeInTheDocument();
    });
  });

  it('shows runner status', async () => {
    renderComponent();

    await waitFor(() => {
      expect(screen.getByText(/online/i)).toBeInTheDocument();
    });
  });

  it('handles empty state', async () => {
    (gitProvidersApi.getRunners as jest.Mock).mockResolvedValue({
      runners: [],
      stats: { total: 0, online: 0, offline: 0, busy: 0 },
      pagination: { ...mockPagination, total_count: 0 },
    });

    renderComponent();

    await waitFor(() => {
      expect(screen.getByText(/no runners/i)).toBeInTheDocument();
    });
  });
});
