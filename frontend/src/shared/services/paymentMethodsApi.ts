import { api } from '@/shared/services/api';

export interface PaymentMethod {
  id: string;
  type: 'card' | 'bank_account' | 'paypal';
  provider: 'stripe' | 'paypal';
  is_default: boolean;
  created_at: string;
  last_used_at?: string;
  
  // Card-specific fields
  card?: {
    brand: string;
    last4: string;
    exp_month: number;
    exp_year: number;
    funding: string;
    country: string;
  };
  
  // Bank account fields
  bank_account?: {
    account_holder_type: string;
    bank_name: string;
    last4: string;
    routing_number: string;
    country: string;
  };
  
  // PayPal fields
  paypal?: {
    email: string;
    payer_id: string;
  };
}

export interface SetupIntent {
  id: string;
  client_secret: string;
  status: string;
  usage: string;
  payment_method_types: string[];
}

export interface PaymentMethodResponse {
  success: boolean;
  payment_method?: PaymentMethod;
  setup_intent?: SetupIntent;
  message?: string;
  error?: string;
}

export interface PaymentMethodsListResponse {
  success: boolean;
  payment_methods: PaymentMethod[];
  default_payment_method_id?: string;
  message?: string;
  error?: string;
}

export interface PaymentMethodSetupResponse {
  success: boolean;
  setup_intent: SetupIntent;
  message?: string;
  error?: string;
}

export const paymentMethodsApi = {
  // Get all payment methods for current account
  async getPaymentMethods(): Promise<PaymentMethodsListResponse> {
    const response = await api.get('/api/v1/payment_methods');
    return response.data;
  },

  // Get a specific payment method
  async getPaymentMethod(id: string): Promise<PaymentMethodResponse> {
    const response = await api.get(`/api/v1/payment_methods/${id}`);
    return response.data;
  },

  // Create setup intent for adding new payment method
  async createSetupIntent(type: 'card' | 'bank_account' = 'card'): Promise<PaymentMethodSetupResponse> {
    const response = await api.post('/api/v1/payment_methods/setup_intent', {
      payment_method_type: type
    });
    return response.data;
  },

  // Confirm payment method after client-side setup
  async confirmPaymentMethod(paymentMethodId: string, setupIntentId: string): Promise<PaymentMethodResponse> {
    const response = await api.post('/api/v1/payment_methods/confirm', {
      payment_method_id: paymentMethodId,
      setup_intent_id: setupIntentId
    });
    return response.data;
  },

  // Set default payment method
  async setDefaultPaymentMethod(id: string): Promise<PaymentMethodResponse> {
    const response = await api.put(`/api/v1/payment_methods/${id}/set_default`);
    return response.data;
  },

  // Delete a payment method
  async deletePaymentMethod(id: string): Promise<{ success: boolean; message?: string; error?: string }> {
    const response = await api.delete(`/api/v1/payment_methods/${id}`);
    return response.data;
  },

  // Utility methods
  getPaymentMethodDisplay(paymentMethod: PaymentMethod): string {
    switch (paymentMethod.type) {
      case 'card':
        if (paymentMethod.card) {
          return `${paymentMethod.card.brand.toUpperCase()} •••• ${paymentMethod.card.last4}`;
        }
        break;
      case 'bank_account':
        if (paymentMethod.bank_account) {
          return `${paymentMethod.bank_account.bank_name} •••• ${paymentMethod.bank_account.last4}`;
        }
        break;
      case 'paypal':
        if (paymentMethod.paypal) {
          return `PayPal (${paymentMethod.paypal.email})`;
        }
        break;
    }
    return 'Unknown Payment Method';
  },

  getCardBrandIcon(brand: string): string {
    const brandIcons: { [key: string]: string } = {
      'visa': '💳',
      'mastercard': '💳',
      'amex': '💳',
      'discover': '💳',
      'diners': '💳',
      'jcb': '💳',
      'unionpay': '💳'
    };
    return brandIcons[brand.toLowerCase()] || '💳';
  },

  isExpiredCard(paymentMethod: PaymentMethod): boolean {
    if (paymentMethod.type !== 'card' || !paymentMethod.card) {
      return false;
    }
    
    const now = new Date();
    const expiry = new Date(paymentMethod.card.exp_year, paymentMethod.card.exp_month - 1);
    return expiry < now;
  },

  formatExpiryDate(month: number, year: number): string {
    return `${month.toString().padStart(2, '0')}/${year.toString().slice(-2)}`;
  }
};

export default paymentMethodsApi;