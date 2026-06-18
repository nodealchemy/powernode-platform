import { screen } from '@testing-library/react';
import { render } from '@/test-utils';
import GovernancePage from './GovernancePage';

// Mock react-query with PLAIN functions (not jest.fn) so jest.config resetMocks:true can't
// strip the return value — the page renders the stat grid from this data synchronously.
jest.mock('@tanstack/react-query', () => ({
  useQuery: () => ({
    data: {
      policies: [],
      violations: [],
      approvalChains: [],
      pendingApprovals: [],
      summary: {
        policies: { total: 12, active: 8 },
        violations: { open: 2, total: 10 },
        approvals: { pending: 3, approved: 20 },
      },
      reports: [],
      collusionIndicators: [],
      coordSummary: null,
      signals: [],
      pressureFields: [],
      teamEvents: [],
    },
    isLoading: false,
    refetch: () => {},
  }),
  useMutation: () => ({ mutate: () => {}, isPending: false }),
  useQueryClient: () => ({ invalidateQueries: () => {} }),
}));

jest.mock('@/shared/hooks/usePageWebSocket', () => ({ usePageWebSocket: () => {} }));
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: () => {} }),
}));

// Stub the heavy tab-panel children so the assertion is isolated to the stat grid.
jest.mock('@/features/ai/security/pages/SecurityDashboardPage', () => ({ SecurityContent: () => null }));
jest.mock('@/features/ai/audit/components/AuditLogList', () => ({ AuditLogList: () => null }));

describe('GovernancePage summary cards — semantic theme tokens (IMP-a8a05e69efc8)', () => {
  it('renders the "Total Policies" stat icon chip with a semantic status token, not the interactive-primary affordance token', () => {
    render(<GovernancePage />);

    // The three sibling cards use semantic status tokens (Active Violations=error,
    // Pending Approvals=warning, Security Score=success); this neutral count card must
    // not be the interactive-primary odd-one-out (the "solid action-blue").
    const label = screen.getByText('Total Policies');
    const row = label.closest('div.flex');
    expect(row).toBeTruthy();

    const iconChip = row!.querySelector('div.rounded-lg');
    expect(iconChip).toBeTruthy();

    expect(iconChip!.className).not.toMatch(/theme-interactive-primary/);
    expect(iconChip!.className).toMatch(/bg-theme-info/);
  });
});
