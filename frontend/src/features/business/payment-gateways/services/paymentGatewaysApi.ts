import { api } from '@/shared/services/api';

export interface PaymentGatewayStatus {
  status: 'connected' | 'configured' | 'not_configured' | 'error' | 'authentication_failed' | 'partial' | 'unsupported';
  message: string;
  last_checked: string;
  account_id?: string;
}

export interface PaymentGatewayConfig {
  provider: string;
  name: string;
  enabled: boolean;
  test_mode: boolean;
  supported_methods: string[];
  publishable_key?: string;
  webhook_secret?: string;
  client_id?: string;
  client_secret?: string;
  environment?: 'sandbox' | 'production';
  // Presence indicators returned by the API
  publishable_key_present?: boolean;
  secret_key_present?: boolean;
  endpoint_secret_present?: boolean;
  webhook_tolerance?: number;
  client_id_present?: boolean;
  client_secret_present?: boolean;
  webhook_id_present?: boolean;
  mode?: 'sandbox' | 'live';
}

export interface PaymentGatewaysOverview {
  gateways: {
    stripe: PaymentGatewayConfig;
    paypal: PaymentGatewayConfig;
  };
  status: {
    stripe: PaymentGatewayStatus;
    paypal: PaymentGatewayStatus;
  };
  recent_transactions: PaymentTransaction[];
  statistics: GatewayStatistics;
}

export interface PaymentTransaction {
  id: string;
  invoice_id: string;
  amount: string;
  currency: string;
  status: string;
  payment_method: string;
  gateway_transaction_id?: string;
  created_at: string;
  processed_at?: string;
  gateway_fee: string;
  net_amount: string;
}

export interface WebhookEvent {
  id: string;
  event_type: string;
  status: string;
  payment_id?: string;
  external_id: string;
  processed_at?: string;
  created_at: string;
  error_message?: string;
}

export interface GatewayStatistics {
  stripe: GatewayStats;
  paypal: GatewayStats;
  overall: GatewayStats;
}

export interface GatewayStats {
  total_transactions: number;
  successful_transactions: number;
  failed_transactions: number;
  total_volume: number;
  total_fees?: number;
  success_rate: number;
  last_30_days: {
    transactions: number;
    volume: number;
  };
}

export interface TestConnectionResult {
  success: boolean;
  gateway: string;
  error?: string;
  account_id?: string;
  business_name?: string;
  country?: string;
  currency?: string;
  charges_enabled?: boolean;
  payouts_enabled?: boolean;
  mode?: string;
  client_id_configured?: boolean;
  webhook_configured?: boolean;
  tested_at: string;
}

export interface AsyncTestResponse {
  job_id: string;
  status: 'pending';
  message: string;
  poll_url: string;
}

export interface GatewayConnectionJob {
  id: string;
  gateway: string;
  status: 'pending' | 'running' | 'completed' | 'failed';
  result?: TestConnectionResult;
  created_at: string;
  updated_at: string;
  completed_at?: string;
}

export interface PaginatedResponse<T> {
  data: T[];
  pagination: {
    current_page: number;
    per_page: number;
    total_count: number;
    total_pages: number;
  };
}

export interface GatewayDetails {
  gateway: string;
  configuration: PaymentGatewayConfig;
  status: PaymentGatewayStatus;
  transactions: PaymentTransaction[];
  webhooks: WebhookEvent[];
  statistics: GatewayStats;
}

class PaymentGatewaysApi {
  // Get overview of all payment gateways
  async getOverview(): Promise<PaymentGatewaysOverview> {
    const response = await api.get('/payment_gateways');
    return response.data.data;
  }

  // Get detailed information for a specific gateway
  async getGatewayDetails(gateway: 'stripe' | 'paypal'): Promise<GatewayDetails> {
    const response = await api.get(`/payment_gateways/${gateway}`);
    return response.data.data;
  }

  // Update gateway configuration
  async updateGatewayConfiguration(
    gateway: 'stripe' | 'paypal',
    configuration: Partial<PaymentGatewayConfig>
  ): Promise<{ message: string; gateway: string; configuration: PaymentGatewayConfig }> {
    const response = await api.put(`/payment_gateways/${gateway}`, {
      configuration
    });
    return response.data;
  }

