/**
 * Credit card form with validation using existing form utilities
 */

import { 
  AlertCircle,
  Calendar,
  CreditCard, 
  Lock, 
  MapPin,
  User
} from 'lucide-react';

import { useDispatch } from 'react-redux';

import { useForm } from '@/shared/hooks/useForm';
import type { AppDispatch } from '@/shared/services';
import { addNotification } from '@/shared/services/slices/uiSlice';

// Credit card form data interface
interface CreditCardFormData {
  cardholderName: string;
  cardNumber: string;
  expiryMonth: string;
  expiryYear: string;
  cvv: string;
  billingLine1: string;
  billingLine2?: string;
  billingCity: string;
  billingState: string;
  billingPostalCode: string;
  billingCountry: string;
  saveCard: boolean;
  setAsDefault: boolean;
}

// Props for the credit card form component
interface CreditCardFormProps {
  onSuccess?: (paymentMethodId: string) => void;
  onCancel?: () => void;
  requireBillingAddress?: boolean;
  allowSaveCard?: boolean;
  submitButtonText?: string;
}

// Card number formatting utility
const formatCardNumber = (value: string): string => {
  const digits = value.replace(/\D/g, '');
  const groups = [];
  
  for (let i = 0; i < digits.length && i < 16; i += 4) {
    groups.push(digits.substring(i, i + 4));
  }
  
  return groups.join(' ');
};


// Luhn algorithm for card validation
const isValidCardNumber = (cardNumber: string): boolean => {
  const digits = cardNumber.replace(/\D/g, '');
  
  if (digits.length < 13 || digits.length > 19) return false;
  
  let sum = 0;
  let isEven = false;
  
  for (let i = digits.length - 1; i >= 0; i--) {
    let digit = parseInt(digits.charAt(i));
    
    if (isEven) {
      digit *= 2;
      if (digit > 9) digit -= 9;
    }
    
    sum += digit;
    isEven = !isEven;
  }
  
  return sum % 10 === 0;
};

