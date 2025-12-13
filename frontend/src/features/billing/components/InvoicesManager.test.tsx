
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { InvoicesManager } from './InvoicesManager';

// Mock notifications hook
const mockShowNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    showNotification: mockShowNotification
  })
}));

// Mock formatters
jest.mock('@/shared/utils/formatters', () => ({
  formatCurrency: (amount: number, _currency?: string) => `$${amount.toFixed(2)}`
}));

// Mock status helpers
jest.mock('@/shared/utils/statusHelpers', () => ({
  getInvoiceStatusColor: (status: string) => {
    const colors: Record<string, string> = { paid: 'green', open: 'blue', overdue: 'red', draft: 'gray', void: 'gray' };
    return colors[status] || 'gray';
  },
  getInvoiceStatusText: (status: string) => status.charAt(0).toUpperCase() + status.slice(1)
}));

// Mock API
const mockGetInvoices = jest.fn();
const mockGetInvoiceStats = jest.fn();
const mockSendInvoice = jest.fn();
const mockVoidInvoice = jest.fn();
const mockRetryPayment = jest.fn();
const mockMarkAsPaid = jest.fn();
const mockDownloadPDF = jest.fn();

jest.mock('@/shared/services/invoicesApi', () => ({
  invoicesApi: {
    getInvoices: (...args: any[]) => mockGetInvoices(...args),
    getInvoiceStats: (...args: any[]) => mockGetInvoiceStats(...args),
    sendInvoice: (...args: any[]) => mockSendInvoice(...args),
    voidInvoice: (...args: any[]) => mockVoidInvoice(...args),
    retryPayment: (...args: any[]) => mockRetryPayment(...args),
    markAsPaid: (...args: any[]) => mockMarkAsPaid(...args),
    downloadPDF: (...args: any[]) => mockDownloadPDF(...args),
    isOverdue: (invoice: any) => invoice.status === 'overdue',
    getDaysOverdue: () => 5
  }
}));

