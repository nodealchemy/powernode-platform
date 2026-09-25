import { apiClient } from '@/shared/services/apiClient';

// The unauthenticated liveness probe behind the public status page. The
// authenticated component-status plane is platformStatusApi.
export const publicHealthApi = {
  /** Resolves when GET /health answers 2xx; rejects otherwise. */
  async check(): Promise<void> {
    await apiClient.get('/health');
  },
};
