import type { AxiosResponse } from 'axios';

// Create properly typed AxiosResponse for tests
export function createMockAxiosResponse<T = any>(data: T, status = 200): AxiosResponse<T> {
  return {
    data,
    status,
    statusText: status === 200 ? 'OK' : 'Error',
    headers: {},
    config: {
      headers: {} as any,
    },
  };
}

