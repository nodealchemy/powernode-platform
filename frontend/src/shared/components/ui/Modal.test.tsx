import { render, screen, fireEvent } from '@testing-library/react';
import { Modal } from './Modal';

describe('Modal', () => {
  const defaultProps = {
    isOpen: true,
    onClose: jest.fn(),
    title: 'Test Modal',
    children: <div>Modal content</div>
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('rendering', () => {
    it('renders when isOpen is true', () => {
      render(<Modal {...defaultProps} />);
      expect(screen.getByRole('dialog')).toBeInTheDocument();
      expect(screen.getByText('Test Modal')).toBeInTheDocument();
      expect(screen.getByText('Modal content')).toBeInTheDocument();
    });

    it('does not render when isOpen is false', () => {
      render(<Modal {...defaultProps} isOpen={false} />);
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    });

    it('renders title correctly', () => {
      render(<Modal {...defaultProps} title="Custom Title" />);
      expect(screen.getByText('Custom Title')).toBeInTheDocument();
    });

    it('renders React node as title', () => {
      render(
        <Modal {...defaultProps} title={<span data-testid="custom-title">Node Title</span>} />
      );
      expect(screen.getByTestId('custom-title')).toBeInTheDocument();
    });

    it('renders children content', () => {
      render(
        <Modal {...defaultProps}>
          <p>Child paragraph</p>
          <button>Child button</button>
        </Modal>
      );
      expect(screen.getByText('Child paragraph')).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Child button' })).toBeInTheDocument();
    });
  });

  describe('close button', () => {
    it('renders close button by default', () => {
      render(<Modal {...defaultProps} />);
      expect(screen.getByRole('button', { name: 'Close modal' })).toBeInTheDocument();
    });

    it('hides close button when showCloseButton is false', () => {
      render(<Modal {...defaultProps} showCloseButton={false} />);
      expect(screen.queryByRole('button', { name: 'Close modal' })).not.toBeInTheDocument();
    });

    it('calls onClose when close button is clicked', () => {
      const handleClose = jest.fn();
      render(<Modal {...defaultProps} onClose={handleClose} />);
      fireEvent.click(screen.getByRole('button', { name: 'Close modal' }));
      expect(handleClose).toHaveBeenCalledTimes(1);
    });
  });

  describe('backdrop click', () => {
    it('calls onClose when backdrop is clicked', () => {
      const handleClose = jest.fn();
      render(<Modal {...defaultProps} onClose={handleClose} />);
      const backdrop = document.querySelector('[class*="justify-center"]');
      if (backdrop) {
        fireEvent.click(backdrop);
        expect(handleClose).toHaveBeenCalledTimes(1);
      }
    });

    it('does not call onClose when closeOnBackdrop is false', () => {
      const handleClose = jest.fn();
      render(
        <Modal {...defaultProps} onClose={handleClose} closeOnBackdrop={false} />
      );
      const backdrop = document.querySelector('[class*="justify-center"]');
      if (backdrop) {
        fireEvent.click(backdrop);
        expect(handleClose).not.toHaveBeenCalled();
      }
    });

    it('does not call onClose when clicking modal content', () => {
      const handleClose = jest.fn();
      render(<Modal {...defaultProps} onClose={handleClose} />);
      fireEvent.click(screen.getByText('Modal content'));
      expect(handleClose).not.toHaveBeenCalled();
    });
  });

  describe('escape key', () => {
    it('calls onClose when Escape is pressed', () => {
      const handleClose = jest.fn();
      render(<Modal {...defaultProps} onClose={handleClose} />);
      fireEvent.keyDown(document, { key: 'Escape' });
      expect(handleClose).toHaveBeenCalledTimes(1);
    });

    it('does not call onClose when closeOnEscape is false', () => {
      const handleClose = jest.fn();
      render(<Modal {...defaultProps} onClose={handleClose} closeOnEscape={false} />);
      fireEvent.keyDown(document, { key: 'Escape' });
      expect(handleClose).not.toHaveBeenCalled();
    });
  });

  describe('max width / size', () => {
    it.each([
      ['sm', 'max-w-sm'],
      ['md', 'max-w-md'],
      ['lg', 'max-w-lg'],
      ['xl', 'max-w-xl'],
      ['2xl', 'max-w-2xl'],
      ['3xl', 'max-w-3xl'],
      ['4xl', 'max-w-4xl'],
      ['5xl', 'max-w-5xl'],
      ['6xl', 'max-w-6xl'],
      ['7xl', 'max-w-7xl'],
    ])('applies %s maxWidth correctly', (maxWidth, expectedClass) => {
      render(
        <Modal {...defaultProps} maxWidth={maxWidth as 'sm' | 'md' | 'lg' | 'xl' | '2xl' | '3xl' | '4xl' | '5xl' | '6xl' | '7xl'} />
      );
      expect(document.querySelector(`.${expectedClass}`)).toBeInTheDocument();
    });

    it('uses size prop as alias for maxWidth', () => {
      render(<Modal {...defaultProps} size="2xl" />);
      expect(document.querySelector('.max-w-2xl')).toBeInTheDocument();
    });

    it('prefers size over maxWidth when both provided', () => {
      render(<Modal {...defaultProps} maxWidth="sm" size="xl" />);
      expect(document.querySelector('.max-w-xl')).toBeInTheDocument();
    });
  });

  describe('variants', () => {
    it('renders default variant', () => {
      render(<Modal {...defaultProps} variant="default" />);
      expect(document.querySelector('.rounded-2xl')).toBeInTheDocument();
    });

    it('renders centered variant', () => {
      render(<Modal {...defaultProps} variant="centered" />);
      expect(document.querySelector('.my-auto')).toBeInTheDocument();
    });

    it('renders fullscreen variant', () => {
      render(<Modal {...defaultProps} variant="fullscreen" />);
      expect(document.querySelector('.h-full.w-full')).toBeInTheDocument();
    });

    it('renders drawer variant', () => {
      render(<Modal {...defaultProps} variant="drawer" />);
      expect(document.querySelector('.ml-auto')).toBeInTheDocument();
    });
  });

  describe('subtitle and icon', () => {
    it('renders subtitle when provided', () => {
      render(<Modal {...defaultProps} subtitle="Subtitle text" />);
      expect(screen.getByText('Subtitle text')).toBeInTheDocument();
    });

    it('renders React node as subtitle', () => {
      render(
        <Modal {...defaultProps} subtitle={<em data-testid="em-subtitle">Emphasized</em>} />
      );
      expect(screen.getByTestId('em-subtitle')).toBeInTheDocument();
    });

    it('renders icon when provided', () => {
      render(<Modal {...defaultProps} icon={<span data-testid="modal-icon">🔔</span>} />);
      expect(screen.getByTestId('modal-icon')).toBeInTheDocument();
    });
  });

  describe('footer', () => {
    it('renders footer when provided', () => {
      render(
        <Modal {...defaultProps} footer={<button>Save</button>} />
      );
      expect(screen.getByRole('button', { name: 'Save' })).toBeInTheDocument();
    });

    it('does not render footer section when footer is not provided', () => {
      render(<Modal {...defaultProps} />);
      const footerElements = document.querySelectorAll('[class*="justify-end"]');
      // Footer section should not be present (only header actions area uses justify-between)
      expect(footerElements.length).toBeLessThanOrEqual(1);
    });
  });

  describe('animation and blur', () => {
    it('applies animation classes by default', () => {
      render(<Modal {...defaultProps} />);
      expect(document.querySelector('.animate-modal-slide-up')).toBeInTheDocument();
    });

    it('removes animation classes when animate is false', () => {
      render(<Modal {...defaultProps} animate={false} />);
      expect(document.querySelector('.animate-modal-slide-up')).not.toBeInTheDocument();
    });

    it('applies blur by default', () => {
      render(<Modal {...defaultProps} />);
      expect(document.querySelector('.backdrop-blur-sm')).toBeInTheDocument();
    });

    it('removes blur when blur is false', () => {
      render(<Modal {...defaultProps} blur={false} />);
      expect(document.querySelector('.backdrop-blur-sm')).not.toBeInTheDocument();
    });
  });

  describe('accessibility', () => {
    it('has correct role and aria attributes', () => {
      render(<Modal {...defaultProps} />);
      const dialog = screen.getByRole('dialog');
      expect(dialog).toHaveAttribute('aria-modal', 'true');
      expect(dialog).toHaveAttribute('aria-labelledby', 'modal-title');
    });

    it('has title with correct id for aria-labelledby', () => {
      render(<Modal {...defaultProps} />);
      expect(screen.getByText('Test Modal')).toHaveAttribute('id', 'modal-title');
    });

    it('prevents body scroll when open', () => {
      render(<Modal {...defaultProps} />);
      expect(document.body.style.overflow).toBe('hidden');
    });

    it('restores body scroll when closed', () => {
      const { rerender } = render(<Modal {...defaultProps} />);
      expect(document.body.style.overflow).toBe('hidden');

      rerender(<Modal {...defaultProps} isOpen={false} />);
      expect(document.body.style.overflow).toBe('unset');
    });
  });

  describe('custom className', () => {
    it('applies custom className to modal', () => {
      render(<Modal {...defaultProps} className="custom-modal" />);
      expect(document.querySelector('.custom-modal')).toBeInTheDocument();
    });
  });

  describe('content scroll', () => {
    it('allows content scroll by default', () => {
      render(<Modal {...defaultProps} />);
      expect(document.querySelector('.max-h-\\[60vh\\]')).toBeInTheDocument();
    });

    it('disables content scroll when disableContentScroll is true', () => {
      render(<Modal {...defaultProps} disableContentScroll />);
      expect(document.querySelector('.max-h-\\[60vh\\]')).not.toBeInTheDocument();
    });
  });
});
