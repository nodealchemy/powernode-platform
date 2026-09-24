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
      summary: {
        policies: { total: 12, active: 8 },
        violations: { open: 2, total: 10 },
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

    // The two sibling cards use semantic status tokens (Active Violations=error,
    // Security Score=success; fc-11 dropped the Approvals tile with the tab it
    // summarized); this neutral count card must not be the interactive-primary
    // odd-one-out (the "solid action-blue").
    const label = screen.getByText('Total Policies');
    const row = label.closest('div.flex');
    expect(row).toBeTruthy();

    const iconChip = row!.querySelector('div.rounded-lg');
    expect(iconChip).toBeTruthy();

    expect(iconChip!.className).not.toMatch(/theme-interactive-primary/);
    expect(iconChip!.className).toMatch(/bg-theme-info/);
  });
});

describe('GovernancePage — Approvals tab removed (fc-11)', () => {
  it('has no Approvals tab, no Pending Approvals tile, and defaults to Policies', () => {
    render(<GovernancePage />);

    expect(screen.queryByRole('tab', { name: /approvals/i })).not.toBeInTheDocument();
    expect(screen.queryByText('Pending Approvals')).not.toBeInTheDocument();
    // Policies stays the default (and only remaining) selected tab, unaffected
    // by the removal.
    expect(screen.getByRole('tab', { name: 'Policies' })).toHaveAttribute('aria-selected', 'true');
  });
});
