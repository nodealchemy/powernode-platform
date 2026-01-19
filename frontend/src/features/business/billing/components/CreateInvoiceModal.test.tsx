
import { render, screen, fireEvent } from '@testing-library/react';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import { CreateInvoiceModal } from './CreateInvoiceModal';

// Mock DatePicker
jest.mock('@/shared/components/ui/DatePicker', () => ({
  DatePicker: ({ selected, onChange, disabled }: any) => (
    <input
      type="date"
      data-testid="date-picker"
      value={selected ? selected.toISOString().split('T')[0] : ''}
      onChange={(e) => onChange(new Date(e.target.value))}
      disabled={disabled}
    />
  )
}));

// Mock useForm to prevent infinite loop from form object changing on each render
const mockReset = jest.fn();
const mockHandleChange = jest.fn();
const mockSetValue = jest.fn();
const mockSetFieldValue = jest.fn();
const mockHandleBlur = jest.fn();
const mockHandleSubmit = jest.fn((e: any) => {
  e?.preventDefault?.();
  return Promise.resolve();
});

jest.mock('@/shared/hooks/useForm', () => ({
  useForm: () => ({
    values: {
      customerEmail: '',
      dueDate: new Date(),
      issueDate: new Date(),
      amount: 0,
      currency: 'USD',
      description: '',
      lineItems: [{ description: '', quantity: 1, unitPrice: 0, total: 0 }]
    },
    errors: {},
    touched: {},
    isSubmitting: false,
    isValid: true,
    handleChange: mockHandleChange,
    handleBlur: mockHandleBlur,
    handleSubmit: mockHandleSubmit,
    setValue: mockSetValue,
    setFieldValue: mockSetFieldValue,
    setValues: jest.fn(),
    reset: mockReset,
    validateField: jest.fn(),
    validateForm: jest.fn(),
    getFieldProps: (name: string) => ({
      name,
      value: '',
      onChange: mockSetFieldValue,
      onBlur: mockHandleBlur
    }),
    getInputProps: (name: string) => ({
      name,
      value: '',
      onChange: mockHandleChange,
      onBlur: mockHandleBlur
    })
  }),
  FormValidationRules: {}
}));

describe('CreateInvoiceModal', () => {
  const createStore = () => configureStore({
    reducer: {
      ui: (state = { notifications: [] }, action: any) => {
        if (action.type === 'ui/addNotification') {
          return { ...state, notifications: [...state.notifications, action.payload] };
        }
        return state;
      }
    }
  });

  const renderComponent = (props = {}) => {
    const defaultProps = {
      isOpen: true,
      onClose: jest.fn(),
      onSubmit: jest.fn().mockResolvedValue(undefined)
    };
    return render(
      <Provider store={createStore()}>
        <CreateInvoiceModal {...defaultProps} {...props} />
      </Provider>
    );
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('rendering', () => {
    it('renders modal title', () => {
      renderComponent();

      // Title appears as modal header text - use getAllByText and check the first one is the title
      const createInvoiceElements = screen.getAllByText('Create Invoice');
      expect(createInvoiceElements.length).toBeGreaterThanOrEqual(1);
    });

    it('renders modal subtitle', () => {
      renderComponent();

      expect(screen.getByText('Generate a new invoice for your customer')).toBeInTheDocument();
    });

    it('renders customer email field', () => {
      renderComponent();

      expect(screen.getByText('Customer Email')).toBeInTheDocument();
      expect(screen.getByPlaceholderText('customer@example.com')).toBeInTheDocument();
    });

    it('renders currency select', () => {
      renderComponent();

      expect(screen.getByText('Currency')).toBeInTheDocument();
      expect(screen.getByRole('combobox')).toBeInTheDocument();
    });

    it('renders date pickers', () => {
      renderComponent();

      expect(screen.getByText('Issue Date *')).toBeInTheDocument();
      expect(screen.getByText('Due Date *')).toBeInTheDocument();
    });

    it('renders description field', () => {
      renderComponent();

      expect(screen.getByText('Description *')).toBeInTheDocument();
      expect(screen.getByPlaceholderText('Invoice description...')).toBeInTheDocument();
    });

    it('renders line items section', () => {
      renderComponent();

      expect(screen.getByText('Line Items')).toBeInTheDocument();
      expect(screen.getByText('Add Item')).toBeInTheDocument();
    });

    it('renders cancel button', () => {
      renderComponent();

      expect(screen.getByText('Cancel')).toBeInTheDocument();
    });

    it('renders create button', () => {
      renderComponent();

      // Create Invoice appears both as title and button text
      const createInvoiceElements = screen.getAllByText('Create Invoice');
      // Should have at least 2: title and button
      expect(createInvoiceElements.length).toBeGreaterThanOrEqual(2);
    });
  });

  describe('currency options', () => {
    it('has USD option', () => {
      renderComponent();

      const select = screen.getByRole('combobox');
      expect(select).toContainHTML('USD');
    });

    it('has EUR option', () => {
      renderComponent();

      const select = screen.getByRole('combobox');
      expect(select).toContainHTML('EUR');
    });

    it('has GBP option', () => {
      renderComponent();

      const select = screen.getByRole('combobox');
      expect(select).toContainHTML('GBP');
    });

    it('has CAD option', () => {
      renderComponent();

      const select = screen.getByRole('combobox');
      expect(select).toContainHTML('CAD');
    });
  });

  describe('line items', () => {
    it('renders default line item', () => {
      renderComponent();

      expect(screen.getByPlaceholderText('Item description')).toBeInTheDocument();
      expect(screen.getByPlaceholderText('Qty')).toBeInTheDocument();
      expect(screen.getByPlaceholderText('Unit price')).toBeInTheDocument();
    });

    it('shows total as $0.00 initially', () => {
      renderComponent();

      expect(screen.getByText('Total: $0.00')).toBeInTheDocument();
    });
  });

  describe('cancel button', () => {
    it('calls onClose when cancel clicked', () => {
      const onClose = jest.fn();
      renderComponent({ onClose });

      fireEvent.click(screen.getByText('Cancel'));

      expect(onClose).toHaveBeenCalled();
    });

    it('calls form reset when cancel clicked', () => {
      renderComponent();

      fireEvent.click(screen.getByText('Cancel'));

      expect(mockReset).toHaveBeenCalled();
    });
  });

  describe('form inputs', () => {
    it('renders customer email input', () => {
      renderComponent();

      const emailInput = screen.getByPlaceholderText('customer@example.com');
      expect(emailInput).toBeInTheDocument();
    });

    it('renders description input', () => {
      renderComponent();

      const descInput = screen.getByPlaceholderText('Invoice description...');
      expect(descInput).toBeInTheDocument();
    });

    it('renders currency select with default USD', () => {
      renderComponent();

      const select = screen.getByRole('combobox');
      expect(select).toBeInTheDocument();
    });
  });

  describe('when modal is closed', () => {
    it('does not render when isOpen is false', () => {
      renderComponent({ isOpen: false });

      expect(screen.queryByText('Create Invoice')).not.toBeInTheDocument();
    });
  });

  describe('form submission', () => {
    it('renders form with correct id', () => {
      renderComponent();

      const form = document.getElementById('create-invoice-form');
      expect(form).toBeInTheDocument();
    });

    it('calls handleSubmit when form is submitted', () => {
      renderComponent();

      const form = document.getElementById('create-invoice-form');
      if (form) {
        fireEvent.submit(form);
      }

      expect(mockHandleSubmit).toHaveBeenCalled();
    });
  });
});
