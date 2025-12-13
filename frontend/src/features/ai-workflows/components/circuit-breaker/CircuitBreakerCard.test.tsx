import { render, screen, fireEvent } from '@testing-library/react';
import { CircuitBreakerCard } from './CircuitBreakerCard';
import type { CircuitBreakerState } from './CircuitBreakerDashboard';

// Mock UI components
jest.mock('@/shared/components/ui/Card', () => ({
  Card: ({ children, className, onClick }: any) => (
    <div data-testid="card" className={className} onClick={onClick}>
      {children}
    </div>
  )
}));

jest.mock('@/shared/components/ui/Badge', () => ({
  Badge: ({ children, variant, size, className }: any) => (
    <span data-testid="badge" data-variant={variant} data-size={size} className={className}>
      {children}
    </span>
  )
}));

jest.mock('@/shared/components/ui/Button', () => ({
  Button: ({ children, onClick, variant, size, className }: any) => (
    <button onClick={onClick} data-variant={variant} data-size={size} className={className}>
      {children}
    </button>
  )
}));

describe('CircuitBreakerCard', () => {
  const mockBreaker: CircuitBreakerState = {
    id: 'breaker-1',
    name: 'OpenAI GPT-4',
    provider: 'openai',
    service: 'ai_provider',
    state: 'closed',
    failure_count: 2,
    success_count: 0,
    failure_threshold: 5,
    success_threshold: 3,
    failure_rate: 5.5,
    avg_response_time_ms: 450,
    total_requests: 1000,
    total_successes: 945,
    total_failures: 55,
    last_success_at: '2025-01-15T10:30:00Z',
    last_failure_at: '2025-01-15T09:00:00Z',
    timeout_duration_ms: 30000,
    configuration: {
      failure_threshold: 5,
      success_threshold: 3,
      timeout_ms: 5000,
      reset_timeout_ms: 30000
    }
  };

  const defaultProps = {
    breaker: mockBreaker
  };

  describe('header', () => {
    it('shows breaker name', () => {
      render(<CircuitBreakerCard {...defaultProps} />);

      expect(screen.getByText('OpenAI GPT-4')).toBeInTheDocument();
    });

    it('shows provider name', () => {
      render(<CircuitBreakerCard {...defaultProps} />);

      expect(screen.getByText('openai')).toBeInTheDocument();
    });

    it('shows service badge', () => {
      render(<CircuitBreakerCard {...defaultProps} />);

      expect(screen.getByText('ai provider')).toBeInTheDocument();
    });
  });

  describe('state badges', () => {
    it('shows Healthy badge for closed state', () => {
      render(<CircuitBreakerCard {...defaultProps} />);

      expect(screen.getByText('Healthy')).toBeInTheDocument();
    });

    it('shows Failed badge for open state', () => {
      const openBreaker = { ...mockBreaker, state: 'open' as const };
      render(<CircuitBreakerCard breaker={openBreaker} />);

      expect(screen.getByText('Failed')).toBeInTheDocument();
    });

    it('shows Testing badge for half_open state', () => {
      const halfOpenBreaker = { ...mockBreaker, state: 'half_open' as const };
      render(<CircuitBreakerCard breaker={halfOpenBreaker} />);

      expect(screen.getByText('Testing')).toBeInTheDocument();
    });
  });

  describe('state icons', () => {
    it('shows CheckCircle2 icon for closed state', () => {
      const { container } = render(<CircuitBreakerCard {...defaultProps} />);

      expect(container.querySelector('.lucide-circle-check')).toBeInTheDocument();
    });

    it('shows XCircle icon for open state', () => {
      const openBreaker = { ...mockBreaker, state: 'open' as const };
      const { container } = render(<CircuitBreakerCard breaker={openBreaker} />);

      expect(container.querySelector('.lucide-circle-x')).toBeInTheDocument();
    });

    it('shows Clock icon for half_open state', () => {
      const halfOpenBreaker = { ...mockBreaker, state: 'half_open' as const };
      const { container } = render(<CircuitBreakerCard breaker={halfOpenBreaker} />);

      expect(container.querySelector('.lucide-clock')).toBeInTheDocument();
    });
  });

  describe('metrics grid', () => {
    it('shows Success Rate', () => {
      render(<CircuitBreakerCard {...defaultProps} />);

      expect(screen.getByText('Success Rate')).toBeInTheDocument();
      expect(screen.getByText('94.5%')).toBeInTheDocument();
    });

    it('shows health score label', () => {
      render(<CircuitBreakerCard {...defaultProps} />);

      // 94.5% success rate = "Good" (needs >= 95% for Excellent)
      expect(screen.getByText('Good')).toBeInTheDocument();
    });

    it('shows Average Response time', () => {
      render(<CircuitBreakerCard {...defaultProps} />);

      expect(screen.getByText('Avg Response')).toBeInTheDocument();
      expect(screen.getByText('450ms')).toBeInTheDocument();
    });

    it('shows response speed label', () => {
      render(<CircuitBreakerCard {...defaultProps} />);

      // 450ms = "Fast"
      expect(screen.getByText('Fast')).toBeInTheDocument();
    });

    it('shows Total Requests', () => {
      render(<CircuitBreakerCard {...defaultProps} />);

      expect(screen.getByText('Total Requests')).toBeInTheDocument();
      expect(screen.getByText('1,000')).toBeInTheDocument();
    });

    it('shows success count', () => {
      render(<CircuitBreakerCard {...defaultProps} />);

      expect(screen.getByText('945 successes')).toBeInTheDocument();
    });

    it('shows Total Failures', () => {
      render(<CircuitBreakerCard {...defaultProps} />);

      expect(screen.getByText('Total Failures')).toBeInTheDocument();
      expect(screen.getByText('55')).toBeInTheDocument();
    });

    it('shows consecutive failure count', () => {
      render(<CircuitBreakerCard {...defaultProps} />);

      expect(screen.getByText('2 consecutive')).toBeInTheDocument();
    });
  });

  describe('health score variations', () => {
    it('shows Excellent for >=95% success rate', () => {
      const excellentBreaker = { ...mockBreaker, failure_rate: 3 }; // 97% success
      render(<CircuitBreakerCard breaker={excellentBreaker} />);

      expect(screen.getByText('Excellent')).toBeInTheDocument();
    });

    it('shows Fair for 70-85% success rate', () => {
      const fairBreaker = { ...mockBreaker, failure_rate: 22 }; // 78% success
      render(<CircuitBreakerCard breaker={fairBreaker} />);

      expect(screen.getByText('Fair')).toBeInTheDocument();
    });

    it('shows Poor for <70% success rate', () => {
      const poorBreaker = { ...mockBreaker, failure_rate: 35 }; // 65% success
      render(<CircuitBreakerCard breaker={poorBreaker} />);

      expect(screen.getByText('Poor')).toBeInTheDocument();
    });
  });

  describe('response time labels', () => {
    it('shows Normal for 1000-3000ms', () => {
      const normalBreaker = { ...mockBreaker, avg_response_time_ms: 1500 };
      render(<CircuitBreakerCard breaker={normalBreaker} />);

      expect(screen.getByText('Normal')).toBeInTheDocument();
    });

    it('shows Slow for >3000ms', () => {
      const slowBreaker = { ...mockBreaker, avg_response_time_ms: 4000 };
      render(<CircuitBreakerCard breaker={slowBreaker} />);

      expect(screen.getByText('Slow')).toBeInTheDocument();
    });
  });

  describe('threshold progress', () => {
    it('shows Failure Threshold label', () => {
      render(<CircuitBreakerCard {...defaultProps} />);

      expect(screen.getByText('Failure Threshold')).toBeInTheDocument();
    });

    it('shows failure count vs threshold', () => {
      render(<CircuitBreakerCard {...defaultProps} />);

      expect(screen.getByText('2/5')).toBeInTheDocument();
    });

    it('shows success threshold for half_open state', () => {
      const halfOpenBreaker = { ...mockBreaker, state: 'half_open' as const, success_count: 1 };
      render(<CircuitBreakerCard breaker={halfOpenBreaker} />);

      expect(screen.getByText('Success Threshold')).toBeInTheDocument();
      expect(screen.getByText('1/3')).toBeInTheDocument();
    });

    it('hides success threshold for closed state', () => {
      render(<CircuitBreakerCard {...defaultProps} />);

      expect(screen.queryByText('Success Threshold')).not.toBeInTheDocument();
    });
  });

  describe('configuration summary', () => {
    it('shows Failure Threshold configuration', () => {
      render(<CircuitBreakerCard {...defaultProps} />);

      const configSection = screen.getByText('Failure Threshold:').parentElement;
      expect(configSection).toBeInTheDocument();
    });

    it('shows Timeout configuration', () => {
      render(<CircuitBreakerCard {...defaultProps} />);

      expect(screen.getByText('Timeout:')).toBeInTheDocument();
      expect(screen.getByText('5000ms')).toBeInTheDocument();
    });

    it('shows Reset Timeout configuration', () => {
      render(<CircuitBreakerCard {...defaultProps} />);

      expect(screen.getByText('Reset Timeout:')).toBeInTheDocument();
      expect(screen.getByText('30000ms')).toBeInTheDocument();
    });
  });

  describe('timestamps', () => {
    it('shows Last Success timestamp', () => {
      render(<CircuitBreakerCard {...defaultProps} />);

      expect(screen.getByText('Last Success:')).toBeInTheDocument();
    });

    it('shows Last Failure timestamp', () => {
      render(<CircuitBreakerCard {...defaultProps} />);

      expect(screen.getByText('Last Failure:')).toBeInTheDocument();
    });

    it('shows Opened At for open state', () => {
      const openBreaker = {
        ...mockBreaker,
        state: 'open' as const,
        opened_at: '2025-01-15T10:00:00Z'
      };
      render(<CircuitBreakerCard breaker={openBreaker} />);

      expect(screen.getByText('Opened At:')).toBeInTheDocument();
    });

    it('hides Opened At for closed state', () => {
      render(<CircuitBreakerCard {...defaultProps} />);

      expect(screen.queryByText('Opened At:')).not.toBeInTheDocument();
    });
  });

  describe('open state info', () => {
    it('shows countdown for open state with next_attempt_at', () => {
      const futureTime = new Date(Date.now() + 60000).toISOString(); // 1 minute from now
      const openBreaker = {
        ...mockBreaker,
        state: 'open' as const,
        next_attempt_at: futureTime
      };
      render(<CircuitBreakerCard breaker={openBreaker} />);

      expect(screen.getByText(/Next attempt in/)).toBeInTheDocument();
    });

    it('shows AlertTriangle icon for open state warning', () => {
      const futureTime = new Date(Date.now() + 60000).toISOString();
      const openBreaker = {
        ...mockBreaker,
        state: 'open' as const,
        next_attempt_at: futureTime
      };
      const { container } = render(<CircuitBreakerCard breaker={openBreaker} />);

      expect(container.querySelector('.lucide-triangle-alert')).toBeInTheDocument();
    });
  });

  describe('half_open state info', () => {
    it('shows testing connection message', () => {
      const halfOpenBreaker = { ...mockBreaker, state: 'half_open' as const, success_count: 1 };
      render(<CircuitBreakerCard breaker={halfOpenBreaker} />);

      expect(screen.getByText(/Testing connection/)).toBeInTheDocument();
      expect(screen.getByText(/1\/3 successes/)).toBeInTheDocument();
    });

    it('shows Activity icon for half_open state', () => {
      const halfOpenBreaker = { ...mockBreaker, state: 'half_open' as const };
      const { container } = render(<CircuitBreakerCard breaker={halfOpenBreaker} />);

      expect(container.querySelector('.lucide-activity')).toBeInTheDocument();
    });
  });

  describe('actions', () => {
    it('shows Reset button for open state when onReset provided', () => {
      const openBreaker = { ...mockBreaker, state: 'open' as const };
      render(<CircuitBreakerCard breaker={openBreaker} onReset={jest.fn()} />);

      expect(screen.getByText('Reset')).toBeInTheDocument();
    });

    it('hides Reset button for closed state', () => {
      render(<CircuitBreakerCard {...defaultProps} onReset={jest.fn()} />);

      expect(screen.queryByText('Reset')).not.toBeInTheDocument();
    });

    it('calls onReset with breaker id when Reset clicked', () => {
      const onReset = jest.fn();
      const openBreaker = { ...mockBreaker, state: 'open' as const };
      render(<CircuitBreakerCard breaker={openBreaker} onReset={onReset} />);

      fireEvent.click(screen.getByText('Reset'));

      expect(onReset).toHaveBeenCalledWith('breaker-1');
    });

    it('shows View History button', () => {
      render(<CircuitBreakerCard {...defaultProps} />);

      expect(screen.getByText('View History')).toBeInTheDocument();
    });

    it('calls onClick when View History clicked', () => {
      const onClick = jest.fn();
      render(<CircuitBreakerCard {...defaultProps} onClick={onClick} />);

      fireEvent.click(screen.getByText('View History'));

      expect(onClick).toHaveBeenCalled();
    });

    it('stops propagation when Reset clicked', () => {
      const onReset = jest.fn();
      const onClick = jest.fn();
      const openBreaker = { ...mockBreaker, state: 'open' as const };
      render(<CircuitBreakerCard breaker={openBreaker} onReset={onReset} onClick={onClick} />);

      fireEvent.click(screen.getByText('Reset'));

      expect(onReset).toHaveBeenCalled();
      expect(onClick).not.toHaveBeenCalled();
    });
  });

  describe('card click', () => {
    it('calls onClick when card clicked', () => {
      const onClick = jest.fn();
      render(<CircuitBreakerCard {...defaultProps} onClick={onClick} />);

      const card = screen.getByTestId('card');
      fireEvent.click(card);

      expect(onClick).toHaveBeenCalled();
    });

    it('has cursor-pointer class', () => {
      const { container } = render(<CircuitBreakerCard {...defaultProps} />);

      expect(container.querySelector('.cursor-pointer')).toBeInTheDocument();
    });

    it('has hover shadow transition', () => {
      const { container } = render(<CircuitBreakerCard {...defaultProps} />);

      expect(container.querySelector('.hover\\:shadow-lg')).toBeInTheDocument();
    });
  });

  describe('service badge colors', () => {
    it('applies ai_provider color', () => {
      render(<CircuitBreakerCard {...defaultProps} />);

      const serviceBadge = screen.getByText('ai provider').closest('[data-testid="badge"]');
      expect(serviceBadge).toHaveClass('bg-theme-interactive-primary');
    });

    it('applies payment_gateway color', () => {
      const paymentBreaker = { ...mockBreaker, service: 'payment_gateway' as const };
      render(<CircuitBreakerCard breaker={paymentBreaker} />);

      const serviceBadge = screen.getByText('payment gateway').closest('[data-testid="badge"]');
      expect(serviceBadge).toHaveClass('bg-theme-success');
    });

    it('applies notification color', () => {
      const notificationBreaker = { ...mockBreaker, service: 'notification' as const };
      render(<CircuitBreakerCard breaker={notificationBreaker} />);

      const serviceBadge = screen.getByText('notification').closest('[data-testid="badge"]');
      expect(serviceBadge).toHaveClass('bg-theme-info');
    });

    it('applies storage color', () => {
      const storageBreaker = { ...mockBreaker, service: 'storage' as const };
      render(<CircuitBreakerCard breaker={storageBreaker} />);

      const serviceBadge = screen.getByText('storage').closest('[data-testid="badge"]');
      expect(serviceBadge).toHaveClass('bg-theme-warning');
    });
  });

  describe('state background colors', () => {
    it('applies success background for closed state', () => {
      const { container } = render(<CircuitBreakerCard {...defaultProps} />);

      expect(container.querySelector('.bg-theme-success.bg-opacity-10')).toBeInTheDocument();
    });

    it('applies error background for open state', () => {
      const openBreaker = { ...mockBreaker, state: 'open' as const };
      const { container } = render(<CircuitBreakerCard breaker={openBreaker} />);

      expect(container.querySelector('.bg-theme-error.bg-opacity-10')).toBeInTheDocument();
    });

    it('applies warning background for half_open state', () => {
      const halfOpenBreaker = { ...mockBreaker, state: 'half_open' as const };
      const { container } = render(<CircuitBreakerCard breaker={halfOpenBreaker} />);

      expect(container.querySelector('.bg-theme-warning.bg-opacity-10')).toBeInTheDocument();
    });
  });
});
