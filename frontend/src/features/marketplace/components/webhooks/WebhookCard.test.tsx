import { render, screen, fireEvent } from '@testing-library/react';
import { WebhookCard } from './WebhookCard';
import { AppWebhook } from '../../types';

describe('WebhookCard', () => {
  const mockWebhook: AppWebhook = {
    id: 'webhook-1',
    name: 'Order Notifications',
    slug: 'order-notifications',
    url: 'https://api.example.com/webhooks',
    event_type: 'order.created',
    http_method: 'POST',
    is_active: true,
    timeout_seconds: 30,
    max_retries: 3,
    secret_token: 'secret_token_12345678',
    description: 'Sends notifications when orders are created',
    headers: {},
    payload_template: {},
    authentication: {},
    retry_config: {},
    content_type: 'application/json',
    metadata: {},
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
  };

  const mockWebhookWithAnalytics: AppWebhook = {
    ...mockWebhook,
    analytics: {
      total_deliveries: 150,
      deliveries_last_24h: 10,
      success_rate: 98.5,
      failure_rate: 1.5,
      average_response_time: 245,
      pending_deliveries: 2,
      failed_deliveries: 3
    }
  };

  describe('rendering', () => {
    it('renders webhook name', () => {
      render(<WebhookCard webhook={mockWebhook} />);

      expect(screen.getByText('Order Notifications')).toBeInTheDocument();
    });

    it('renders webhook URL', () => {
      render(<WebhookCard webhook={mockWebhook} />);

      expect(screen.getByText('https://api.example.com/webhooks')).toBeInTheDocument();
    });

    it('renders event type', () => {
      render(<WebhookCard webhook={mockWebhook} />);

      expect(screen.getByText('order.created')).toBeInTheDocument();
    });

    it('renders HTTP method badge', () => {
      render(<WebhookCard webhook={mockWebhook} />);

      expect(screen.getByText('POST')).toBeInTheDocument();
    });

    it('renders active status badge when active', () => {
      render(<WebhookCard webhook={mockWebhook} />);

      expect(screen.getByText('Active')).toBeInTheDocument();
    });

    it('renders inactive status badge when inactive', () => {
      render(<WebhookCard webhook={{ ...mockWebhook, is_active: false }} />);

      expect(screen.getByText('Inactive')).toBeInTheDocument();
    });

    it('renders description when provided', () => {
      render(<WebhookCard webhook={mockWebhook} />);

      expect(screen.getByText('Sends notifications when orders are created')).toBeInTheDocument();
    });

    it('renders timeout info', () => {
      render(<WebhookCard webhook={mockWebhook} />);

      expect(screen.getByText('30s timeout')).toBeInTheDocument();
    });

    it('renders retry info', () => {
      render(<WebhookCard webhook={mockWebhook} />);

      expect(screen.getByText(/3 retries/)).toBeInTheDocument();
    });

    it('renders truncated secret token', () => {
      render(<WebhookCard webhook={mockWebhook} />);

      expect(screen.getByText(/secret_t/)).toBeInTheDocument();
    });
  });

  describe('analytics', () => {
    it('renders analytics section when available', () => {
      render(<WebhookCard webhook={mockWebhookWithAnalytics} />);

      expect(screen.getByText('Success Rate')).toBeInTheDocument();
      expect(screen.getByText('Avg Response')).toBeInTheDocument();
      expect(screen.getByText('Pending')).toBeInTheDocument();
      expect(screen.getByText('Failed')).toBeInTheDocument();
    });

    it('displays success rate', () => {
      render(<WebhookCard webhook={mockWebhookWithAnalytics} />);

      expect(screen.getByText('98.5%')).toBeInTheDocument();
    });

    it('displays average response time', () => {
      render(<WebhookCard webhook={mockWebhookWithAnalytics} />);

      expect(screen.getByText('245ms')).toBeInTheDocument();
    });

    it('displays pending deliveries', () => {
      render(<WebhookCard webhook={mockWebhookWithAnalytics} />);

      expect(screen.getByText('2')).toBeInTheDocument();
    });

    it('displays failed deliveries', () => {
      render(<WebhookCard webhook={mockWebhookWithAnalytics} />);

      expect(screen.getByText('3')).toBeInTheDocument();
    });

    it('displays total deliveries count', () => {
      render(<WebhookCard webhook={mockWebhookWithAnalytics} />);

      expect(screen.getByText(/150 deliveries/)).toBeInTheDocument();
    });
  });

  describe('action buttons', () => {
    it('renders edit button when onEdit provided', () => {
      const onEdit = jest.fn();
      render(<WebhookCard webhook={mockWebhook} onEdit={onEdit} />);

      expect(screen.getByTitle('Edit Webhook')).toBeInTheDocument();
    });

    it('calls onEdit when edit button clicked', () => {
      const onEdit = jest.fn();
      render(<WebhookCard webhook={mockWebhook} onEdit={onEdit} />);

      fireEvent.click(screen.getByTitle('Edit Webhook'));

      expect(onEdit).toHaveBeenCalledWith(mockWebhook);
    });

    it('renders toggle status button when onToggleStatus provided', () => {
      const onToggleStatus = jest.fn();
      render(<WebhookCard webhook={mockWebhook} onToggleStatus={onToggleStatus} />);

      expect(screen.getByTitle('Deactivate')).toBeInTheDocument();
    });

    it('shows Activate title for inactive webhooks', () => {
      const onToggleStatus = jest.fn();
      render(<WebhookCard webhook={{ ...mockWebhook, is_active: false }} onToggleStatus={onToggleStatus} />);

      expect(screen.getByTitle('Activate')).toBeInTheDocument();
    });

    it('calls onToggleStatus when toggle button clicked', () => {
      const onToggleStatus = jest.fn();
      render(<WebhookCard webhook={mockWebhook} onToggleStatus={onToggleStatus} />);

      fireEvent.click(screen.getByTitle('Deactivate'));

      expect(onToggleStatus).toHaveBeenCalledWith(mockWebhook);
    });

    it('renders test button when onTest provided', () => {
      const onTest = jest.fn();
      render(<WebhookCard webhook={mockWebhook} onTest={onTest} />);

      expect(screen.getByTitle('Test Webhook')).toBeInTheDocument();
    });

    it('calls onTest when test button clicked', () => {
      const onTest = jest.fn();
      render(<WebhookCard webhook={mockWebhook} onTest={onTest} />);

      fireEvent.click(screen.getByTitle('Test Webhook'));

      expect(onTest).toHaveBeenCalledWith(mockWebhook);
    });

    it('renders analytics button when onViewAnalytics provided and analytics exist', () => {
      const onViewAnalytics = jest.fn();
      render(<WebhookCard webhook={mockWebhookWithAnalytics} onViewAnalytics={onViewAnalytics} />);

      expect(screen.getByTitle('View Analytics')).toBeInTheDocument();
    });

    it('does not render analytics button without analytics data', () => {
      const onViewAnalytics = jest.fn();
      render(<WebhookCard webhook={mockWebhook} onViewAnalytics={onViewAnalytics} />);

      expect(screen.queryByTitle('View Analytics')).not.toBeInTheDocument();
    });

    it('renders deliveries button when onViewDeliveries provided', () => {
      const onViewDeliveries = jest.fn();
      render(<WebhookCard webhook={mockWebhook} onViewDeliveries={onViewDeliveries} />);

      expect(screen.getByTitle('View Deliveries')).toBeInTheDocument();
    });

    it('renders regenerate secret button when onRegenerateSecret provided', () => {
      const onRegenerateSecret = jest.fn();
      render(<WebhookCard webhook={mockWebhook} onRegenerateSecret={onRegenerateSecret} />);

      expect(screen.getByTitle('Regenerate Secret')).toBeInTheDocument();
    });

    it('calls onRegenerateSecret when regenerate button clicked', () => {
      const onRegenerateSecret = jest.fn();
      render(<WebhookCard webhook={mockWebhook} onRegenerateSecret={onRegenerateSecret} />);

      fireEvent.click(screen.getByTitle('Regenerate Secret'));

      expect(onRegenerateSecret).toHaveBeenCalledWith(mockWebhook);
    });
  });

  describe('without optional callbacks', () => {
    it('does not render buttons when callbacks not provided', () => {
      render(<WebhookCard webhook={mockWebhook} />);

      expect(screen.queryByTitle('Edit Webhook')).not.toBeInTheDocument();
      expect(screen.queryByTitle('Deactivate')).not.toBeInTheDocument();
      expect(screen.queryByTitle('Test Webhook')).not.toBeInTheDocument();
    });
  });
});
