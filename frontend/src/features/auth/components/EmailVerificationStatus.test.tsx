import { render, screen } from '@testing-library/react';
import { EmailVerificationStatus, EmailVerificationLoader } from './EmailVerificationStatus';

describe('EmailVerificationStatus', () => {
  it('displays verified status with correct styling', () => {
    render(<EmailVerificationStatus isVerified={true} />);

    expect(screen.getByText('Verified')).toBeInTheDocument();
    
    const icon = document.querySelector('svg');
    expect(icon).toBeInTheDocument();
    expect(icon).toHaveClass('text-theme-success');
  });

  it('displays unverified status with correct styling', () => {
    render(<EmailVerificationStatus isVerified={false} />);

    expect(screen.getByText('Unverified')).toBeInTheDocument();
    
    const icon = document.querySelector('svg');
    expect(icon).toBeInTheDocument();
    expect(icon).toHaveClass('text-theme-warning');
  });

  it('hides icon when showIcon is false', () => {
    render(<EmailVerificationStatus isVerified={true} showIcon={false} />);

    expect(screen.getByText('Verified')).toBeInTheDocument();
    expect(document.querySelector('svg')).not.toBeInTheDocument();
  });

  it('hides text when showText is false', () => {
    render(<EmailVerificationStatus isVerified={true} showText={false} />);

    expect(screen.queryByText('Verified')).not.toBeInTheDocument();
    expect(document.querySelector('svg')).toBeInTheDocument();
  });

  it('renders badge variant correctly', () => {
    render(<EmailVerificationStatus isVerified={true} variant="badge" />);

    const badge = screen.getByText('Verified');
    expect(badge).toHaveClass('bg-theme-success-subtle', 'text-theme-success', 'rounded-full');
  });

  it('renders tooltip variant correctly', () => {
    render(<EmailVerificationStatus isVerified={false} variant="tooltip" />);

    const tooltip = document.querySelector('.group');
    expect(tooltip).toBeInTheDocument();
    expect(screen.getByText('Email Unverified')).toBeInTheDocument();
  });

  it('applies small size classes correctly', () => {
    render(<EmailVerificationStatus isVerified={true} size="sm" />);

    const icon = document.querySelector('svg');
    const text = screen.getByText('Verified');

    expect(icon).toHaveClass('h-3', 'w-3');
    expect(text).toHaveClass('text-xs');
  });

  it('applies medium size classes correctly', () => {
    render(<EmailVerificationStatus isVerified={true} size="md" />);

    const icon = document.querySelector('svg');
    const text = screen.getByText('Verified');

    expect(icon).toHaveClass('h-4', 'w-4');
    expect(text).toHaveClass('text-sm');
  });

  it('applies large size classes correctly', () => {
    render(<EmailVerificationStatus isVerified={true} size="lg" />);

    const icon = document.querySelector('svg');
    const text = screen.getByText('Verified');

    expect(icon).toHaveClass('h-5', 'w-5');
    expect(text).toHaveClass('text-base');
  });

  it('badge variant applies correct size classes', () => {
    render(<EmailVerificationStatus isVerified={true} variant="badge" size="sm" />);

    const badge = screen.getByText('Verified');
    expect(badge).toHaveClass('px-2', 'py-1', 'text-xs');
  });

  it('shows correct icon for verified state', () => {
    render(<EmailVerificationStatus isVerified={true} />);

    // CheckCircle icon should be present
    const icon = document.querySelector('svg');
    expect(icon).toBeInTheDocument();
  });

  it('shows correct icon for unverified state', () => {
    render(<EmailVerificationStatus isVerified={false} />);

    // AlertTriangle icon should be present
    const icon = document.querySelector('svg');
    expect(icon).toBeInTheDocument();
  });

  it('maintains default props when not specified', () => {
    render(<EmailVerificationStatus isVerified={true} />);

    // Should show both icon and text by default
    expect(document.querySelector('svg')).toBeInTheDocument();
    expect(screen.getByText('Verified')).toBeInTheDocument();
  });

  it('handles both showIcon and showText being false', () => {
    const { container } = render(
      <EmailVerificationStatus isVerified={true} showIcon={false} showText={false} />
    );

    expect(container.firstChild).toBeInTheDocument();
    expect(document.querySelector('svg')).not.toBeInTheDocument();
    expect(screen.queryByText('Verified')).not.toBeInTheDocument();
  });
});

describe('EmailVerificationLoader', () => {
  it('displays loading state correctly', () => {
    render(<EmailVerificationLoader />);

    expect(screen.getByText('Checking...')).toBeInTheDocument();
    
    const icon = document.querySelector('svg');
    expect(icon).toBeInTheDocument();
    expect(icon).toHaveClass('animate-spin', 'text-theme-muted');
  });

  it('hides text when showText is false', () => {
    render(<EmailVerificationLoader showText={false} />);

    expect(screen.queryByText('Checking...')).not.toBeInTheDocument();
    expect(document.querySelector('svg')).toBeInTheDocument();
  });

  it('applies correct size classes for small size', () => {
    render(<EmailVerificationLoader size="sm" />);

    const icon = document.querySelector('svg');
    const text = screen.getByText('Checking...');

    expect(icon).toHaveClass('h-3', 'w-3');
    expect(text).toHaveClass('text-xs');
  });

  it('applies correct size classes for large size', () => {
    render(<EmailVerificationLoader size="lg" />);

    const icon = document.querySelector('svg');
    const text = screen.getByText('Checking...');

    expect(icon).toHaveClass('h-5', 'w-5');
    expect(text).toHaveClass('text-base');
  });

  it('has spinning animation on icon', () => {
    render(<EmailVerificationLoader />);

    const icon = document.querySelector('svg');
    expect(icon).toHaveClass('animate-spin');
  });

  it('uses correct muted styling', () => {
    render(<EmailVerificationLoader />);

    const icon = document.querySelector('svg');
    const text = screen.getByText('Checking...');

    expect(icon).toHaveClass('text-theme-muted');
    expect(text).toHaveClass('text-theme-muted');
  });
});