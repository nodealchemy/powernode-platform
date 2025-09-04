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

// Legacy wrapper for backward compatibility
export function createMockApiResponse<T>(data: T, success = true) {
  return createMockAxiosResponse(data, success ? 200 : 400);
}