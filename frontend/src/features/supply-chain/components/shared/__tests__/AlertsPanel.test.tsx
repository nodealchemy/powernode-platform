import { render, screen, fireEvent } from '@testing-library/react';
import { AlertsPanel } from '../AlertsPanel';

jest.mock('lucide-react', () => ({
  AlertTriangle: ({ className }: { className?: string }) => (
    <span data-testid="alert-triangle" className={className} />
  ),
  AlertCircle: ({ className }: { className?: string }) => (
    <span data-testid="alert-circle" className={className} />
  ),
  Info: ({ className }: { className?: string }) => (
    <span data-testid="info-icon" className={className} />
  ),
  CheckCircle: ({ className }: { className?: string }) => (
    <span data-testid="check-circle" className={className} />
  ),
}));

describe('AlertsPanel', () => {
  describe('empty state', () => {
    it('renders empty state when no alerts', () => {
      render(<AlertsPanel alerts={[]} />);
      expect(screen.getByText('Recent Alerts')).toBeInTheDocument();
      expect(screen.getByText('No active alerts')).toBeInTheDocument();
    });

    it('displays CheckCircle icon in empty state', () => {
      render(<AlertsPanel alerts={[]} />);
      expect(screen.getByTestId('check-circle')).toBeInTheDocument();
    });

    it('applies success color to empty state icon', () => {
      render(<AlertsPanel alerts={[]} />);
      const icon = screen.getByTestId('check-circle');
      expect(icon).toHaveClass('w-8');
      expect(icon).toHaveClass('h-8');
      expect(icon).toHaveClass('text-theme-success');
    });
  });

  describe('alert rendering', () => {
    const mockAlert = {
      id: 'alert-1',
      type: 'vulnerability',
      severity: 'high' as const,
      title: 'Critical Vulnerability',
      message: 'A security vulnerability was detected',
      entity_id: 'component-123',
      entity_type: 'component',
      created_at: new Date().toISOString(),
    };

    it('renders single alert', () => {
      render(<AlertsPanel alerts={[mockAlert]} />);
      expect(screen.getByText('Critical Vulnerability')).toBeInTheDocument();
      expect(screen.getByText('A security vulnerability was detected')).toBeInTheDocument();
    });

    it('renders multiple alerts', () => {
      const alerts = [
        mockAlert,
        { ...mockAlert, id: 'alert-2', title: 'License Violation' },
        { ...mockAlert, id: 'alert-3', title: 'Compliance Issue' },
      ];
      render(<AlertsPanel alerts={alerts} />);
      expect(screen.getByText('Critical Vulnerability')).toBeInTheDocument();
      expect(screen.getByText('License Violation')).toBeInTheDocument();
      expect(screen.getByText('Compliance Issue')).toBeInTheDocument();
    });
  });

  describe('severity icons', () => {
    it('renders AlertCircle icon for critical severity', () => {
      const alert = {
        id: 'alert-1',
        type: 'vulnerability',
        severity: 'critical' as const,
        title: 'Critical Issue',
        message: 'A critical issue detected',
        entity_id: 'component-123',
        entity_type: 'component',
        created_at: new Date().toISOString(),
      };
      render(<AlertsPanel alerts={[alert]} />);
      expect(screen.getByTestId('alert-circle')).toBeInTheDocument();
    });

    it('renders AlertTriangle icon for high severity', () => {
      const alert = {
        id: 'alert-1',
        type: 'vulnerability',
        severity: 'high' as const,
        title: 'High Priority',
        message: 'High priority issue',
        entity_id: 'component-123',
        entity_type: 'component',
        created_at: new Date().toISOString(),
      };
      render(<AlertsPanel alerts={[alert]} />);
      expect(screen.getByTestId('alert-triangle')).toBeInTheDocument();
    });

    it('renders Info icon for medium severity', () => {
      const alert = {
        id: 'alert-1',
        type: 'vulnerability',
        severity: 'medium' as const,
        title: 'Medium Priority',
        message: 'Medium priority issue',
        entity_id: 'component-123',
        entity_type: 'component',
        created_at: new Date().toISOString(),
      };
      render(<AlertsPanel alerts={[alert]} />);
      expect(screen.getByTestId('info-icon')).toBeInTheDocument();
    });

    it('renders CheckCircle icon for low severity', () => {
      const alert = {
        id: 'alert-1',
        type: 'vulnerability',
        severity: 'low' as const,
        title: 'Low Priority',
        message: 'Low priority issue',
        entity_id: 'component-123',
        entity_type: 'component',
        created_at: new Date().toISOString(),
      };
      render(<AlertsPanel alerts={[alert]} />);
      const icons = screen.getAllByTestId('check-circle');
      expect(icons.length).toBeGreaterThan(0);
    });
  });

  describe('severity colors', () => {
    it('applies error color for critical severity', () => {
      const alert = {
        id: 'alert-1',
        type: 'vulnerability',
        severity: 'critical' as const,
        title: 'Critical Issue',
        message: 'Critical issue',
        entity_id: 'component-123',
        entity_type: 'component',
        created_at: new Date().toISOString(),
      };
      render(<AlertsPanel alerts={[alert]} />);
      const icon = screen.getByTestId('alert-circle');
      expect(icon).toHaveClass('text-theme-error');
    });

    it('applies warning color for high severity', () => {
      const alert = {
        id: 'alert-1',
        type: 'vulnerability',
        severity: 'high' as const,
        title: 'High Priority',
        message: 'High issue',
        entity_id: 'component-123',
        entity_type: 'component',
        created_at: new Date().toISOString(),
      };
      render(<AlertsPanel alerts={[alert]} />);
      const icon = screen.getByTestId('alert-triangle');
      expect(icon).toHaveClass('text-theme-warning');
    });

    it('applies info color for medium severity', () => {
      const alert = {
        id: 'alert-1',
        type: 'vulnerability',
        severity: 'medium' as const,
        title: 'Medium Priority',
        message: 'Medium issue',
        entity_id: 'component-123',
        entity_type: 'component',
        created_at: new Date().toISOString(),
      };
      render(<AlertsPanel alerts={[alert]} />);
      const icon = screen.getByTestId('info-icon');
      expect(icon).toHaveClass('text-theme-info');
    });

    it('applies success color for low severity', () => {
      const alert = {
        id: 'alert-1',
        type: 'vulnerability',
        severity: 'low' as const,
        title: 'Low Priority',
        message: 'Low issue',
        entity_id: 'component-123',
        entity_type: 'component',
        created_at: new Date().toISOString(),
      };
      render(<AlertsPanel alerts={[alert]} />);
      const icons = screen.getAllByTestId('check-circle');
      const lowSeverityIcon = icons.find((icon) => icon.className.includes('text-theme-success'));
      expect(lowSeverityIcon).toHaveClass('text-theme-success');
    });
  });

  describe('maxItems prop', () => {
    it('limits display to default 5 items', () => {
      const alerts = Array.from({ length: 10 }, (_, i) => ({
        id: `alert-${i}`,
        type: 'vulnerability',
        severity: 'high' as const,
        title: `Alert ${i}`,
        message: `Message ${i}`,
        entity_id: `component-${i}`,
        entity_type: 'component',
        created_at: new Date().toISOString(),
      }));
      render(<AlertsPanel alerts={alerts} />);
      expect(screen.getByText('Alert 0')).toBeInTheDocument();
      expect(screen.getByText('Alert 4')).toBeInTheDocument();
      expect(screen.queryByText('Alert 5')).not.toBeInTheDocument();
    });

    it('respects custom maxItems', () => {
      const alerts = Array.from({ length: 10 }, (_, i) => ({
        id: `alert-${i}`,
        type: 'vulnerability',
        severity: 'high' as const,
        title: `Alert ${i}`,
        message: `Message ${i}`,
        entity_id: `component-${i}`,
        entity_type: 'component',
        created_at: new Date().toISOString(),
      }));
      render(<AlertsPanel alerts={alerts} maxItems={3} />);
      expect(screen.getByText('Alert 0')).toBeInTheDocument();
      expect(screen.getByText('Alert 2')).toBeInTheDocument();
      expect(screen.queryByText('Alert 3')).not.toBeInTheDocument();
    });

    it('displays all alerts if fewer than maxItems', () => {
      const alerts = Array.from({ length: 3 }, (_, i) => ({
        id: `alert-${i}`,
        type: 'vulnerability',
        severity: 'high' as const,
        title: `Alert ${i}`,
        message: `Message ${i}`,
        entity_id: `component-${i}`,
        entity_type: 'component',
        created_at: new Date().toISOString(),
      }));
      render(<AlertsPanel alerts={alerts} maxItems={5} />);
      expect(screen.getByText('Alert 0')).toBeInTheDocument();
      expect(screen.getByText('Alert 1')).toBeInTheDocument();
      expect(screen.getByText('Alert 2')).toBeInTheDocument();
    });
  });

  describe('text content', () => {
    it('displays alert title', () => {
      const alert = {
        id: 'alert-1',
        type: 'vulnerability',
        severity: 'high' as const,
        title: 'Security Vulnerability Found',
        message: 'A vulnerability exists',
        entity_id: 'component-123',
        entity_type: 'component',
        created_at: new Date().toISOString(),
      };
      render(<AlertsPanel alerts={[alert]} />);
      expect(screen.getByText('Security Vulnerability Found')).toBeInTheDocument();
    });

    it('displays alert message', () => {
      const alert = {
        id: 'alert-1',
        type: 'vulnerability',
        severity: 'high' as const,
        title: 'Vulnerability',
        message: 'This is a detailed message about the issue',
        entity_id: 'component-123',
        entity_type: 'component',
        created_at: new Date().toISOString(),
      };
      render(<AlertsPanel alerts={[alert]} />);
      expect(screen.getByText('This is a detailed message about the issue')).toBeInTheDocument();
    });

    it('truncates long titles', () => {
      const alert = {
        id: 'alert-1',
        type: 'vulnerability',
        severity: 'high' as const,
        title: 'A'.repeat(100),
        message: 'Short message',
        entity_id: 'component-123',
        entity_type: 'component',
        created_at: new Date().toISOString(),
      };
      const { container } = render(<AlertsPanel alerts={[alert]} />);
      const title = container.querySelector('[data-testid="alert-title"]') || container.querySelector('p');
      expect(title).toHaveClass('truncate');
    });

    it('truncates long messages', () => {
      const alert = {
        id: 'alert-1',
        type: 'vulnerability',
        severity: 'high' as const,
        title: 'Title',
        message: 'B'.repeat(100),
        entity_id: 'component-123',
        entity_type: 'component',
        created_at: new Date().toISOString(),
      };
      const { container } = render(<AlertsPanel alerts={[alert]} />);
      const messages = container.querySelectorAll('p');
      const messageElement = Array.from(messages).find((p) => p.textContent?.includes('B'));
      expect(messageElement).toHaveClass('truncate');
    });
  });

  describe('click handling', () => {
    it('calls onAlertClick when alert is clicked', () => {
      const mockOnClick = jest.fn();
      const alert = {
        id: 'alert-1',
        type: 'vulnerability',
        severity: 'high' as const,
        title: 'Test Alert',
        message: 'Test message',
        entity_id: 'component-123',
        entity_type: 'component',
        created_at: new Date().toISOString(),
      };
      const { container } = render(
        <AlertsPanel alerts={[alert]} onAlertClick={mockOnClick} />
      );
      const alertElement = container.querySelector('div[class*="flex items-start gap-3"]');
      if (alertElement) {
        fireEvent.click(alertElement);
      }
      expect(mockOnClick).toHaveBeenCalledWith(alert);
    });

    it('does not crash when onAlertClick is not provided', () => {
      const alert = {
        id: 'alert-1',
        type: 'vulnerability',
        severity: 'high' as const,
        title: 'Test Alert',
        message: 'Test message',
        entity_id: 'component-123',
        entity_type: 'component',
        created_at: new Date().toISOString(),
      };
      const { container } = render(<AlertsPanel alerts={[alert]} />);
      const alertElement = container.querySelector('div[class*="flex items-start gap-3"]');
      expect(() => {
        if (alertElement) {
          fireEvent.click(alertElement);
        }
      }).not.toThrow();
    });

    it('calls onAlertClick with correct alert data', () => {
      const mockOnClick = jest.fn();
      const alert = {
        id: 'alert-42',
        type: 'compliance',
        severity: 'critical' as const,
        title: 'Compliance Alert',
        message: 'Compliance check failed',
        entity_id: 'vendor-999',
        entity_type: 'vendor',
        created_at: '2024-01-01T12:00:00Z',
      };
      const { container } = render(
        <AlertsPanel alerts={[alert]} onAlertClick={mockOnClick} />
      );
      const alertElement = container.querySelector('div[class*="flex items-start gap-3"]');
      if (alertElement) {
        fireEvent.click(alertElement);
      }
      expect(mockOnClick).toHaveBeenCalledWith(alert);
    });
  });

  describe('cursor styles', () => {
    it('applies cursor-pointer when onAlertClick is provided', () => {
      const mockOnClick = jest.fn();
      const alert = {
        id: 'alert-1',
        type: 'vulnerability',
        severity: 'high' as const,
        title: 'Test Alert',
        message: 'Test message',
        entity_id: 'component-123',
        entity_type: 'component',
        created_at: new Date().toISOString(),
      };
      const { container } = render(
        <AlertsPanel alerts={[alert]} onAlertClick={mockOnClick} />
      );
      const alertElement = container.querySelector('div[class*="cursor-pointer"]');
      expect(alertElement).toBeInTheDocument();
    });

    it('does not apply cursor-pointer when onAlertClick is not provided', () => {
      const alert = {
        id: 'alert-1',
        type: 'vulnerability',
        severity: 'high' as const,
        title: 'Test Alert',
        message: 'Test message',
        entity_id: 'component-123',
        entity_type: 'component',
        created_at: new Date().toISOString(),
      };
      const { container } = render(<AlertsPanel alerts={[alert]} />);
      const alertElement = container.querySelector('div[class*="cursor-pointer"]');
      expect(alertElement).not.toBeInTheDocument();
    });
  });

  describe('panel structure', () => {
    it('displays panel title', () => {
      render(<AlertsPanel alerts={[]} />);
      expect(screen.getByText('Recent Alerts')).toBeInTheDocument();
    });

    it('has proper styling and layout', () => {
      const { container } = render(<AlertsPanel alerts={[]} />);
      const panel = container.querySelector('div[class*="bg-theme-surface"]');
      expect(panel).toHaveClass('rounded-lg');
      expect(panel).toHaveClass('p-4');
    });
  });
});
