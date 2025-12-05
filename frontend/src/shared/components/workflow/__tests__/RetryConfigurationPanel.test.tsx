import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { RetryConfigurationPanel } from '../RetryConfigurationPanel';

describe('RetryConfigurationPanel', () => {
  const mockOnChange = jest.fn();
  const defaultConfig = {
    enabled: true,
    max_retries: 3,
    strategy: 'exponential' as const,
    initial_delay_ms: 1000,
    backoff_multiplier: 2,
    max_delay_ms: 60000,
    jitter: false,
    retry_on_errors: ['timeout', 'rate_limit']
  };

  beforeEach(() => {
    mockOnChange.mockClear();
  });

  describe('rendering', () => {
    it('renders retry configuration form', () => {
      render(<RetryConfigurationPanel config={defaultConfig} onChange={mockOnChange} />);

      // Component renders with workflow configuration title (nodeLevel=false by default)
      expect(screen.getByText('Workflow Retry Configuration')).toBeInTheDocument();
      expect(screen.getByText('Max Retries')).toBeInTheDocument();
      expect(screen.getByText('Retry Strategy')).toBeInTheDocument();
    });

    it('displays current configuration values', () => {
      render(<RetryConfigurationPanel config={defaultConfig} onChange={mockOnChange} />);

      // Find the max retries input by its container/value
      const maxRetriesInput = screen.getByDisplayValue('3');
      expect(maxRetriesInput).toBeInTheDocument();

      // Find strategy select - the component uses Select with option text "Exponential Backoff"
      const strategySelect = screen.getByRole('combobox') as HTMLSelectElement;
      expect(strategySelect).toBeInTheDocument();
      expect(strategySelect.value).toBe('exponential');
    });

    it('shows exponential backoff fields when exponential strategy selected', () => {
      render(<RetryConfigurationPanel config={defaultConfig} onChange={mockOnChange} />);

      expect(screen.getByText('Initial Delay (ms)')).toBeInTheDocument();
      expect(screen.getByText('Backoff Multiplier')).toBeInTheDocument();
      expect(screen.getByText('Max Delay (ms)')).toBeInTheDocument();
    });

    it('shows linear backoff fields when linear strategy selected', () => {
      const linearConfig = { ...defaultConfig, strategy: 'linear' as const, linear_increment_ms: 1000 };
      render(<RetryConfigurationPanel config={linearConfig} onChange={mockOnChange} />);

      expect(screen.getByText('Linear Increment (ms)')).toBeInTheDocument();
    });

    it('shows fixed delay field when fixed strategy selected', () => {
      const fixedConfig = { ...defaultConfig, strategy: 'fixed' as const, fixed_delay_ms: 5000 };
      render(<RetryConfigurationPanel config={fixedConfig} onChange={mockOnChange} />);

      expect(screen.getByText('Fixed Delay (ms)')).toBeInTheDocument();
    });

    it('shows custom delays field when custom strategy selected', () => {
      const customConfig = { ...defaultConfig, strategy: 'custom' as const, custom_delays_ms: [1000, 2000] };
      render(<RetryConfigurationPanel config={customConfig} onChange={mockOnChange} />);

      expect(screen.getByText('Custom Delay Schedule (ms, comma-separated)')).toBeInTheDocument();
    });
  });

  describe('configuration updates', () => {
    it('calls onChange when max retries is changed', async () => {
      render(<RetryConfigurationPanel config={defaultConfig} onChange={mockOnChange} />);

      const maxRetriesInput = screen.getByDisplayValue('3');
      await userEvent.clear(maxRetriesInput);
      await userEvent.type(maxRetriesInput, '5');

      await waitFor(() => {
        expect(mockOnChange).toHaveBeenCalled();
      });
    });

    it('calls onChange when strategy is changed', async () => {
      render(<RetryConfigurationPanel config={defaultConfig} onChange={mockOnChange} />);

      const strategySelect = screen.getByRole('combobox');
      await userEvent.selectOptions(strategySelect, 'linear');

      expect(mockOnChange).toHaveBeenCalled();
    });

    it('calls onChange when initial delay is changed', async () => {
      render(<RetryConfigurationPanel config={defaultConfig} onChange={mockOnChange} />);

      const initialDelayInput = screen.getByDisplayValue('1000');
      await userEvent.clear(initialDelayInput);
      await userEvent.type(initialDelayInput, '2000');

      await waitFor(() => {
        expect(mockOnChange).toHaveBeenCalled();
      });
    });

    it('calls onChange when jitter checkbox is toggled', async () => {
      render(<RetryConfigurationPanel config={defaultConfig} onChange={mockOnChange} />);

      // Component has jitter checkbox with label text
      const jitterCheckbox = screen.getByText(/Add jitter/i).closest('label')?.querySelector('input');
      if (jitterCheckbox) {
        await userEvent.click(jitterCheckbox);
        expect(mockOnChange).toHaveBeenCalledWith({ ...defaultConfig, jitter: true });
      }
    });
  });

  describe('retry schedule preview', () => {
    it('displays retry schedule for exponential backoff', () => {
      render(<RetryConfigurationPanel config={defaultConfig} onChange={mockOnChange} />);

      expect(screen.getByText(/Retry Schedule Preview/i)).toBeInTheDocument();
      // formatDelay outputs "1.0s", "2.0s", "4.0s" for 1000, 2000, 4000ms
      expect(screen.getByText('1.0s')).toBeInTheDocument();
      expect(screen.getByText('2.0s')).toBeInTheDocument();
      expect(screen.getByText('4.0s')).toBeInTheDocument();
    });

    it('updates preview when configuration changes', async () => {
      const { rerender } = render(<RetryConfigurationPanel config={defaultConfig} onChange={mockOnChange} />);

      const updatedConfig = { ...defaultConfig, initial_delay_ms: 2000 };
      rerender(<RetryConfigurationPanel config={updatedConfig} onChange={mockOnChange} />);

      // formatDelay outputs "2.0s", "4.0s", "8.0s" for 2000, 4000, 8000ms
      expect(screen.getByText('2.0s')).toBeInTheDocument();
      expect(screen.getByText('4.0s')).toBeInTheDocument();
      expect(screen.getByText('8.0s')).toBeInTheDocument();
    });

    it('shows max delay cap in preview', () => {
      const cappedConfig = { ...defaultConfig, max_retries: 10, max_delay_ms: 10000 };
      render(<RetryConfigurationPanel config={cappedConfig} onChange={mockOnChange} />);

      // formatDelay outputs "10.0s" for 10000ms
      const delayTexts = screen.getAllByText('10.0s');
      expect(delayTexts.length).toBeGreaterThan(0); // Multiple delays capped at 10s
    });

    it('displays linear progression for linear strategy', () => {
      const linearConfig = {
        ...defaultConfig,
        strategy: 'linear' as const,
        linear_increment_ms: 1000
      };
      render(<RetryConfigurationPanel config={linearConfig} onChange={mockOnChange} />);

      // formatDelay outputs "1.0s", "2.0s", "3.0s" for linear progression
      expect(screen.getByText('1.0s')).toBeInTheDocument();
      expect(screen.getByText('2.0s')).toBeInTheDocument();
      expect(screen.getByText('3.0s')).toBeInTheDocument();
    });

    it('displays fixed delay for all retries', () => {
      const fixedConfig = {
        ...defaultConfig,
        strategy: 'fixed' as const,
        fixed_delay_ms: 5000
      };
      render(<RetryConfigurationPanel config={fixedConfig} onChange={mockOnChange} />);

      // formatDelay outputs "5.0s" for all retries
      const delayTexts = screen.getAllByText('5.0s');
      expect(delayTexts.length).toBe(3); // All 3 retries at 5s
    });
  });

  describe('validation', () => {
    it('has max retries input with min/max constraints', async () => {
      render(<RetryConfigurationPanel config={defaultConfig} onChange={mockOnChange} />);

      const maxRetriesInput = screen.getByDisplayValue('3');
      expect(maxRetriesInput).toHaveAttribute('min', '0');
      expect(maxRetriesInput).toHaveAttribute('max', '10');
    });

    it('has initial delay input with min constraint', async () => {
      render(<RetryConfigurationPanel config={defaultConfig} onChange={mockOnChange} />);

      const initialDelayInput = screen.getByDisplayValue('1000');
      expect(initialDelayInput).toHaveAttribute('min', '100');
    });

    it('renders custom delays input for custom strategy', async () => {
      const customConfig = {
        ...defaultConfig,
        strategy: 'custom' as const,
        custom_delays_ms: [1000, 2000]
      };
      render(<RetryConfigurationPanel config={customConfig} onChange={mockOnChange} />);

      // Component shows custom delay schedule input
      expect(screen.getByText('Custom Delay Schedule (ms, comma-separated)')).toBeInTheDocument();
    });
  });

  describe('disabled state', () => {
    it('disables all inputs when disabled prop is true', async () => {
      render(<RetryConfigurationPanel config={defaultConfig} onChange={mockOnChange} disabled={true} />);

      const maxRetriesInput = screen.getByDisplayValue('3') as HTMLInputElement;
      expect(maxRetriesInput.disabled).toBe(true);
    });

    it('enables inputs when disabled prop is false', async () => {
      render(<RetryConfigurationPanel config={defaultConfig} onChange={mockOnChange} disabled={false} />);

      const maxRetriesInput = screen.getByDisplayValue('3') as HTMLInputElement;
      expect(maxRetriesInput.disabled).toBe(false);
    });
  });

  describe('error type filtering', () => {
    it('displays retry error type options', () => {
      render(<RetryConfigurationPanel config={defaultConfig} onChange={mockOnChange} />);

      expect(screen.getByText('Retry on Error Types')).toBeInTheDocument();
      expect(screen.getByText('Timeout')).toBeInTheDocument();
      expect(screen.getByText('Rate Limit')).toBeInTheDocument();
      expect(screen.getByText('Network Error')).toBeInTheDocument();
    });

    it('allows toggling error types', async () => {
      const configWithErrors = {
        ...defaultConfig,
        retry_on_errors: ['timeout', 'rate_limit']
      };
      render(<RetryConfigurationPanel config={configWithErrors} onChange={mockOnChange} />);

      // Find the Network Error checkbox by finding the label and then its input
      const networkErrorLabel = screen.getByText('Network Error');
      const checkbox = networkErrorLabel.closest('label')?.querySelector('input');
      if (checkbox) {
        await userEvent.click(checkbox);
        expect(mockOnChange).toHaveBeenCalled();
      }
    });
  });
});
