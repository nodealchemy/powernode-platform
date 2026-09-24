// Covers api.ts's response interceptor reaction to Admin::MaintenanceMode's
// gate (a 503 carrying { code: 'maintenance_mode' }) — the piece that drives
// MaintenanceScreen. axios itself is mocked so the registered interceptor
// function can be invoked directly with a synthetic error, rather than
// standing up a real HTTP layer.
jest.mock('axios', () => {
  const instance = {
    interceptors: {
      request: { use: jest.fn() },
      response: { use: jest.fn() },
    },
    get: jest.fn(),
    post: jest.fn(),
    put: jest.fn(),
    patch: jest.fn(),
    delete: jest.fn(),
  };
  return {
    __esModule: true,
    default: { create: jest.fn(() => instance) },
  };
});

import axios from 'axios';
// Importing the store transitively imports authSlice -> authAPI -> api.ts,
// which constructs the real APIClient singleton (and so registers its
// response interceptor against the mocked axios instance) at module-load time.
import { store } from '@/shared/services';
import { clearMaintenanceMode } from '@/shared/services/slices/uiSlice';

describe('api.ts maintenance-mode interceptor', () => {
  let onRejected: (error: unknown) => Promise<unknown>;

  beforeAll(() => {
    const mockAxiosInstance = (axios.create as jest.Mock).mock.results[0].value;
    onRejected = mockAxiosInstance.interceptors.response.use.mock.calls[0][1];
  });

  beforeEach(() => {
    store.dispatch(clearMaintenanceMode());
  });

  it('sets the maintenance flag from a 503 carrying code: maintenance_mode', async () => {
    const error = {
      config: { url: '/some/endpoint' },
      response: {
        status: 503,
        data: {
          success: false,
          error: 'Down for upgrades',
          code: 'maintenance_mode',
          details: { estimated_completion: '2026-01-01T00:00:00Z' },
        },
      },
    };

    await expect(onRejected(error)).rejects.toBe(error);

    expect(store.getState().ui.maintenance).toEqual({
      active: true,
      message: 'Down for upgrades',
      estimatedCompletion: '2026-01-01T00:00:00Z',
    });
  });

  it('does not set the maintenance flag for an unrelated 503', async () => {
    const error = {
      config: { url: '/some/endpoint' },
      response: { status: 503, data: { success: false, error: 'Service unavailable' } },
    };

    await expect(onRejected(error)).rejects.toBe(error);

    expect(store.getState().ui.maintenance?.active).toBe(false);
  });

  it('does not set the maintenance flag for a 401', async () => {
    const error = {
      config: { url: '/some/endpoint', _retry: true },
      response: { status: 401, data: { success: false, error: 'Unauthorized' } },
    };

    await expect(onRejected(error)).rejects.toBe(error);

    expect(store.getState().ui.maintenance?.active).toBe(false);
  });
});
