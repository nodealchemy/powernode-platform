import { screen } from '@testing-library/react';
import { configureStore } from '@reduxjs/toolkit';
import { LoginPage } from './LoginPage';
import authReducer from '@/shared/services/slices/authSlice';
import uiReducer from '@/shared/services/slices/uiSlice';
import configReducer, { fetchPlatformConfig } from '@/shared/services/slices/configSlice';
import { api } from '@/shared/services/api';
import { renderWithProviders } from '@/shared/utils/test-utils';

jest.mock('@/shared/services/api', () => ({
  api: { get: jest.fn(), post: jest.fn() },
}));

jest.mock('@/shared/services/settings/settingsApi', () => ({
  settingsApi: {
    getCopyright: jest.fn().mockResolvedValue('Test Copyright'),
    formatCopyright: jest.fn().mockReturnValue('© 2025 Test Company'),
  },
}));

const buildStore = () =>
  configureStore({ reducer: { auth: authReducer, ui: uiReducer, config: configReducer } });

describe('LoginPage sign-up block driven by GET /config', () => {
  it('shows the sign-up block once the server reports registration enabled', async () => {
    (api.get as jest.Mock).mockResolvedValue({
      data: { success: true, data: { features: { registration_enabled: true } } },
    });
    const store = buildStore();
    await store.dispatch(fetchPlatformConfig());

    renderWithProviders(<LoginPage />, { store });

    expect(screen.getByText('Create your account')).toBeInTheDocument();
  });

  it('hides the sign-up block when the server reports registration disabled', async () => {
    (api.get as jest.Mock).mockResolvedValue({
      data: { success: true, data: { features: { registration_enabled: false } } },
    });
    const store = buildStore();
    await store.dispatch(fetchPlatformConfig());

    renderWithProviders(<LoginPage />, { store });

    expect(screen.queryByText('Create your account')).not.toBeInTheDocument();
  });
});