describe('InvoicesManager', () => {
  const mockInvoices = [
    {
      id: 'inv-1',
      invoice_number: 'INV-001',
      customer: { name: 'John Doe', email: 'john@example.com' },
      total: 150.00,
      amount_remaining: 0,
      currency: 'USD',
      status: 'paid',
      issue_date: '2025-01-01',
      due_date: '2025-01-31'
    },
    {
      id: 'inv-2',
      invoice_number: 'INV-002',
      customer: { name: 'Jane Smith', email: 'jane@example.com' },
      total: 250.00,
      amount_remaining: 250.00,
      currency: 'USD',
      status: 'open',
      issue_date: '2025-01-10',
      due_date: '2025-02-10'
    },
    {
      id: 'inv-3',
      invoice_number: 'INV-003',
      customer: { name: 'Bob Wilson', email: 'bob@example.com' },
      total: 500.00,
      amount_remaining: 500.00,
      currency: 'USD',
      status: 'draft',
      issue_date: '2025-01-15',
      due_date: '2025-02-15'
    }
  ];

  const mockStats = {
    total_invoices: 10,
    outstanding_amount: 2500,
    overdue_amount: 500,
    payment_success_rate: 85.5
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetInvoices.mockResolvedValue({
      success: true,
      invoices: mockInvoices,
      pagination: { total_pages: 1, current_page: 1 }
    });
    mockGetInvoiceStats.mockResolvedValue(mockStats);
  });

  describe('loading state', () => {
    it('shows loading spinner while fetching invoices', () => {
      mockGetInvoices.mockImplementation(() => new Promise(() => {}));

      render(<InvoicesManager />);

      expect(document.querySelector('.flex.items-center.justify-center')).toBeInTheDocument();
    });
  });

  describe('empty state', () => {
    it('shows empty state when no invoices', async () => {
      mockGetInvoices.mockResolvedValue({
        success: true,
        invoices: [],
        pagination: { total_pages: 1, current_page: 1 }
      });

      render(<InvoicesManager />);

      await waitFor(() => {
        expect(screen.getByText('No Invoices Found')).toBeInTheDocument();
      });
      expect(screen.getByText('No invoices have been created yet.')).toBeInTheDocument();
    });

    it('shows search message when no results match', async () => {
      render(<InvoicesManager />);

      await waitFor(() => {
        expect(screen.getByText('INV-001')).toBeInTheDocument();
      });

      const searchInput = screen.getByPlaceholderText('Search invoices...');
      fireEvent.change(searchInput, { target: { value: 'nonexistent' } });

      expect(screen.getByText('No Invoices Found')).toBeInTheDocument();
      expect(screen.getByText('No invoices match your search criteria.')).toBeInTheDocument();
    });
  });

  describe('stats display', () => {
    it('shows stats cards when showStats is true', async () => {
      render(<InvoicesManager showStats={true} />);

      await waitFor(() => {
        expect(screen.getByText('Total Invoices')).toBeInTheDocument();
      });
      expect(screen.getByText('10')).toBeInTheDocument();
      expect(screen.getByText('Outstanding')).toBeInTheDocument();
      expect(screen.getByText('Overdue')).toBeInTheDocument();
      expect(screen.getByText('Success Rate')).toBeInTheDocument();
      expect(screen.getByText('85.5%')).toBeInTheDocument();
    });

    it('hides stats cards when showStats is false', async () => {
      render(<InvoicesManager showStats={false} />);

      await waitFor(() => {
        expect(screen.getByText('INV-001')).toBeInTheDocument();
      });

      expect(screen.queryByText('Total Invoices')).not.toBeInTheDocument();
    });
  });

  describe('invoices list', () => {
    it('displays invoices in table', async () => {
      render(<InvoicesManager />);

      await waitFor(() => {
        expect(screen.getByText('INV-001')).toBeInTheDocument();
      });
      expect(screen.getByText('INV-002')).toBeInTheDocument();
      expect(screen.getByText('INV-003')).toBeInTheDocument();
    });

    it('shows customer information', async () => {
      render(<InvoicesManager />);

      await waitFor(() => {
        expect(screen.getByText('John Doe')).toBeInTheDocument();
      });
      expect(screen.getByText('john@example.com')).toBeInTheDocument();
    });

    it('shows invoice amounts', async () => {
      render(<InvoicesManager />);

      await waitFor(() => {
        expect(screen.getByText('$150.00')).toBeInTheDocument();
      });
      expect(screen.getByText('$250.00')).toBeInTheDocument();
    });

    it('shows status badges', async () => {
      render(<InvoicesManager />);

      await waitFor(() => {
        expect(screen.getByText('Paid')).toBeInTheDocument();
      });
      expect(screen.getByText('Open')).toBeInTheDocument();
      expect(screen.getByText('Draft')).toBeInTheDocument();
    });
  });

  describe('search functionality', () => {
    it('filters invoices by invoice number', async () => {
      render(<InvoicesManager />);

      await waitFor(() => {
        expect(screen.getByText('INV-001')).toBeInTheDocument();
      });

      const searchInput = screen.getByPlaceholderText('Search invoices...');
      fireEvent.change(searchInput, { target: { value: 'INV-001' } });

      expect(screen.getByText('INV-001')).toBeInTheDocument();
      expect(screen.queryByText('INV-002')).not.toBeInTheDocument();
    });

    it('filters invoices by customer name', async () => {
      render(<InvoicesManager />);

      await waitFor(() => {
        expect(screen.getByText('INV-001')).toBeInTheDocument();
      });

      const searchInput = screen.getByPlaceholderText('Search invoices...');
      fireEvent.change(searchInput, { target: { value: 'Jane' } });

      expect(screen.queryByText('INV-001')).not.toBeInTheDocument();
      expect(screen.getByText('INV-002')).toBeInTheDocument();
    });
  });

  describe('filters panel', () => {
    it('toggles filters panel', async () => {
      render(<InvoicesManager showFilters={true} />);

      await waitFor(() => {
        expect(screen.getByText('Filters')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Filters'));

      // Status appears in multiple places (label, option, table header)
      const statusElements = screen.getAllByText('Status');
      expect(statusElements.length).toBeGreaterThan(1);
      expect(screen.getByText('Date Range')).toBeInTheDocument();
      expect(screen.getByText('Sort By')).toBeInTheDocument();
    });

    it('hides filters button when showFilters is false', async () => {
      render(<InvoicesManager showFilters={false} />);

      await waitFor(() => {
        expect(screen.getByText('INV-001')).toBeInTheDocument();
      });

      expect(screen.queryByText('Filters')).not.toBeInTheDocument();
    });
  });

  describe('actions', () => {
    it('sends draft invoice', async () => {
      mockSendInvoice.mockResolvedValue({ success: true, message: 'Invoice sent' });

      render(<InvoicesManager />);

      await waitFor(() => {
        expect(screen.getByText('INV-003')).toBeInTheDocument();
      });

      const sendButtons = screen.getAllByTitle('Send Invoice');
      fireEvent.click(sendButtons[0]);

      await waitFor(() => {
        expect(mockSendInvoice).toHaveBeenCalledWith('inv-3');
      });
    });

    it('voids invoice', async () => {
      mockVoidInvoice.mockResolvedValue({ success: true, message: 'Invoice voided' });

      render(<InvoicesManager />);

      await waitFor(() => {
        expect(screen.getByText('INV-003')).toBeInTheDocument();
      });

      const voidButtons = screen.getAllByTitle('Void Invoice');
      fireEvent.click(voidButtons[0]);

      await waitFor(() => {
        expect(mockVoidInvoice).toHaveBeenCalled();
      });
    });
  });

  describe('header', () => {
    it('displays title and description', async () => {
      render(<InvoicesManager />);

      await waitFor(() => {
        expect(screen.getByText('Invoices')).toBeInTheDocument();
      });
      expect(screen.getByText('Manage customer invoices and payments')).toBeInTheDocument();
    });
  });

  describe('table headers', () => {
    it('displays all column headers', async () => {
      render(<InvoicesManager />);

      await waitFor(() => {
        expect(screen.getByText('Invoice')).toBeInTheDocument();
      });
      expect(screen.getByText('Customer')).toBeInTheDocument();
      expect(screen.getByText('Amount')).toBeInTheDocument();
      expect(screen.getByText('Status')).toBeInTheDocument();
      expect(screen.getByText('Due Date')).toBeInTheDocument();
      expect(screen.getByText('Actions')).toBeInTheDocument();
    });
  });

  describe('error handling', () => {
    it('shows notification on API error', async () => {
      mockGetInvoices.mockResolvedValue({ success: false });

      render(<InvoicesManager />);

      await waitFor(() => {
        expect(mockShowNotification).toHaveBeenCalledWith('Failed to load invoices', 'error');
      });
    });

    it('shows notification on action error', async () => {
      mockSendInvoice.mockResolvedValue({ success: false, error: 'Send failed' });

      render(<InvoicesManager />);

      await waitFor(() => {
        expect(screen.getByText('INV-003')).toBeInTheDocument();
      });

      const sendButtons = screen.getAllByTitle('Send Invoice');
      fireEvent.click(sendButtons[0]);

      await waitFor(() => {
        expect(mockShowNotification).toHaveBeenCalledWith('Send failed', 'error');
      });
    });
  });
});
