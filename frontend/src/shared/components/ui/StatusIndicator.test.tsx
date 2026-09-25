import { render, screen } from '@testing-library/react';
import { StatusIndicator } from './StatusIndicator';

describe('StatusIndicator', () => {
  describe('rendering', () => {
    it('renders with default text for status', () => {
      render(<StatusIndicator status="active" />);

      expect(screen.getByText('Active')).toBeInTheDocument();
    });

    it('renders with custom text', () => {
      render(<StatusIndicator status="active" text="Online" />);

      expect(screen.getByText('Online')).toBeInTheDocument();
      expect(screen.queryByText('Active')).not.toBeInTheDocument();
    });

    it('applies custom className', () => {
      const { container } = render(
        <StatusIndicator status="active" className="custom-class" />
      );

      expect(container.querySelector('.custom-class')).toBeInTheDocument();
    });
  });

  describe('status types', () => {
    it('renders active status', () => {
      render(<StatusIndicator status="active" />);

      expect(screen.getByText('Active')).toBeInTheDocument();
      expect(screen.getByText('●')).toBeInTheDocument();
    });

    it('renders inactive status', () => {
      render(<StatusIndicator status="inactive" />);

      expect(screen.getByText('Inactive')).toBeInTheDocument();
      expect(screen.getByText('○')).toBeInTheDocument();
    });

    it('renders pending status', () => {
      render(<StatusIndicator status="pending" />);

      expect(screen.getByText('Pending')).toBeInTheDocument();
      expect(screen.getByText('◐')).toBeInTheDocument();
    });

    it('renders error status', () => {
      render(<StatusIndicator status="error" />);

      expect(screen.getByText('Error')).toBeInTheDocument();
      expect(screen.getByText('✕')).toBeInTheDocument();
    });

    it('renders warning status', () => {
      render(<StatusIndicator status="warning" />);

      expect(screen.getByText('Warning')).toBeInTheDocument();
      expect(screen.getByText('⚠')).toBeInTheDocument();
    });

    it('renders success status', () => {
      render(<StatusIndicator status="success" />);

      expect(screen.getByText('Success')).toBeInTheDocument();
      expect(screen.getByText('✓')).toBeInTheDocument();
    });

    it('renders loading status', () => {
      render(<StatusIndicator status="loading" />);

      expect(screen.getByText('Loading')).toBeInTheDocument();
      expect(screen.getByText('◐')).toBeInTheDocument();
    });
  });

  describe('icon display', () => {
    it('shows icon by default', () => {
      render(<StatusIndicator status="active" />);

      expect(screen.getByText('●')).toBeInTheDocument();
    });

    it('hides icon when showIcon is false', () => {
      render(<StatusIndicator status="active" showIcon={false} />);

      expect(screen.queryByText('●')).not.toBeInTheDocument();
    });
  });

  describe('sizes', () => {
    it('renders small size', () => {
      const { container } = render(<StatusIndicator status="active" size="sm" />);

      // Badge should have size-specific styling
      expect(container.firstChild).toBeInTheDocument();
    });

    it('renders medium size by default', () => {
      const { container } = render(<StatusIndicator status="active" />);

      expect(container.firstChild).toBeInTheDocument();
    });

    it('renders large size', () => {
      const { container } = render(<StatusIndicator status="active" size="lg" />);

      expect(container.firstChild).toBeInTheDocument();
    });
  });
});

describe('Convenience Components', () => {

});
