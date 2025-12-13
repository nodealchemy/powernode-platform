
import { render, screen, fireEvent } from '@testing-library/react';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import { CreditCardForm } from './CreditCardForm';

describe('CreditCardForm', () => {
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
    return render(
      <Provider store={createStore()}>
        <CreditCardForm {...props} />
      </Provider>
    );
  };

  describe('rendering', () => {
    it('renders form header', () => {
      renderComponent();

      expect(screen.getByText('Payment Information')).toBeInTheDocument();
    });

    it('renders cardholder name field', () => {
      renderComponent();

      expect(screen.getByText('Cardholder Name')).toBeInTheDocument();
      expect(screen.getByPlaceholderText('Enter cardholder name')).toBeInTheDocument();
    });

    it('renders card number field', () => {
      renderComponent();

      expect(screen.getByText('Card Number')).toBeInTheDocument();
      expect(screen.getByPlaceholderText('1234 5678 9012 3456')).toBeInTheDocument();
    });

    it('renders expiry date fields', () => {
      renderComponent();

      expect(screen.getByText('Month')).toBeInTheDocument();
      expect(screen.getByText('Year')).toBeInTheDocument();
    });

    it('renders CVV field', () => {
      renderComponent();

      expect(screen.getByText('CVV')).toBeInTheDocument();
      expect(screen.getByPlaceholderText('123')).toBeInTheDocument();
    });

    it('renders submit button with default text', () => {
      renderComponent();

      expect(screen.getByText('Add Payment Method')).toBeInTheDocument();
    });

    it('renders submit button with custom text', () => {
      renderComponent({ submitButtonText: 'Save Card' });

      expect(screen.getByText('Save Card')).toBeInTheDocument();
    });
  });

  describe('billing address', () => {
    it('shows billing address fields by default', () => {
      renderComponent();

      expect(screen.getByText('Billing Address')).toBeInTheDocument();
      expect(screen.getByPlaceholderText('123 Main Street')).toBeInTheDocument();
      expect(screen.getByPlaceholderText('City')).toBeInTheDocument();
      expect(screen.getByPlaceholderText('State')).toBeInTheDocument();
      expect(screen.getByPlaceholderText('12345')).toBeInTheDocument();
    });

    it('hides billing address when not required', () => {
      renderComponent({ requireBillingAddress: false });

      expect(screen.queryByText('Billing Address')).not.toBeInTheDocument();
    });
  });

  describe('save card options', () => {
    it('shows save card checkbox by default', () => {
      renderComponent();

      expect(screen.getByText('Save this card for future payments')).toBeInTheDocument();
    });

    it('hides save card checkbox when not allowed', () => {
      renderComponent({ allowSaveCard: false });

      expect(screen.queryByText('Save this card for future payments')).not.toBeInTheDocument();
    });

    it('shows set as default option when save card is checked', () => {
      renderComponent();

      // Save card is checked by default
      expect(screen.getByText('Set as default payment method')).toBeInTheDocument();
    });
  });

  describe('cancel button', () => {
    it('renders cancel button when onCancel provided', () => {
      const onCancel = jest.fn();
      renderComponent({ onCancel });

      expect(screen.getByText('Cancel')).toBeInTheDocument();
    });

    it('does not render cancel button when onCancel not provided', () => {
      renderComponent();

      expect(screen.queryByText('Cancel')).not.toBeInTheDocument();
    });

    it('calls onCancel when cancel button clicked', () => {
      const onCancel = jest.fn();
      renderComponent({ onCancel });

      fireEvent.click(screen.getByText('Cancel'));

      expect(onCancel).toHaveBeenCalled();
    });
  });

  describe('input fields', () => {
    it('allows entering cardholder name', () => {
      renderComponent();

      const input = screen.getByPlaceholderText('Enter cardholder name');
      fireEvent.change(input, { target: { value: 'John Doe' } });

      expect(input).toHaveValue('John Doe');
    });

    it('allows entering CVV', () => {
      renderComponent();

      const input = screen.getByPlaceholderText('123');
      fireEvent.change(input, { target: { value: '456' } });

      expect(input).toHaveValue('456');
    });

    it('has maxLength on card number field', () => {
      renderComponent();

      const input = screen.getByPlaceholderText('1234 5678 9012 3456');
      expect(input).toHaveAttribute('maxLength', '19');
    });

    it('has maxLength on CVV field', () => {
      renderComponent();

      const input = screen.getByPlaceholderText('123');
      expect(input).toHaveAttribute('maxLength', '4');
    });
  });

  describe('expiry date dropdowns', () => {
    it('has all 12 month options', () => {
      renderComponent();

      // Month select is the first combobox
      const selects = screen.getAllByRole('combobox');
      const monthSelect = selects[0];

      // Should have 12 months + placeholder option (13 total)
      expect(monthSelect.querySelectorAll('option').length).toBe(13);
    });

    it('has future year options', () => {
      renderComponent();

      const selects = screen.getAllByRole('combobox');
      const yearSelect = selects[1];
      const currentYear = new Date().getFullYear();

      // Should have options for current year
      expect(yearSelect.innerHTML).toContain(String(currentYear));
    });
  });
});
