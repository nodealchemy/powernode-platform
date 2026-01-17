import { render, screen, fireEvent } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { TabButton } from './TabButton';

const mockNavigate = jest.fn();

jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate
}));

describe('TabButton', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  const defaultProps = {
    id: 'tab-1',
    label: 'Dashboard',
    path: '/dashboard',
    isActive: false
  };

  const renderTabButton = (props = {}) => {
    return render(
      <MemoryRouter>
        <TabButton {...defaultProps} {...props} />
      </MemoryRouter>
    );
  };

  describe('rendering', () => {
    it('renders label', () => {
      renderTabButton();

      expect(screen.getByText('Dashboard')).toBeInTheDocument();
    });

    it('renders as button element', () => {
      renderTabButton();

      expect(screen.getByRole('button')).toBeInTheDocument();
    });

    it('renders icon when provided', () => {
      renderTabButton({ icon: '🏠' });

      expect(screen.getByText('🏠')).toBeInTheDocument();
    });
  });

  describe('navigation', () => {
    it('navigates to path when clicked', () => {
      renderTabButton();

      fireEvent.click(screen.getByRole('button'));

      expect(mockNavigate).toHaveBeenCalledWith('/dashboard');
    });

    it('calls onClick instead of navigate when onClick provided', () => {
      const onClick = jest.fn();
      renderTabButton({ onClick });

      fireEvent.click(screen.getByRole('button'));

      expect(onClick).toHaveBeenCalled();
      expect(mockNavigate).not.toHaveBeenCalled();
    });
  });

  describe('active state', () => {
    it('has active styling when isActive is true', () => {
      renderTabButton({ isActive: true });

      const button = screen.getByRole('button');
      expect(button).toHaveClass('border-theme-link', 'text-theme-link');
    });

    it('has inactive styling when isActive is false', () => {
      renderTabButton({ isActive: false });

      const button = screen.getByRole('button');
      expect(button).toHaveClass('border-transparent', 'text-theme-secondary');
    });
  });

  describe('disabled state', () => {
    it('is disabled when disabled prop is true', () => {
      renderTabButton({ disabled: true });

      expect(screen.getByRole('button')).toBeDisabled();
    });

    it('has disabled styling', () => {
      renderTabButton({ disabled: true });

      expect(screen.getByRole('button')).toHaveClass('opacity-50', 'cursor-not-allowed');
    });

    it('does not navigate when disabled', () => {
      renderTabButton({ disabled: true });

      fireEvent.click(screen.getByRole('button'));

      expect(mockNavigate).not.toHaveBeenCalled();
    });

    it('does not call onClick when disabled', () => {
      const onClick = jest.fn();
      renderTabButton({ disabled: true, onClick });

      fireEvent.click(screen.getByRole('button'));

      expect(onClick).not.toHaveBeenCalled();
    });
  });

  describe('styling', () => {
    it('has flex layout for icon and label', () => {
      renderTabButton();

      const button = screen.getByRole('button');
      expect(button).toHaveClass('flex', 'items-center');
    });

    it('has bottom border styling', () => {
      renderTabButton();

      const button = screen.getByRole('button');
      expect(button).toHaveClass('border-b-2');
    });

    it('applies custom className', () => {
      renderTabButton({ className: 'custom-class' });

      expect(screen.getByRole('button')).toHaveClass('custom-class');
    });
  });
});
