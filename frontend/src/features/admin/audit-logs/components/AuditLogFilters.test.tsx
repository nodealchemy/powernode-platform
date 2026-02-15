import { render, screen, fireEvent } from '@testing-library/react';
import { AuditLogFilters } from './AuditLogFilters';

describe('AuditLogFilters', () => {
  const defaultFilters = {};

  const defaultProps = {
    filters: defaultFilters,
    onFiltersChange: jest.fn(),
    onClearFilters: jest.fn()
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('header', () => {
    it('shows Filters title', () => {
      render(<AuditLogFilters {...defaultProps} />);

      expect(screen.getByText('Filters')).toBeInTheDocument();
    });

    it('shows filter count when filters active', () => {
      const activeFilters = { action: 'user_login', status: 'success' };
      render(<AuditLogFilters {...defaultProps} filters={activeFilters} />);

      expect(screen.getByText('2')).toBeInTheDocument();
    });

    it('shows Clear All button when filters active', () => {
      const activeFilters = { action: 'user_login' };
      render(<AuditLogFilters {...defaultProps} filters={activeFilters} />);

      expect(screen.getByText('Clear All')).toBeInTheDocument();
    });

    it('hides Clear All button when no filters', () => {
      render(<AuditLogFilters {...defaultProps} />);

      expect(screen.queryByText('Clear All')).not.toBeInTheDocument();
    });

    it('calls onClearFilters when Clear All clicked', () => {
      const onClearFilters = jest.fn();
      const activeFilters = { action: 'user_login' };
      render(<AuditLogFilters {...defaultProps} filters={activeFilters} onClearFilters={onClearFilters} />);

      fireEvent.click(screen.getByText('Clear All'));

      expect(onClearFilters).toHaveBeenCalled();
    });
  });

  describe('quick filters', () => {
    it('shows Failed Logins quick filter', () => {
      render(<AuditLogFilters {...defaultProps} />);

      expect(screen.getByText('Failed Logins')).toBeInTheDocument();
    });

    it('shows Errors quick filter', () => {
      render(<AuditLogFilters {...defaultProps} />);

      expect(screen.getByText('Errors')).toBeInTheDocument();
    });

    it('shows Admin Actions quick filter', () => {
      render(<AuditLogFilters {...defaultProps} />);

      expect(screen.getByText('Admin Actions')).toBeInTheDocument();
    });

    it('shows Last 24h quick filter', () => {
      render(<AuditLogFilters {...defaultProps} />);

      expect(screen.getByText('Last 24h')).toBeInTheDocument();
    });

    it('applies Failed Logins filter on click', () => {
      const onFiltersChange = jest.fn();
      render(<AuditLogFilters {...defaultProps} onFiltersChange={onFiltersChange} />);

      fireEvent.click(screen.getByText('Failed Logins'));

      expect(onFiltersChange).toHaveBeenCalledWith(expect.objectContaining({
        action: 'login_failed'
      }));
    });

    it('applies Errors filter on click', () => {
      const onFiltersChange = jest.fn();
      render(<AuditLogFilters {...defaultProps} onFiltersChange={onFiltersChange} />);

      fireEvent.click(screen.getByText('Errors'));

      expect(onFiltersChange).toHaveBeenCalledWith(expect.objectContaining({
        status: 'error'
      }));
    });

    it('applies Admin Actions filter on click', () => {
      const onFiltersChange = jest.fn();
      render(<AuditLogFilters {...defaultProps} onFiltersChange={onFiltersChange} />);

      fireEvent.click(screen.getByText('Admin Actions'));

      expect(onFiltersChange).toHaveBeenCalledWith(expect.objectContaining({
        source: 'admin_panel'
      }));
    });

    it('highlights active quick filter', () => {
      const activeFilters = { action: 'login_failed' };
      render(<AuditLogFilters {...defaultProps} filters={activeFilters} />);

      const failedLoginsButton = screen.getByText('Failed Logins').closest('button');
      expect(failedLoginsButton).toHaveClass('bg-theme-error');
    });
  });

  describe('expanded filters', () => {
    it('shows expanded filters when toggle clicked', () => {
      render(<AuditLogFilters {...defaultProps} />);

      // Click the expand/collapse button (RefreshCw icon)
      const toggleButtons = screen.getAllByRole('button');
      const expandButton = toggleButtons.find(btn =>
        btn.querySelector('.lucide-refresh-cw')
      );

      if (expandButton) {
        fireEvent.click(expandButton);
      }

      expect(screen.getByText('User Email')).toBeInTheDocument();
    });

    it('shows date range inputs in expanded mode', () => {
      render(<AuditLogFilters {...defaultProps} />);

      const toggleButtons = screen.getAllByRole('button');
      const expandButton = toggleButtons.find(btn =>
        btn.querySelector('.lucide-refresh-cw')
      );

      if (expandButton) {
        fireEvent.click(expandButton);
      }

      expect(screen.getByText('From Date')).toBeInTheDocument();
      expect(screen.getByText('To Date')).toBeInTheDocument();
    });

    it('shows Action select in expanded mode', () => {
      render(<AuditLogFilters {...defaultProps} />);

      const toggleButtons = screen.getAllByRole('button');
      const expandButton = toggleButtons.find(btn =>
        btn.querySelector('.lucide-refresh-cw')
      );

      if (expandButton) {
        fireEvent.click(expandButton);
      }

      expect(screen.getByText('Action')).toBeInTheDocument();
    });

    it('shows Source select in expanded mode', () => {
      render(<AuditLogFilters {...defaultProps} />);

      const toggleButtons = screen.getAllByRole('button');
      const expandButton = toggleButtons.find(btn =>
        btn.querySelector('.lucide-refresh-cw')
      );

      if (expandButton) {
        fireEvent.click(expandButton);
      }

      expect(screen.getByText('Source')).toBeInTheDocument();
    });

    it('shows Resource Type select in expanded mode', () => {
      render(<AuditLogFilters {...defaultProps} />);

      const toggleButtons = screen.getAllByRole('button');
      const expandButton = toggleButtons.find(btn =>
        btn.querySelector('.lucide-refresh-cw')
      );

      if (expandButton) {
        fireEvent.click(expandButton);
      }

      expect(screen.getByText('Resource Type')).toBeInTheDocument();
    });

    it('shows Status select in expanded mode', () => {
      render(<AuditLogFilters {...defaultProps} />);

      const toggleButtons = screen.getAllByRole('button');
      const expandButton = toggleButtons.find(btn =>
        btn.querySelector('.lucide-refresh-cw')
      );

      if (expandButton) {
        fireEvent.click(expandButton);
      }

      // Multiple "Status" labels may exist
      const statusLabels = screen.getAllByText('Status');
      expect(statusLabels.length).toBeGreaterThan(0);
    });

    it('shows Account Name input in expanded mode', () => {
      render(<AuditLogFilters {...defaultProps} />);

      const toggleButtons = screen.getAllByRole('button');
      const expandButton = toggleButtons.find(btn =>
        btn.querySelector('.lucide-refresh-cw')
      );

      if (expandButton) {
        fireEvent.click(expandButton);
      }

      expect(screen.getByText('Account Name')).toBeInTheDocument();
    });

    it('shows IP Address input in expanded mode', () => {
      render(<AuditLogFilters {...defaultProps} />);

      const toggleButtons = screen.getAllByRole('button');
      const expandButton = toggleButtons.find(btn =>
        btn.querySelector('.lucide-refresh-cw')
      );

      if (expandButton) {
        fireEvent.click(expandButton);
      }

      expect(screen.getByText('IP Address')).toBeInTheDocument();
    });
  });

  describe('filter changes', () => {
    it('calls onFiltersChange when action select changes', () => {
      const onFiltersChange = jest.fn();
      render(<AuditLogFilters {...defaultProps} onFiltersChange={onFiltersChange} />);

      // Expand filters first
      const toggleButtons = screen.getAllByRole('button');
      const expandButton = toggleButtons.find(btn =>
        btn.querySelector('.lucide-refresh-cw')
      );

      if (expandButton) {
        fireEvent.click(expandButton);
      }

      const actionSelect = screen.getAllByRole('combobox')[0];
      fireEvent.change(actionSelect, { target: { value: 'user_login' } });

      expect(onFiltersChange).toHaveBeenCalled();
    });

    it('calls onFiltersChange when user email changes', () => {
      const onFiltersChange = jest.fn();
      render(<AuditLogFilters {...defaultProps} onFiltersChange={onFiltersChange} />);

      // Expand filters first
      const toggleButtons = screen.getAllByRole('button');
      const expandButton = toggleButtons.find(btn =>
        btn.querySelector('.lucide-refresh-cw')
      );

      if (expandButton) {
        fireEvent.click(expandButton);
      }

      const emailInput = screen.getByPlaceholderText('Search by user email...');
      fireEvent.change(emailInput, { target: { value: 'test@example.com' } });

      expect(onFiltersChange).toHaveBeenCalledWith(expect.objectContaining({
        user_email: 'test@example.com'
      }));
    });
  });

  describe('active filters display', () => {
    it('shows active filter badges', () => {
      const activeFilters = { action: 'user_login', status: 'success' };
      render(<AuditLogFilters {...defaultProps} filters={activeFilters} />);

      expect(screen.getByText('Action:')).toBeInTheDocument();
      expect(screen.getByText('user_login')).toBeInTheDocument();
    });

    it('allows removing individual filter', () => {
      const onFiltersChange = jest.fn();
      const activeFilters = { action: 'user_login' };
      render(<AuditLogFilters {...defaultProps} filters={activeFilters} onFiltersChange={onFiltersChange} />);

      // Find the X button next to the active filter
      const filterBadge = screen.getByText('user_login').closest('div');
      const removeButton = filterBadge?.querySelector('button');

      if (removeButton) {
        fireEvent.click(removeButton);
      }

      expect(onFiltersChange).toHaveBeenCalledWith(expect.objectContaining({
        action: undefined
      }));
    });
  });

  describe('select options', () => {
    it('shows All Actions option', () => {
      render(<AuditLogFilters {...defaultProps} />);

      // Expand filters first
      const toggleButtons = screen.getAllByRole('button');
      const expandButton = toggleButtons.find(btn =>
        btn.querySelector('.lucide-refresh-cw')
      );

      if (expandButton) {
        fireEvent.click(expandButton);
      }

      expect(screen.getByText('All Actions')).toBeInTheDocument();
    });

    it('shows All Sources option', () => {
      render(<AuditLogFilters {...defaultProps} />);

      // Expand filters first
      const toggleButtons = screen.getAllByRole('button');
      const expandButton = toggleButtons.find(btn =>
        btn.querySelector('.lucide-refresh-cw')
      );

      if (expandButton) {
        fireEvent.click(expandButton);
      }

      expect(screen.getByText('All Sources')).toBeInTheDocument();
    });

    it('shows All Resources option', () => {
      render(<AuditLogFilters {...defaultProps} />);

      // Expand filters first
      const toggleButtons = screen.getAllByRole('button');
      const expandButton = toggleButtons.find(btn =>
        btn.querySelector('.lucide-refresh-cw')
      );

      if (expandButton) {
        fireEvent.click(expandButton);
      }

      expect(screen.getByText('All Resources')).toBeInTheDocument();
    });

    it('shows All Statuses option', () => {
      render(<AuditLogFilters {...defaultProps} />);

      // Expand filters first
      const toggleButtons = screen.getAllByRole('button');
      const expandButton = toggleButtons.find(btn =>
        btn.querySelector('.lucide-refresh-cw')
      );

      if (expandButton) {
        fireEvent.click(expandButton);
      }

      expect(screen.getByText('All Statuses')).toBeInTheDocument();
    });
  });
});
