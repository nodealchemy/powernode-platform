import { configureStore } from '@reduxjs/toolkit';
import configReducer, { fetchPlatformConfig } from './configSlice';
import { api } from '@/shared/services/api';

jest.mock('@/shared/services/api', () => ({
  api: { get: jest.fn() },
}));

const mockedGet = api.get as jest.Mock;

const buildStore = () => configureStore({ reducer: { config: configReducer } });

describe('configSlice', () => {
  it('starts with registration disabled', () => {
    expect(buildStore().getState().config.registrationEnabled).toBe(false);
  });

  it('fetches GET /config and maps features.registration_enabled', async () => {
    mockedGet.mockResolvedValue({
      data: { success: true, data: { features: { registration_enabled: true } } },
    });
    const store = buildStore();

    await store.dispatch(fetchPlatformConfig());

    expect(mockedGet).toHaveBeenCalledWith('/config');
    expect(store.getState().config.registrationEnabled).toBe(true);
  });

  it('keeps registration disabled when the server reports it off', async () => {
    mockedGet.mockResolvedValue({
      data: { success: true, data: { features: { registration_enabled: false } } },
    });
    const store = buildStore();

    await store.dispatch(fetchPlatformConfig());

    expect(store.getState().config.registrationEnabled).toBe(false);
  });

  it('keeps registration disabled when the request fails', async () => {
    mockedGet.mockRejectedValue(new Error('network'));
    const store = buildStore();

    await store.dispatch(fetchPlatformConfig());

    expect(store.getState().config.registrationEnabled).toBe(false);
  });
});