export const CreditCardForm: React.FC<CreditCardFormProps> = ({
  onSuccess,
  onCancel,
  requireBillingAddress = true,
  allowSaveCard = true,
  submitButtonText = 'Add Payment Method'
}) => {
  const dispatch = useDispatch<AppDispatch>();
  
  const initialValues: CreditCardFormData = {
    cardholderName: '',
    cardNumber: '',
    expiryMonth: '',
    expiryYear: '',
    cvv: '',
    billingLine1: '',
    billingLine2: '',
    billingCity: '',
    billingState: '',
    billingPostalCode: '',
    billingCountry: 'US',
    saveCard: true,
    setAsDefault: false
  };

  const validationRules = {
    cardholderName: {
      required: true,
      minLength: 2,
      maxLength: 100
    },
    cardNumber: {
      required: true,
      custom: (value: unknown) => {
        if (!value || typeof value !== 'string') return null;
        const digits = value.replace(/\D/g, '');
        if (digits.length < 13 || digits.length > 19) {
          return 'Card number must be 13-19 digits';
        }
        if (!isValidCardNumber(digits)) {
          return 'Please enter a valid card number';
        }
        return null;
      }
    },
    expiryMonth: {
      required: true,
      custom: (value: unknown) => {
        if (!value || typeof value !== 'string') return null;
        const month = parseInt(value);
        if (month < 1 || month > 12) {
          return 'Please enter a valid month (01-12)';
        }
        return null;
      }
    },
    expiryYear: {
      required: true,
      custom: (value: unknown) => {
        if (!value || typeof value !== 'string') return null;
        const year = parseInt(value);
        const currentYear = new Date().getFullYear();
        if (year < currentYear || year > currentYear + 20) {
          return 'Please enter a valid expiry year';
        }
        return null;
      }
    },
    cvv: {
      required: true,
      custom: (value: unknown) => {
        if (!value || typeof value !== 'string') return null;
        if (!/^\d{3,4}$/.test(value)) {
          return 'CVV must be 3 or 4 digits';
        }
        return null;
      }
    }
  };

  if (requireBillingAddress) {
    Object.assign(validationRules, {
      billingLine1: { required: true, maxLength: 100 },
      billingCity: { required: true, maxLength: 50 },
      billingState: { required: true, maxLength: 50 },
      billingPostalCode: { required: true, maxLength: 20 },
      billingCountry: { required: true }
    });
  }

  const form = useForm({
    initialValues,
    validationRules,
    onSubmit: async (_values) => {
      try {
        // Here you would integrate with your payment processor (Stripe, etc.)
        // For now, we'll simulate a successful payment method creation
        const paymentMethodId = 'pm_' + Math.random().toString(36).substr(2, 9);
        
        dispatch(addNotification({
          message: 'Payment method added successfully!',
          type: 'success'
        }));
        
        onSuccess?.(paymentMethodId);
      } catch (error) {
        dispatch(addNotification({
          message: 'Failed to add payment method. Please try again.',
          type: 'error'
        }));
        throw error;
      }
    }
  });

  // Handle card number changes with formatting
  const handleCardNumberChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const formatted = formatCardNumber(e.target.value);
    form.setValue('cardNumber', formatted);
  };

  const currentYear = new Date().getFullYear();
  const years = Array.from({ length: 21 }, (_, i) => currentYear + i);
  const months = Array.from({ length: 12 }, (_, i) => ({
    value: String(i + 1).padStart(2, '0'),
    label: String(i + 1).padStart(2, '0')
  }));

  return (
    <div className="bg-theme-surface rounded-lg p-6 border border-theme">
      <div className="flex items-center space-x-2 mb-6">
        <CreditCard className="w-6 h-6 text-theme-primary" />
        <h3 className="text-lg font-semibold text-theme-primary">Payment Information</h3>
      </div>

      <form onSubmit={form.handleSubmit} className="space-y-6">
        {/* Cardholder Name */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-2">
            <User className="inline w-4 h-4 mr-1" />
            Cardholder Name
          </label>
          <input
            type="text"
            {...form.getFieldProps('cardholderName')}
            className="w-full px-3 py-2 border border-theme rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 bg-theme-surface text-theme-primary"
            placeholder="Enter cardholder name"
          />
          {form.errors.cardholderName && (
            <p className="mt-1 text-sm text-theme-danger flex items-center">
              <AlertCircle className="w-4 h-4 mr-1" />
              {form.errors.cardholderName}
            </p>
          )}
        </div>

        {/* Card Number */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-2">
            <CreditCard className="inline w-4 h-4 mr-1" />
            Card Number
          </label>
          <input
            type="text"
            value={form.values.cardNumber}
            onChange={handleCardNumberChange}
            onBlur={form.handleBlur}
            name="cardNumber"
            maxLength={19}
            className="w-full px-3 py-2 border border-theme rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 bg-theme-surface text-theme-primary"
            placeholder="1234 5678 9012 3456"
          />
          {form.errors.cardNumber && (
            <p className="mt-1 text-sm text-theme-danger flex items-center">
              <AlertCircle className="w-4 h-4 mr-1" />
              {form.errors.cardNumber}
            </p>
          )}
        </div>

        {/* Expiry and CVV */}
        <div className="grid grid-cols-3 gap-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              <Calendar className="inline w-4 h-4 mr-1" />
              Month
            </label>
            <select
              {...form.getFieldProps('expiryMonth')}
              className="w-full px-3 py-2 border border-theme rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 bg-theme-surface text-theme-primary"
            >
              <option value="">MM</option>
              {months.map(month => (
                <option key={month.value} value={month.value}>
                  {month.label}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Year
            </label>
            <select
              {...form.getFieldProps('expiryYear')}
              className="w-full px-3 py-2 border border-theme rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 bg-theme-surface text-theme-primary"
            >
              <option value="">YYYY</option>
              {years.map(year => (
                <option key={year} value={year}>
                  {year}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              <Lock className="inline w-4 h-4 mr-1" />
              CVV
            </label>
            <input
              type="text"
              {...form.getFieldProps('cvv')}
              maxLength={4}
              className="w-full px-3 py-2 border border-theme rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 bg-theme-surface text-theme-primary"
              placeholder="123"
            />
          </div>
        </div>

        {/* Billing Address */}
        {requireBillingAddress && (
          <div className="space-y-4">
            <div className="flex items-center space-x-2">
              <MapPin className="w-5 h-5 text-theme-primary" />
              <h4 className="text-md font-medium text-theme-primary">Billing Address</h4>
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Address Line 1
              </label>
              <input
                type="text"
                {...form.getFieldProps('billingLine1')}
                className="w-full px-3 py-2 border border-theme rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 bg-theme-surface text-theme-primary"
                placeholder="123 Main Street"
              />
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  City
                </label>
                <input
                  type="text"
                  {...form.getFieldProps('billingCity')}
                  className="w-full px-3 py-2 border border-theme rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 bg-theme-surface text-theme-primary"
                  placeholder="City"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  State
                </label>
                <input
                  type="text"
                  {...form.getFieldProps('billingState')}
                  className="w-full px-3 py-2 border border-theme rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 bg-theme-surface text-theme-primary"
                  placeholder="State"
                />
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Postal Code
              </label>
              <input
                type="text"
                {...form.getFieldProps('billingPostalCode')}
                className="w-full px-3 py-2 border border-theme rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 bg-theme-surface text-theme-primary"
                placeholder="12345"
              />
            </div>
          </div>
        )}

        {/* Save Card Options */}
        {allowSaveCard && (
          <div className="space-y-3">
            <div className="flex items-center">
              <input
                type="checkbox"
                {...form.getFieldProps('saveCard')}
                className="h-4 w-4 text-theme-info focus:ring-blue-500 border-theme rounded"
              />
              <label className="ml-2 block text-sm text-theme-primary">
                Save this card for future payments
              </label>
            </div>

            {form.values.saveCard && (
              <div className="flex items-center ml-6">
                <input
                  type="checkbox"
                  {...form.getFieldProps('setAsDefault')}
                  className="h-4 w-4 text-theme-info focus:ring-blue-500 border-theme rounded"
                />
                <label className="ml-2 block text-sm text-theme-primary">
                  Set as default payment method
                </label>
              </div>
            )}
          </div>
        )}

        {/* Form Actions */}
        <div className="flex space-x-4">
          <button
            type="submit"
            disabled={form.isSubmitting}
            className="flex-1 bg-theme-info text-white py-2 px-4 rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {form.isSubmitting ? 'Processing...' : submitButtonText}
          </button>
          
          {onCancel && (
            <button
              type="button"
              onClick={onCancel}
              className="flex-1 bg-theme-surface border border-theme text-theme-primary py-2 px-4 rounded-md hover:bg-theme-surface/80 focus:outline-none focus:ring-2 focus:ring-blue-500"
            >
              Cancel
            </button>
          )}
        </div>
      </form>
    </div>
  );
};