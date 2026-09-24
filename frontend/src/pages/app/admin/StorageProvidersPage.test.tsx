import type { ReactNode } from 'react';
import { render, screen } from '@testing-library/react';

jest.mock('react-redux', () => ({ useDispatch: () => jest.fn() }));
jest.mock('@/shared/hooks/useAuth', () => ({
  useAuth: () => ({ currentUser: { permissions: ['admin.storage.read'] } }),
}));
jest.mock('@/shared/hooks/usePageWebSocket', () => ({ usePageWebSocket: jest.fn() }));
const mockGetProviders = jest.fn();
jest.mock('@/features/admin/storage/services/storageApi', () => ({
  storageApi: { getProviders: () => mockGetProviders() },
}));
// Renders the breadcrumbs the page hands its container, so their hrefs can be read.
jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({
    breadcrumbs,
    children,
  }: {
    breadcrumbs?: Array<{ label: string; href?: string }>;
    children?: ReactNode;
  }) => (
    <div>
      {breadcrumbs?.map((b) => (
        <span key={b.label} data-testid={`crumb-${b.label}`} data-href={b.href ?? ''} />
      ))}
      {children}
    </div>
  ),
}));

import StorageProvidersPage from './StorageProvidersPage';

describe('StorageProvidersPage breadcrumbs', () => {
  beforeEach(() => mockGetProviders.mockResolvedValue([]));

  it('points every crumb at an app route that exists (the page lives at /app/admin/storage)', async () => {
    render(<StorageProvidersPage />);

    expect(await screen.findByTestId('crumb-Dashboard')).toHaveAttribute('data-href', '/app');
    expect(screen.getByTestId('crumb-Admin')).toHaveAttribute('data-href', '/app/admin/settings');
    expect(screen.getByTestId('crumb-File Storage')).toHaveAttribute('data-href', '');
    expect(screen.queryByTestId('crumb-System')).toBeNull();
  });
});
