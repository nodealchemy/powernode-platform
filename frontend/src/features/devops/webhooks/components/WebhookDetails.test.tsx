import { screen } from '@testing-library/react';
import { render } from '@/test-utils';
import { WebhookDetails } from './WebhookDetails';
import { webhooksApi } from '@/features/devops/webhooks/services/webhooksApi';
import type { WebhookEndpoint } from '@/features/devops/webhooks/services/webhooksApi';

// NOTE: jest.config has resetMocks:true, which wipes any implementation set inside a
// jest.mock factory before each test. So the factory only declares jest.fn() shells and
// the implementations are configured at the start of the test below.
jest.mock('@/features/devops/webhooks/services/webhooksApi', () => ({
  webhooksApi: {
    getWebhook: jest.fn(),
    getDeliveryHistory: jest.fn(),
    getSuccessRate: jest.fn(),
    getStatusColor: jest.fn(),
    getDeliveryStatusColor: jest.fn(),
    formatEventType: jest.fn(),
  },
}));

jest.mock('@/shared/hooks/useNotifications', () => {
  const addNotification = jest.fn();
  return { useNotifications: () => ({ addNotification }) };
});

const webhook = {
  id: 'wh1',
  url: 'https://example.com/hook',
  status: 'active',
  description: '',
  created_at: '2026-01-01T00:00:00Z',
  content_type: 'application/json',
  timeout_seconds: 30,
  retry_limit: 3,
  event_types: ['order.created'],
  success_count: 480,
  failure_count: 20,
} as unknown as WebhookEndpoint;

describe('WebhookDetails stats cards — semantic theme tokens (IMP-be10354a89eb)', () => {
  beforeEach(() => {
    (webhooksApi.getWebhook as jest.Mock).mockResolvedValue({
      success: true,
      data: {
        retry_backoff: 'exponential',
        secret_token: 'secret-token-value',
        delivery_stats: {
          total_deliveries: 500,
          average_response_time: 245,
          last_success_at: null,
          last_failure_at: null,
        },
      },
    });
    (webhooksApi.getDeliveryHistory as jest.Mock).mockResolvedValue({
      success: true,
      data: [],
      pagination: { current_page: 1, per_page: 20, total_pages: 0, total_count: 0 },
    });
    (webhooksApi.getSuccessRate as jest.Mock).mockReturnValue(96);
    (webhooksApi.getStatusColor as jest.Mock).mockReturnValue('text-theme-success');
    (webhooksApi.getDeliveryStatusColor as jest.Mock).mockReturnValue('text-theme-success');
    (webhooksApi.formatEventType as jest.Mock).mockImplementation((eventType: string) => eventType);
  });

  it('renders the "Total Deliveries" stat icon chip with a semantic status token, not the interactive-primary affordance token', async () => {
    render(<WebhookDetails webhook={webhook} />);

    // Siblings use semantic status tokens (Successful=success, Failed=error); this
    // neutral-total chip must not be the interactive-primary odd-one-out.
    const label = await screen.findByText('Total Deliveries');
    const row = label.closest('div.flex');
    expect(row).toBeTruthy();

    const iconChip = row!.querySelector('div.rounded-lg');
    expect(iconChip).toBeTruthy();

    expect(iconChip!.className).not.toMatch(/theme-interactive-primary/);
    expect(iconChip!.className).toMatch(/bg-theme-info/);
  });
});
