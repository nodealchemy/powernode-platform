import type { ReactNode } from 'react';
import { render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import StorageProviderAssignmentsPage from './StorageProviderAssignmentsPage';

// =============================================================================
// Mocks
// =============================================================================

const mockDispatch = jest.fn();
jest.mock('react-redux', () => ({ useDispatch: () => mockDispatch }));

jest.mock('@/shared/services/slices/uiSlice', () => ({
  addNotification: (payload: unknown) => ({ type: 'ui/addNotification', payload }),
}));

let mockPermissions: string[] = [];
jest.mock('@/shared/hooks/useAuth', () => ({
  useAuth: () => ({ currentUser: { permissions: mockPermissions } }),
}));

const mockGetProvider = jest.fn();
jest.mock('@/features/admin/storage/services/storageApi', () => ({
  storageApi: {
    getProvider: (...args: unknown[]) => mockGetProvider(...args),
  },
}));

// PageContainer pulls BreadcrumbProvider context; stub it to title + children.
jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({ title, children }: { title?: string; children?: ReactNode }) => (
    <div data-testid="page-container">
      <h1>{title}</h1>
      {children}
    </div>
  ),
}));

jest.mock('@/features/system/storage/components/StorageProviderAssignmentsTab', () => ({
  StorageProviderAssignmentsTab: ({ storageId }: { storageId: string }) => (
    <div data-testid="assignments-tab">assignments-for-{storageId}</div>
  ),
}));

// =============================================================================
// Helpers
// =============================================================================

const renderPage = () =>
  render(
    <MemoryRouter initialEntries={['/admin/storage/fs-1/assignments']}>
      <Routes>
        <Route path="/admin/storage/:storageId/assignments" element={<StorageProviderAssignmentsPage />} />
      </Routes>
    </MemoryRouter>
  );

beforeEach(() => {
  jest.clearAllMocks();
  mockPermissions = [];
});

// =============================================================================
// Tests
// =============================================================================

describe('StorageProviderAssignmentsPage', () => {
  // BLESSED CROSS-BOUNDARY SEAM (IMP-ca6b51d65114): this core admin page
  // fronts system-extension endpoints. The seam degrades gracefully in a
  // core-only assembly because system.storage.assignments.read is registered
  // by the EXTENSION engine — without the extension no user can hold it, so
  // the page fails closed instead of 404ing against absent endpoints. This
  // spec is the regression guard for that fail-closed behavior.
  it('fails closed without the extension-registered read permission', async () => {
    renderPage();

    expect(
      await screen.findByText(/don't have permission to view storage assignments/i)
    ).toBeInTheDocument();
    expect(mockGetProvider).not.toHaveBeenCalled();
    expect(screen.queryByTestId('assignments-tab')).not.toBeInTheDocument();
  });

  it('loads the provider and renders the assignments tab with permission', async () => {
    mockPermissions = ['system.storage.assignments.read'];
    mockGetProvider.mockResolvedValue({
      id: 'fs-1',
      name: 'primary-nfs',
      provider_type: 'nfs',
    });

    renderPage();

    await waitFor(() => expect(mockGetProvider).toHaveBeenCalledWith('fs-1'));
    expect(await screen.findByText('primary-nfs — Assignments')).toBeInTheDocument();
    expect(screen.getByTestId('assignments-tab')).toHaveTextContent('assignments-for-fs-1');
  });

  it('shows the not-found state when the provider fetch fails', async () => {
    mockPermissions = ['system.storage.assignments.read'];
    mockGetProvider.mockRejectedValue(new Error('boom'));

    renderPage();

    expect(await screen.findByText(/Storage not found/i)).toBeInTheDocument();
    expect(mockDispatch).toHaveBeenCalled();
  });
});
