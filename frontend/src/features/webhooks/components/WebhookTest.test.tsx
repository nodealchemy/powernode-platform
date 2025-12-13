import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { WebhookTest } from './WebhookTest';

// Mock webhooksApi
const mockGetAvailableEvents = jest.fn();
const mockTestWebhook = jest.fn();

jest.mock('@/features/webhooks/services/webhooksApi', () => ({
  webhooksApi: {
    getAvailableEvents: (...args: any[]) => mockGetAvailableEvents(...args),
    testWebhook: (...args: any[]) => mockTestWebhook(...args),
    formatEventType: (type: string) => type.replace('.', ' - ')
  }
}));

// Mock LoadingSpinner
jest.mock('@/shared/components/ui/LoadingSpinner', () => ({
  LoadingSpinner: ({ size }: any) => <div data-testid="loading-spinner" data-size={size}>Loading...</div>
}));

// Mock CodeBlock
jest.mock('@/shared/components/ui/CodeBlock', () => ({
  __esModule: true,
  default: ({ code, language }: any) => (
    <pre data-testid="code-block" data-language={language}>{code}</pre>
  )
}));

describe('WebhookTest', () => {
  const mockWebhook = {
    id: 'webhook-1',
    url: 'https://example.com/webhook',
    description: 'Test webhook',
    status: 'active' as const,
    event_types: ['subscription.created', 'payment.succeeded'],
    content_type: 'application/json',
    timeout_seconds: 30,
    retry_limit: 3,
    created_at: '2025-01-01T00:00:00Z',
    updated_at: '2025-01-01T00:00:00Z',
    success_count: 0,
    failure_count: 0
  };

  const defaultProps = {
    webhook: mockWebhook,
    onSuccess: jest.fn(),
    onError: jest.fn()
  };

  const mockAvailableEvents = ['subscription.created', 'subscription.updated', 'payment.succeeded', 'payment.failed', 'user.created'];

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetAvailableEvents.mockResolvedValue({
      success: true,
      data: {
        events: mockAvailableEvents,
        categories: {}
      }
    });
  });

  describe('rendering', () => {
    it('renders test configuration section', () => {
      render(<WebhookTest {...defaultProps} />);

      expect(screen.getByText('Test Configuration')).toBeInTheDocument();
    });

    it('renders event type selector', () => {
      render(<WebhookTest {...defaultProps} />);

      expect(screen.getByText('Event Type')).toBeInTheDocument();
      expect(screen.getByRole('combobox')).toBeInTheDocument();
    });

    it('shows subscribed events in selector', () => {
      render(<WebhookTest {...defaultProps} />);

      expect(screen.getByText('subscription - created (subscribed)')).toBeInTheDocument();
      expect(screen.getByText('payment - succeeded (subscribed)')).toBeInTheDocument();
    });

    it('renders send test button', () => {
      render(<WebhookTest {...defaultProps} />);

      expect(screen.getByText('Send Test Event')).toBeInTheDocument();
    });

    it('renders sample payload section', () => {
      render(<WebhookTest {...defaultProps} />);

      expect(screen.getByText('Sample Payload')).toBeInTheDocument();
      expect(screen.getByTestId('code-block')).toBeInTheDocument();
    });

    it('renders testing tips section', () => {
      render(<WebhookTest {...defaultProps} />);

      expect(screen.getByText('Testing Tips')).toBeInTheDocument();
      expect(screen.getByText(/Use a webhook testing service like ngrok/)).toBeInTheDocument();
    });
  });

  describe('inactive webhook', () => {
    it('shows warning when webhook is inactive', () => {
      const inactiveWebhook = { ...mockWebhook, status: 'inactive' as const };
      render(<WebhookTest {...defaultProps} webhook={inactiveWebhook} />);

      expect(screen.getByText('Webhook must be active to test')).toBeInTheDocument();
    });

    it('disables test button when webhook is inactive', () => {
      const inactiveWebhook = { ...mockWebhook, status: 'inactive' as const };
      render(<WebhookTest {...defaultProps} webhook={inactiveWebhook} />);

      const button = screen.getByText('Send Test Event').closest('button');
      expect(button).toBeDisabled();
    });
  });

  describe('event type selection', () => {
    it('allows changing event type', async () => {
      render(<WebhookTest {...defaultProps} />);

      await waitFor(() => {
        expect(mockGetAvailableEvents).toHaveBeenCalled();
      });

      const select = screen.getByRole('combobox');
      fireEvent.change(select, { target: { value: 'payment.succeeded' } });

      expect(select).toHaveValue('payment.succeeded');
    });

    it('defaults to first subscribed event', () => {
      render(<WebhookTest {...defaultProps} />);

      const select = screen.getByRole('combobox');
      expect(select).toHaveValue('subscription.created');
    });
  });

  describe('test execution', () => {
    it('calls testWebhook API when test button clicked', async () => {
      mockTestWebhook.mockResolvedValue({
        success: true,
        data: {
          webhook_id: 'webhook-1',
          test_payload: {},
          response: {
            status: 200,
            response_time: 150,
            success: true
          }
        }
      });

      render(<WebhookTest {...defaultProps} />);

      fireEvent.click(screen.getByText('Send Test Event'));

      await waitFor(() => {
        expect(mockTestWebhook).toHaveBeenCalledWith('webhook-1', 'subscription.created');
      });
    });

    it('shows loading state while testing', async () => {
      mockTestWebhook.mockImplementation(() => new Promise(() => {}));

      render(<WebhookTest {...defaultProps} />);

      fireEvent.click(screen.getByText('Send Test Event'));

      expect(screen.getByText('Testing...')).toBeInTheDocument();
      expect(screen.getByTestId('loading-spinner')).toBeInTheDocument();
    });

    it('calls onSuccess on successful test', async () => {
      const onSuccess = jest.fn();
      mockTestWebhook.mockResolvedValue({
        success: true,
        data: {
          webhook_id: 'webhook-1',
          test_payload: {},
          response: {
            status: 200,
            response_time: 150,
            success: true
          }
        }
      });

      render(<WebhookTest {...defaultProps} onSuccess={onSuccess} />);

      fireEvent.click(screen.getByText('Send Test Event'));

      await waitFor(() => {
        expect(onSuccess).toHaveBeenCalledWith('Webhook test completed successfully with status 200');
      });
    });

    it('calls onError on failed test', async () => {
      const onError = jest.fn();
      mockTestWebhook.mockResolvedValue({
        success: false,
        error: 'Connection refused'
      });

      render(<WebhookTest {...defaultProps} onError={onError} />);

      fireEvent.click(screen.getByText('Send Test Event'));

      await waitFor(() => {
        expect(onError).toHaveBeenCalledWith('Connection refused');
      });
    });

    it('calls onError on API exception', async () => {
      const onError = jest.fn();
      mockTestWebhook.mockRejectedValue(new Error('Network error'));

      render(<WebhookTest {...defaultProps} onError={onError} />);

      fireEvent.click(screen.getByText('Send Test Event'));

      await waitFor(() => {
        expect(onError).toHaveBeenCalledWith('An unexpected error occurred during webhook test');
      });
    });
  });

  describe('test results', () => {
    const successResult = {
      success: true,
      data: {
        webhook_id: 'webhook-1',
        test_payload: { event: 'test' },
        response: {
          status: 200,
          response_time: 150,
          success: true,
          response_body: '{"ok": true}'
        }
      }
    };

    const failureResult = {
      success: true,
      data: {
        webhook_id: 'webhook-1',
        test_payload: { event: 'test' },
        response: {
          status: 500,
          response_time: 2500,
          success: false,
          response_body: 'Internal Server Error'
        }
      }
    };

    it('displays test result section after test', async () => {
      mockTestWebhook.mockResolvedValue(successResult);

      render(<WebhookTest {...defaultProps} />);
      fireEvent.click(screen.getByText('Send Test Event'));

      await waitFor(() => {
        expect(screen.getByText('Test Result')).toBeInTheDocument();
      });
    });

    it('shows success status for 2xx response', async () => {
      mockTestWebhook.mockResolvedValue(successResult);

      render(<WebhookTest {...defaultProps} />);
      fireEvent.click(screen.getByText('Send Test Event'));

      await waitFor(() => {
        expect(screen.getByText('200 Success')).toBeInTheDocument();
      });
    });

    it('shows response time', async () => {
      mockTestWebhook.mockResolvedValue(successResult);

      render(<WebhookTest {...defaultProps} />);
      fireEvent.click(screen.getByText('Send Test Event'));

      await waitFor(() => {
        expect(screen.getByText('150ms')).toBeInTheDocument();
      });
    });

    it('shows success message for successful test', async () => {
      mockTestWebhook.mockResolvedValue(successResult);

      render(<WebhookTest {...defaultProps} />);
      fireEvent.click(screen.getByText('Send Test Event'));

      await waitFor(() => {
        expect(screen.getByText('Test Successful')).toBeInTheDocument();
      });
    });

    it('shows failure message for failed test', async () => {
      mockTestWebhook.mockResolvedValue(failureResult);

      render(<WebhookTest {...defaultProps} />);
      fireEvent.click(screen.getByText('Send Test Event'));

      await waitFor(() => {
        expect(screen.getByText('Test Failed')).toBeInTheDocument();
      });
    });

    it('shows response body when present', async () => {
      mockTestWebhook.mockResolvedValue(successResult);

      render(<WebhookTest {...defaultProps} />);
      fireEvent.click(screen.getByText('Send Test Event'));

      await waitFor(() => {
        expect(screen.getByText('Response Body')).toBeInTheDocument();
      });
      expect(screen.getByText('{"ok": true}')).toBeInTheDocument();
    });

    it('shows request details', async () => {
      mockTestWebhook.mockResolvedValue(successResult);

      render(<WebhookTest {...defaultProps} />);
      fireEvent.click(screen.getByText('Send Test Event'));

      await waitFor(() => {
        expect(screen.getByText('Request Details')).toBeInTheDocument();
      });
      expect(screen.getByText('https://example.com/webhook')).toBeInTheDocument();
      expect(screen.getByText('POST')).toBeInTheDocument();
      expect(screen.getByText('application/json')).toBeInTheDocument();
    });
  });

  describe('sample payload', () => {
    it('includes webhook id in sample payload', () => {
      render(<WebhookTest {...defaultProps} />);

      const codeBlock = screen.getByTestId('code-block');
      expect(codeBlock.textContent).toContain('webhook-1');
    });

    it('includes test flag in sample payload', () => {
      render(<WebhookTest {...defaultProps} />);

      const codeBlock = screen.getByTestId('code-block');
      expect(codeBlock.textContent).toContain('"test": true');
    });
  });
});
