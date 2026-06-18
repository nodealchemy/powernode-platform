import { screen } from '@testing-library/react';
import { render } from '@/test-utils';
import PrivacyDashboardPage from './PrivacyDashboardPage';

// loadDashboard()/loadDeletionStatus() run on mount; resolve them so loading -> false.
// NOTE: the factory is hoisted above imports, so the dashboard shape is inlined here
// (a top-level const would hit a temporal-dead-zone error).
jest.mock('@/features/privacy/services/privacyApi', () => ({
  __esModule: true,
  default: {
    getDashboard: jest.fn().mockResolvedValue({
      consents: { marketing: { granted: true } },
      export_requests: [],
      terms_status: { needs_review: false },
    }),
    getDeletionStatus: jest.fn().mockResolvedValue(null),
    updateConsents: jest.fn(),
    requestExport: jest.fn(),
    downloadExport: jest.fn(),
    requestDeletion: jest.fn(),
    cancelDeletion: jest.fn(),
  },
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ showNotification: jest.fn() }),
}));

jest.mock('@/shared/hooks/usePageWebSocket', () => ({
  usePageWebSocket: jest.fn(),
}));

// Isolate the test to the header stat grid — stub the data-heavy child cards.
jest.mock('@/features/privacy/components/ConsentManager', () => ({
  ConsentManager: () => null,
}));
jest.mock('@/features/privacy/components/DataExportCard', () => ({
  DataExportCard: () => null,
}));
jest.mock('@/features/privacy/components/DataDeletionCard', () => ({
  DataDeletionCard: () => null,
}));

describe('PrivacyDashboardPage header stats — semantic theme tokens (IMP-f2b4763a21cf)', () => {
  it('renders the "Terms Status" stat icon chip with a semantic status token, not the interactive-primary affordance token', async () => {
    render(<PrivacyDashboardPage />);

    // Siblings in the same grid use success/info; this chip must not be the odd-one-out.
    const label = await screen.findByText('Terms Status');
    const row = label.closest('div.flex');
    expect(row).toBeTruthy();

    const iconChip = row!.querySelector('div.rounded-lg');
    expect(iconChip).toBeTruthy();

    expect(iconChip!.className).not.toMatch(/theme-interactive-primary/);
    expect(iconChip!.className).toMatch(/bg-theme-info/);
  });
});
