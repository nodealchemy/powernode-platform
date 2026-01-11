import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { WebhookForm } from './WebhookForm';

// Mock useForm hook
const mockReset = jest.fn();
const mockSetValue = jest.fn();
const mockHandleBlur = jest.fn();
const mockHandleSubmit = jest.fn((e: any) => {
  e?.preventDefault?.();
  return Promise.resolve();
});

jest.mock('@/shared/hooks/useForm', () => ({
  useForm: () => ({
    values: {
      url: '',
      description: '',
      status: 'active',
      event_types: [],
      content_type: 'application/json',
      timeout_seconds: 30,
      retry_limit: 3,
      retry_backoff: 'exponential'
    },
    errors: {},
    touched: {},
    isSubmitting: false,
    isValid: true,
    handleChange: jest.fn(),
    handleBlur: mockHandleBlur,
    handleSubmit: mockHandleSubmit,
    setValue: mockSetValue,
    setValues: jest.fn(),
    reset: mockReset,
    validateField: jest.fn(),
    validateForm: jest.fn(),
    getFieldProps: (name: string) => ({
      name,
      value: name === 'status' ? 'active' : name === 'content_type' ? 'application/json' : '',
      onChange: jest.fn(),
      onBlur: mockHandleBlur
    })
  }),
  FormValidationRules: {}
}));

// Mock webhooksApi
const mockGetAvailableEvents = jest.fn();

jest.mock('@/features/devops/webhooks/services/webhooksApi', () => ({
  webhooksApi: {
    getAvailableEvents: (...args: any[]) => mockGetAvailableEvents(...args),
    getDefaultFormData: () => ({
      url: '',
      description: '',
      status: 'active',
      event_types: [],
      content_type: 'application/json',
      timeout_seconds: 30,
      retry_limit: 3,
      retry_backoff: 'exponential'
    }),
    formatEventType: (type: string) => type.replace('.', ' - ')
  }
}));

// Mock LoadingSpinner
jest.mock('@/shared/components/ui/LoadingSpinner', () => ({
  LoadingSpinner: ({ size }: any) => <div data-testid="loading-spinner" data-size={size}>Loading...</div>
}));

// Mock ErrorAlert
jest.mock('@/shared/components/ui/ErrorAlert', () => ({
  __esModule: true,
  default: ({ message, onClose }: any) => (
    <div data-testid="error-alert">
      {message}
      <button onClick={onClose}>Close</button>
    </div>
  )
}));

