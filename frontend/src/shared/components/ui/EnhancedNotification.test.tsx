import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { EnhancedNotification } from './EnhancedNotification';

// Mock clipboard API
const mockWriteText = jest.fn();
Object.assign(navigator, {
  clipboard: {
    writeText: mockWriteText
  }
});

describe('EnhancedNotification', () => {
  const defaultProps = {
    id: 'notification-1',
    type: 'success' as const,
    message: 'Operation completed successfully',
    onRemove: jest.fn()
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockWriteText.mockResolvedValue(undefined);
  });

  describe('rendering', () => {
    it('renders notification message', () => {
      render(<EnhancedNotification {...defaultProps} />);

      expect(screen.getByText('Operation completed successfully')).toBeInTheDocument();
    });

    it('renders success notification with correct styling', () => {
      const { container } = render(<EnhancedNotification {...defaultProps} />);

      // The toast class is on the root element
      expect(container.firstChild).toHaveClass('toast-theme-success');
    });

    it('renders error notification with correct styling', () => {
      const { container } = render(<EnhancedNotification {...defaultProps} type="error" />);

      expect(container.firstChild).toHaveClass('toast-theme-error');
    });

    it('renders warning notification with correct styling', () => {
      const { container } = render(<EnhancedNotification {...defaultProps} type="warning" />);

      expect(container.firstChild).toHaveClass('toast-theme-warning');
    });

    it('renders info notification with correct styling', () => {
      const { container } = render(<EnhancedNotification {...defaultProps} type="info" />);

      expect(container.firstChild).toHaveClass('toast-theme-info');
    });

    it('renders copy button', () => {
      render(<EnhancedNotification {...defaultProps} />);

      expect(screen.getByTitle('Copy notification')).toBeInTheDocument();
    });

    it('renders dismiss button', () => {
      render(<EnhancedNotification {...defaultProps} />);

      expect(screen.getByTitle('Dismiss')).toBeInTheDocument();
    });
  });

  describe('icons', () => {
    it('renders success icon for success type', () => {
      render(<EnhancedNotification {...defaultProps} type="success" />);

      // CheckCircle icon is present
      const icons = document.querySelectorAll('.toast-icon');
      expect(icons.length).toBeGreaterThan(0);
    });

    it('renders error icon for error type', () => {
      render(<EnhancedNotification {...defaultProps} type="error" />);

      const icons = document.querySelectorAll('.toast-icon');
      expect(icons.length).toBeGreaterThan(0);
    });

    it('renders warning icon for warning type', () => {
      render(<EnhancedNotification {...defaultProps} type="warning" />);

      const icons = document.querySelectorAll('.toast-icon');
      expect(icons.length).toBeGreaterThan(0);
    });

    it('renders info icon for info type', () => {
      render(<EnhancedNotification {...defaultProps} type="info" />);

      const icons = document.querySelectorAll('.toast-icon');
      expect(icons.length).toBeGreaterThan(0);
    });
  });

  describe('dismiss', () => {
    it('calls onRemove with notification id when dismiss clicked', () => {
      const onRemove = jest.fn();
      render(<EnhancedNotification {...defaultProps} onRemove={onRemove} />);

      fireEvent.click(screen.getByTitle('Dismiss'));

      expect(onRemove).toHaveBeenCalledWith('notification-1');
    });
  });

  describe('copy functionality', () => {
    it('copies message to clipboard', async () => {
      render(<EnhancedNotification {...defaultProps} />);

      fireEvent.click(screen.getByTitle('Copy notification'));

      await waitFor(() => {
        expect(mockWriteText).toHaveBeenCalledWith('Operation completed successfully');
      });
    });

    it('shows check icon after copying', async () => {
      render(<EnhancedNotification {...defaultProps} />);

      fireEvent.click(screen.getByTitle('Copy notification'));

      await waitFor(() => {
        // After copy, the icon changes to Check
        expect(mockWriteText).toHaveBeenCalled();
      });
    });

    it('copies message with details when details exist', async () => {
      const details = { errorCode: 'E001', field: 'email' };
      render(<EnhancedNotification {...defaultProps} details={details} />);

      fireEvent.click(screen.getByTitle('Copy notification'));

      await waitFor(() => {
        expect(mockWriteText).toHaveBeenCalledWith(expect.stringContaining('Operation completed successfully'));
        expect(mockWriteText).toHaveBeenCalledWith(expect.stringContaining('errorCode'));
        expect(mockWriteText).toHaveBeenCalledWith(expect.stringContaining('E001'));
      });
    });
  });

  describe('expand functionality', () => {
    it('does not show expand button when no details', () => {
      render(<EnhancedNotification {...defaultProps} />);

      expect(screen.queryByTitle('Expand details')).not.toBeInTheDocument();
    });

    it('shows expand button when details exist', () => {
      const details = { errorCode: 'E001' };
      render(<EnhancedNotification {...defaultProps} details={details} />);

      expect(screen.getByTitle('Expand details')).toBeInTheDocument();
    });

    it('expands to show details when expand clicked', () => {
      const details = { errorCode: 'E001', message: 'Validation failed' };
      render(<EnhancedNotification {...defaultProps} details={details} />);

      // Details not visible initially
      expect(screen.queryByText('E001')).not.toBeInTheDocument();

      // Click expand
      fireEvent.click(screen.getByTitle('Expand details'));

      // Details now visible
      expect(screen.getByText('E001')).toBeInTheDocument();
      expect(screen.getByText('Validation failed')).toBeInTheDocument();
    });

    it('collapses when collapse clicked', () => {
      const details = { errorCode: 'E001' };
      render(<EnhancedNotification {...defaultProps} details={details} />);

      // Expand
      fireEvent.click(screen.getByTitle('Expand details'));
      expect(screen.getByText('E001')).toBeInTheDocument();

      // Collapse
      fireEvent.click(screen.getByTitle('Collapse details'));
      expect(screen.queryByText('E001')).not.toBeInTheDocument();
    });

    it('formats detail keys nicely', () => {
      const details = { errorCode: 'E001' };
      render(<EnhancedNotification {...defaultProps} details={details} />);

      fireEvent.click(screen.getByTitle('Expand details'));

      // ErrorCode should be formatted as "Error Code:"
      expect(screen.getByText('Error Code:')).toBeInTheDocument();
    });
  });

  describe('object details', () => {
    it('formats object values as JSON', () => {
      const details = { config: { setting: 'value', enabled: true } };
      render(<EnhancedNotification {...defaultProps} details={details} />);

      fireEvent.click(screen.getByTitle('Expand details'));

      // Should show JSON formatted object
      expect(screen.getByText(/setting/)).toBeInTheDocument();
    });
  });

  describe('empty details', () => {
    it('does not show expand button for empty details object', () => {
      const details = {};
      render(<EnhancedNotification {...defaultProps} details={details} />);

      expect(screen.queryByTitle('Expand details')).not.toBeInTheDocument();
    });
  });
});
