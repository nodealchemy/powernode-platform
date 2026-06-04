import { apiClient } from '@/shared/services/apiClient';
import type { SpendSummary } from '../SpendDashboard';

/**
 * governanceSpendApi — co-located HTTP layer for the M4 governance
 * spend pane.
 *
 * Consolidates the inline `apiClient` calls previously made by
 * `SpendDashboard`. Behavior is preserved verbatim: same `apiClient`
 * module, same endpoint, same response handling (`response.data` is
 * returned directly). The default endpoint matches the component's
 * historical default of `/governance/spend`; callers may override it.
 */
export const GOVERNANCE_SPEND_ENDPOINT = '/governance/spend';

export const governanceSpendApi = {
  /**
   * Fetch the month-to-date spend summary.
   *
   * @param endpoint - Endpoint path to fetch from. Defaults to
   *   `/governance/spend` (the component's historical default).
   * @returns The `SpendSummary` payload (the value previously derived
   *   from `response.data`).
   */
  async getSpendSummary(
    endpoint: string = GOVERNANCE_SPEND_ENDPOINT,
  ): Promise<SpendSummary> {
    const response = await apiClient.get<SpendSummary>(endpoint);
    return response.data;
  },
};

export default governanceSpendApi;