  // Test gateway connection (now async)
  async testConnection(gateway: 'stripe' | 'paypal'): Promise<AsyncTestResponse> {
    const response = await api.post(`/payment_gateways/${gateway}/test_connection`);
    return response.data.data;
  }

  // Get gateway connection job status
  async getConnectionJob(jobId: string): Promise<GatewayConnectionJob> {
    const response = await api.get(`/gateway_connection_jobs/${jobId}`);
    return response.data.data;
  }

  // Poll for test connection results with timeout
  async pollTestConnection(jobId: string, maxAttempts = 30, intervalMs = 2000): Promise<TestConnectionResult> {
    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      const job = await this.getConnectionJob(jobId);
      
      if (job.status === 'completed') {
        if (job.result) {
          return job.result;
        } else {
          throw new Error('Job completed but no result available');
        }
      } else if (job.status === 'failed') {
        const errorMessage = job.result?.error || 'Gateway connection test failed';
        throw new Error(errorMessage);
      }
      
      // Wait before next poll (unless it's the last attempt)
      if (attempt < maxAttempts - 1) {
        await new Promise(resolve => setTimeout(resolve, intervalMs));
      }
    }
    
    throw new Error('Gateway connection test timed out');
  }

  // Convenient method that starts test and polls for results
  async testConnectionAndWait(gateway: 'stripe' | 'paypal'): Promise<TestConnectionResult> {
    const asyncResponse = await this.testConnection(gateway);
    return this.pollTestConnection(asyncResponse.job_id);
  }

  // Get webhook events for a gateway
  async getWebhookEvents(
    gateway: 'stripe' | 'paypal',
    page = 1,
    perPage = 20
  ): Promise<PaginatedResponse<WebhookEvent>> {
    const response = await api.get(`/payment_gateways/${gateway}/webhook_events`, {
      params: { page, per_page: perPage }
    });
    return {
      data: response.data.events,
      pagination: response.data.pagination
    };
  }

  // Get transactions for a gateway
  async getTransactions(
    gateway: 'stripe' | 'paypal',
    page = 1,
    perPage = 20
  ): Promise<PaginatedResponse<PaymentTransaction>> {
    const response = await api.get(`/payment_gateways/${gateway}/transactions`, {
      params: { page, per_page: perPage }
    });
    return {
      data: response.data.transactions,
      pagination: response.data.pagination
    };
  }

  // Utility methods
  formatCurrency(amountCents: number | string, currency = 'USD'): string {
    const amount = typeof amountCents === 'string' ? parseInt(amountCents) : amountCents;
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: currency.toUpperCase(),
    }).format(amount / 100);
  }

  formatSuccessRate(rate: number): string {
    return `${rate.toFixed(2)}%`;
  }

  getStatusColor(status: string): 'green' | 'yellow' | 'red' | 'gray' {
    switch (status) {
      case 'connected':
      case 'processed':
      case 'succeeded':
        return 'green';
      case 'configured':
      case 'partial':
      case 'processing':
      case 'pending':
        return 'yellow';
      case 'error':
      case 'failed':
      case 'authentication_failed':
        return 'red';
      default:
        return 'gray';
    }
  }

  getStatusText(status: string): string {
    switch (status) {
      case 'connected':
        return 'Connected';
      case 'configured':
        return 'Configured';
      case 'not_configured':
        return 'Not Configured';
      case 'error':
        return 'Error';
      case 'authentication_failed':
        return 'Authentication Failed';
      case 'partial':
        return 'Partially Configured';
      case 'unsupported':
        return 'Unsupported';
      case 'processed':
        return 'Processed';
      case 'processing':
        return 'Processing';
      case 'pending':
        return 'Pending';
      case 'failed':
        return 'Failed';
      case 'succeeded':
        return 'Succeeded';
      case 'canceled':
        return 'Canceled';
      case 'refunded':
        return 'Refunded';
      default:
        return status.charAt(0).toUpperCase() + status.slice(1);
    }
  }

  getPaymentMethodName(method: string): string {
    switch (method) {
      case 'stripe_card':
        return 'Stripe Card';
      case 'stripe_bank':
        return 'Stripe Bank';
      case 'paypal':
        return 'PayPal';
      case 'bank_transfer':
        return 'Bank Transfer';
      case 'check':
        return 'Check';
      default:
        return method.charAt(0).toUpperCase() + method.slice(1);
    }
  }
}

export const paymentGatewaysApi = new PaymentGatewaysApi();