describe('WebhookForm', () => {
  const defaultProps = {
    onSubmit: jest.fn(),
    onCancel: jest.fn()
  };

  const mockEventCategories = {
    'Subscriptions': ['subscription.created', 'subscription.updated', 'subscription.cancelled'],
    'Payments': ['payment.succeeded', 'payment.failed'],
    'Users': ['user.created', 'user.deleted']
  };

  const mockEvents = [
    'subscription.created', 'subscription.updated', 'subscription.cancelled',
    'payment.succeeded', 'payment.failed',
    'user.created', 'user.deleted'
  ];

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetAvailableEvents.mockResolvedValue({
      success: true,
      data: {
        events: mockEvents,
        categories: mockEventCategories
      }
    });
  });

  describe('loading state', () => {
    it('shows loading spinner while loading events', () => {
      mockGetAvailableEvents.mockImplementation(() => new Promise(() => {}));

      render(<WebhookForm {...defaultProps} />);

      expect(screen.getByTestId('loading-spinner')).toBeInTheDocument();
    });
  });

  describe('form rendering', () => {
    it('renders form after loading events', async () => {
      render(<WebhookForm {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Basic Configuration')).toBeInTheDocument();
      });
    });

    it('renders URL field', async () => {
      render(<WebhookForm {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Webhook URL')).toBeInTheDocument();
      });
    });

    it('renders description field', async () => {
      render(<WebhookForm {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Description')).toBeInTheDocument();
      });
      expect(screen.getByPlaceholderText('Describe the purpose of this webhook...')).toBeInTheDocument();
    });

    it('renders status field', async () => {
      render(<WebhookForm {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByLabelText('Status')).toBeInTheDocument();
      });
      expect(screen.getByText('Active')).toBeInTheDocument();
      expect(screen.getByText('Inactive')).toBeInTheDocument();
    });

    it('renders event types section', async () => {
      render(<WebhookForm {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Event Types *')).toBeInTheDocument();
      });
    });

    it('renders advanced settings', async () => {
      render(<WebhookForm {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Advanced Settings')).toBeInTheDocument();
      });
      expect(screen.getByText('Content Type')).toBeInTheDocument();
      expect(screen.getByText('Timeout (seconds)')).toBeInTheDocument();
      expect(screen.getByText('Retry Limit')).toBeInTheDocument();
      expect(screen.getByText('Retry Strategy')).toBeInTheDocument();
    });

    it('renders security info box', async () => {
      render(<WebhookForm {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Security Considerations:')).toBeInTheDocument();
      });
    });

    it('renders cancel and submit buttons', async () => {
      render(<WebhookForm {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Cancel')).toBeInTheDocument();
      });
      expect(screen.getByText('Create Webhook')).toBeInTheDocument();
    });
  });

  describe('event categories', () => {
    it('displays event categories', async () => {
      render(<WebhookForm {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Subscriptions')).toBeInTheDocument();
      });
      expect(screen.getByText('Payments')).toBeInTheDocument();
      expect(screen.getByText('Users')).toBeInTheDocument();
    });

    it('displays event count per category', async () => {
      render(<WebhookForm {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('0/3 selected')).toBeInTheDocument();
      });
      // Payments and Users both have 2 events, so there are multiple "0/2 selected" elements
      const twoEventCounts = screen.getAllByText('0/2 selected');
      expect(twoEventCounts.length).toBe(2);
    });

    it('displays event checkboxes', async () => {
      render(<WebhookForm {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('subscription - created')).toBeInTheDocument();
      });
      expect(screen.getByText('payment - succeeded')).toBeInTheDocument();
    });

    it('calls setValue when event checkbox clicked', async () => {
      render(<WebhookForm {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('subscription - created')).toBeInTheDocument();
      });

      const checkbox = screen.getByLabelText('subscription - created');
      fireEvent.click(checkbox);

      expect(mockSetValue).toHaveBeenCalledWith('event_types', ['subscription.created']);
    });
  });

  describe('form actions', () => {
    it('calls onCancel when cancel button clicked', async () => {
      const onCancel = jest.fn();
      render(<WebhookForm {...defaultProps} onCancel={onCancel} />);

      await waitFor(() => {
        expect(screen.getByText('Cancel')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Cancel'));

      expect(onCancel).toHaveBeenCalled();
    });

    it('calls handleSubmit on form submit', async () => {
      const { container } = render(<WebhookForm {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Create Webhook')).toBeInTheDocument();
      });

      const form = container.querySelector('form');
      fireEvent.submit(form!);

      expect(mockHandleSubmit).toHaveBeenCalled();
    });
  });

  describe('edit mode', () => {
    const existingWebhook = {
      id: 'webhook-1',
      url: 'https://example.com/webhook',
      description: 'My webhook',
      status: 'active' as const,
      event_types: ['subscription.created'],
      content_type: 'application/json',
      timeout_seconds: 30,
      retry_limit: 3,
      created_at: '2025-01-01T00:00:00Z',
      updated_at: '2025-01-01T00:00:00Z',
      success_count: 0,
      failure_count: 0
    };

    it('shows Update Webhook button when editing', async () => {
      render(<WebhookForm {...defaultProps} webhook={existingWebhook} />);

      await waitFor(() => {
        expect(screen.getByText('Update Webhook')).toBeInTheDocument();
      });
    });
  });

  describe('error handling', () => {
    it('shows error alert when events fail to load', async () => {
      mockGetAvailableEvents.mockResolvedValue({
        success: false,
        error: 'Failed to load events'
      });

      render(<WebhookForm {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByTestId('error-alert')).toBeInTheDocument();
      });
      expect(screen.getByText('Failed to load events')).toBeInTheDocument();
    });

    it('shows error alert on API exception', async () => {
      mockGetAvailableEvents.mockRejectedValue(new Error('Network error'));

      render(<WebhookForm {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByTestId('error-alert')).toBeInTheDocument();
      });
      expect(screen.getByText('Failed to load available events')).toBeInTheDocument();
    });
  });

  describe('content type options', () => {
    it('displays content type options', async () => {
      render(<WebhookForm {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('application/json')).toBeInTheDocument();
      });
      expect(screen.getByText('application/x-www-form-urlencoded')).toBeInTheDocument();
    });
  });

  describe('retry strategy options', () => {
    it('displays retry strategy options', async () => {
      render(<WebhookForm {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Exponential Backoff')).toBeInTheDocument();
      });
      expect(screen.getByText('Linear Backoff')).toBeInTheDocument();
    });
  });
});
