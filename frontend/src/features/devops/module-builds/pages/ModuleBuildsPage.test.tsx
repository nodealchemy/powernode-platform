import { screen, waitFor } from '@testing-library/react';
import { render, createMockUser } from '@/test-utils';
import { ModuleBuildsPage } from './ModuleBuildsPage';
import { moduleBuildBatchesApi } from '../services/moduleBuildBatchesApi';
import type { ModuleBuildBatch } from '../types';

// NOTE: jest.config has resetMocks:true, which wipes any implementation set inside a
// jest.mock factory before each test — implementations are set per-test below.
jest.mock('../services/moduleBuildBatchesApi', () => ({
  moduleBuildBatchesApi: {
    list: jest.fn(),
    get: jest.fn(),
    cancel: jest.fn(),
  },
}));

const mockApi = moduleBuildBatchesApi as jest.Mocked<typeof moduleBuildBatchesApi>;

const batch: ModuleBuildBatch = {
  id: 'batch-1234-5678',
  status: 'complete',
  trigger: 'push',
  shadow: false,
  base_sha: 'abc1234def',
  head_sha: 'def5678abc',
  module_slugs: ['fleet-autonomy', 'sdwan-manager'],
  planned_count: 2,
  succeeded_count: 2,
  failed_count: 0,
  active: false,
  finished: true,
  package_context: null,
  created_at: '2026-08-01T00:00:00Z',
  updated_at: '2026-08-01T00:05:00Z',
};

describe('ModuleBuildsPage', () => {
  it('renders module build batches for a user with system.module_builds.read', async () => {
    mockApi.list.mockResolvedValue({
      module_build_batches: [batch],
      meta: { current_page: 1, per_page: 20, total_count: 1, total_pages: 1, next_page: null, prev_page: null },
    });

    render(<ModuleBuildsPage />, {
      preloadedState: {
        auth: { user: createMockUser({ permissions: ['system.module_builds.read'] }), isLoading: false, isAuthenticated: true },
      },
    });

    expect(await screen.findByText('fleet-autonomy')).toBeInTheDocument();
    expect(screen.getByText('sdwan-manager')).toBeInTheDocument();
    expect(screen.getByText('Complete')).toBeInTheDocument();
  });

  it('does not fetch and shows a permission message for a user without system.module_builds.read', async () => {
    render(<ModuleBuildsPage />, {
      preloadedState: {
        auth: { user: createMockUser({ permissions: [] }), isLoading: false, isAuthenticated: true },
      },
    });

    expect(await screen.findByText(/don't have permission/i)).toBeInTheDocument();
    await waitFor(() => expect(mockApi.list).not.toHaveBeenCalled());
  });
});
