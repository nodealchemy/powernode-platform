import { screen, fireEvent, waitFor } from '@testing-library/react';
import { AdminSettingsTabs } from './AdminSettingsTabs';
import { renderWithProviders, mockUsers, mockAuthenticatedState } from '@/shared/utils/test-utils';

// Mock navigation hooks
const mockNavigate = jest.fn();
const mockLocation = { pathname: '/app/admin/settings' };

jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate,
  useLocation: () => mockLocation,
}));

describe('AdminSettingsTabs', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('renders settings tabs', async () => {
    renderWithProviders(
      <AdminSettingsTabs />,
      { 
        preloadedState: { 
          ...mockAuthenticatedState,
          auth: {
            ...mockAuthenticatedState.auth,
            user: {
              ...mockUsers.adminUser,
              permissions: [...mockUsers.adminUser.permissions, 'admin.settings.email', 'admin.settings.security', 'admin.billing.manage_gateways']
            }
          }
        }
      }
    );

    await waitFor(() => {
      expect(screen.getAllByText('Overview')).toHaveLength(2); // Desktop and mobile
      expect(screen.getAllByText('Email Settings')).toHaveLength(2); // Desktop and mobile
      expect(screen.getAllByText('Security')).toHaveLength(2); // Desktop and mobile
      // Payment Gateways is enterpriseOnly — not rendered without enterprise enabled
    });
  });

  it('highlights active tab based on current location', async () => {
    renderWithProviders(
      <AdminSettingsTabs />,
      { 
        preloadedState: { 
          ...mockAuthenticatedState,
          auth: {
            ...mockAuthenticatedState.auth,
            user: {
              ...mockUsers.adminUser,
              permissions: [...mockUsers.adminUser.permissions, 'admin.settings.email', 'admin.settings.security']
            }
          }
        }
      }
    );

    await waitFor(() => {
      const overviewTabs = screen.getAllByText('Overview');
      const desktopOverviewTab = overviewTabs.find(tab => tab.closest('button'));
      expect(desktopOverviewTab?.closest('button')).toHaveAttribute('aria-current', 'page');
    });
  });

  it('navigates to selected tab on click', async () => {
    renderWithProviders(
      <AdminSettingsTabs />,
      { 
        preloadedState: { 
          ...mockAuthenticatedState,
          auth: {
            ...mockAuthenticatedState.auth,
            user: {
              ...mockUsers.adminUser,
              permissions: [...mockUsers.adminUser.permissions, 'admin.settings.email']
            }
          }
        }
      }
    );

    await waitFor(() => {
      const emailTabs = screen.getAllByText('Email Settings');
      const desktopEmailTab = emailTabs.find(tab => tab.closest('button'));
      if (desktopEmailTab) {
        fireEvent.click(desktopEmailTab);
      }
    });

    expect(mockNavigate).toHaveBeenCalledWith('/app/admin/settings/email');
  });

  it('filters tabs based on user permissions', async () => {
    renderWithProviders(
      <AdminSettingsTabs />,
      { 
        preloadedState: { 
          ...mockAuthenticatedState,
          auth: {
            ...mockAuthenticatedState.auth,
            user: {
              ...mockUsers.regularUser,
              permissions: ['admin.settings.read'] // Limited permissions
            }
          }
        }
      }
    );

    await waitFor(() => {
      // Should see Overview (no specific permissions required) and Performance (basic permission)
      expect(screen.getAllByText('Overview')).toHaveLength(2); // Desktop and mobile
      expect(screen.getAllByText('Performance')).toHaveLength(2); // Desktop and mobile
      
      // Should NOT see permission-restricted tabs
      expect(screen.queryByText('Email Settings')).not.toBeInTheDocument();
      expect(screen.queryByText('Security')).not.toBeInTheDocument();
      expect(screen.queryByText('Payment Gateways')).not.toBeInTheDocument();
    });
  });

  it('shows mobile dropdown on small screens', async () => {
    renderWithProviders(
      <AdminSettingsTabs />,
      { 
        preloadedState: { 
          ...mockAuthenticatedState,
          auth: {
            ...mockAuthenticatedState.auth,
            user: {
              ...mockUsers.adminUser,
              permissions: [...mockUsers.adminUser.permissions, 'admin.settings.email']
            }
          }
        }
      }
    );

    await waitFor(() => {
      const mobileSelect = screen.getByLabelText('Select an admin settings tab');
      expect(mobileSelect).toBeInTheDocument();
      expect(mobileSelect).toHaveValue('overview');
    });
  });

  it('handles mobile dropdown navigation', async () => {
    renderWithProviders(
      <AdminSettingsTabs />,
      { 
        preloadedState: { 
          ...mockAuthenticatedState,
          auth: {
            ...mockAuthenticatedState.auth,
            user: {
              ...mockUsers.adminUser,
              permissions: [...mockUsers.adminUser.permissions, 'admin.settings.email']
            }
          }
        }
      }
    );

    await waitFor(() => {
      const mobileSelect = screen.getByLabelText('Select an admin settings tab');
      fireEvent.change(mobileSelect, { target: { value: 'email' } });
    });

    expect(mockNavigate).toHaveBeenCalledWith('/app/admin/settings/email');
  });

  it('displays tab descriptions correctly', async () => {
    renderWithProviders(
      <AdminSettingsTabs />,
      { 
        preloadedState: { 
          ...mockAuthenticatedState,
          auth: {
            ...mockAuthenticatedState.auth,
            user: {
              ...mockUsers.adminUser,
              permissions: [...mockUsers.adminUser.permissions, 'admin.settings.email']
            }
          }
        }
      }
    );

    await waitFor(() => {
      expect(screen.getByText('System overview and quick admin actions')).toBeInTheDocument();
    });
  });

  it('handles tabs with no required permissions', async () => {
    renderWithProviders(
      <AdminSettingsTabs />,
      { 
        preloadedState: { 
          ...mockAuthenticatedState,
          auth: {
            ...mockAuthenticatedState.auth,
            user: {
              ...mockUsers.regularUser,
              permissions: [] // No permissions at all
            }
          }
        }
      }
    );

    await waitFor(() => {
      // Should still see Overview tab as it has no specific permission requirements
      expect(screen.getAllByText('Overview')).toHaveLength(2); // Desktop and mobile
    });
  });

  it('shows correct active tab for different routes', async () => {
    // Temporarily modify the mock location for this test
    const originalPathname = mockLocation.pathname;
    mockLocation.pathname = '/app/admin/settings/email';

    renderWithProviders(
      <AdminSettingsTabs />,
      { 
        preloadedState: { 
          ...mockAuthenticatedState,
          auth: {
            ...mockAuthenticatedState.auth,
            user: {
              ...mockUsers.adminUser,
              permissions: [...mockUsers.adminUser.permissions, 'admin.settings.email']
            }
          }
        }
      }
    );

    await waitFor(() => {
      // Find the desktop Email Settings button specifically 
      const buttons = screen.getAllByRole('button');
      const emailButton = buttons.find(button => button.textContent?.includes('Email Settings'));
      expect(emailButton).toHaveAttribute('aria-current', 'page');
    });
    
    // Reset the mock back to original value for other tests
    mockLocation.pathname = originalPathname;
  });
});