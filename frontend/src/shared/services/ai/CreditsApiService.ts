/**
 * Credits API Service - Prepaid AI Credit System
 *
 * Handles credit balance, purchases, transfers, and usage tracking.
 */

import { BaseApiService, QueryFilters } from './BaseApiService';

// ============================================================================
// Types
// ============================================================================

export interface CreditBalance {
  balance: number;
  reserved: number;
  available: number;
  is_reseller: boolean;
  lifetime_purchased: number;
  lifetime_used: number;
  last_purchase_at: string | null;
  last_usage_at: string | null;
}

export interface CreditTransaction {
  id: string;
  account_id: string;
  transaction_type: string;
  amount: number;
  balance_before: number;
  balance_after: number;
  description: string | null;
  status: string;
  reference_type: string | null;
  reference_id: string | null;
  created_at: string;
}

export interface CreditPack {
  id: string;
  name: string;
  description: string | null;
  pack_type: string;
  credits: number;
  price_usd: number;
  bonus_credits: number;
  effective_price_per_credit: number;
  is_featured: boolean;
  reseller_price_usd?: number;
  reseller_discount_percentage?: number;
}

export interface CreditPurchase {
  id: string;
  credit_pack_id: string;
  quantity: number;
  credits_purchased: number;
  bonus_credits: number;
  total_credits: number;
  unit_price_usd: number;
  total_price_usd: number;
  discount_percentage: number;
  discount_amount_usd: number;
  final_price_usd: number;
  status: string;
  created_at: string;
}

export interface CreditTransfer {
  id: string;
  reference_code: string;
  from_account_id: string;
  from_account_name: string;
  to_account_id: string;
  to_account_name: string;
  amount: number;
  fee_percentage: number;
  fee_amount: number;
  net_amount: number;
  status: string;
  description: string | null;
  created_at: string;
}

export interface UsageAnalytics {
  period_days: number;
  total_usage: number;
  average_daily: number;
  by_day: Record<string, number>;
  by_operation: Record<string, number>;
  transaction_count: number;
}

export interface OperationCost {
  credits: number;
  rate_id: string;
  rate_details: {
    operation_type: string;
    provider_type: string | null;
    model_name: string | null;
    base_credits: number;
  };
}

export interface ResellerStats {
  is_reseller: boolean;
  discount_percentage: number;
  total_transfers_out: number;
  total_credits_transferred: number;
  total_fees_collected: number;
  lifetime_credits_purchased: number;
  lifetime_credits_transferred_out: number;
}

export interface TransactionFilters extends QueryFilters {
  transaction_type?: string;
}

// ============================================================================
// Service
// ============================================================================

class CreditsApiService extends BaseApiService {
  private basePath = '/ai/credits';

  // Balance and Transactions
  async getBalance(): Promise<CreditBalance> {
    return this.get<CreditBalance>(`${this.basePath}/balance`);
  }

  async getTransactions(filters?: TransactionFilters): Promise<{
    transactions: CreditTransaction[];
    total_count: number;
  }> {
    const queryString = this.buildQueryString(filters);
    return this.get(`${this.basePath}/transactions${queryString}`);
  }

  // Credit Packs
  async getPacks(): Promise<{ packs: CreditPack[] }> {
    return this.get(`${this.basePath}/packs`);
  }

  // Purchases
  async createPurchase(data: {
    pack_id: string;
    quantity?: number;
    payment_method?: string;
  }): Promise<CreditPurchase> {
    return this.post<CreditPurchase>(`${this.basePath}/purchases`, data);
  }

  async completePurchase(
    purchaseId: string,
    paymentReference: string
  ): Promise<CreditPurchase> {
    return this.post<CreditPurchase>(
      `${this.basePath}/purchases/${purchaseId}/complete`,
      { payment_reference: paymentReference }
    );
  }

  // Transfers
  async createTransfer(data: {
    to_account_id: string;
    amount: number;
    description?: string;
  }): Promise<CreditTransfer> {
    return this.post<CreditTransfer>(`${this.basePath}/transfers`, data);
  }

  async approveTransfer(transferId: string): Promise<CreditTransfer> {
    return this.post<CreditTransfer>(
      `${this.basePath}/transfers/${transferId}/approve`
    );
  }

  async completeTransfer(transferId: string): Promise<CreditTransfer> {
    return this.post<CreditTransfer>(
      `${this.basePath}/transfers/${transferId}/complete`
    );
  }

  async cancelTransfer(
    transferId: string,
    reason?: string
  ): Promise<CreditTransfer> {
    return this.post<CreditTransfer>(
      `${this.basePath}/transfers/${transferId}/cancel`,
      { reason }
    );
  }

  // Usage
  async deductCredits(data: {
    amount: number;
    operation_type: string;
    reference?: string;
    description?: string;
    metadata?: Record<string, unknown>;
  }): Promise<{ success: boolean }> {
    return this.post(`${this.basePath}/deduct`, data);
  }

  async calculateCost(data: {
    operation_type: string;
    provider_type?: string;
    model_name?: string;
    metrics?: {
      input_tokens?: number;
      output_tokens?: number;
      requests?: number;
      duration_minutes?: number;
      storage_gb?: number;
    };
  }): Promise<OperationCost> {
    return this.post<OperationCost>(`${this.basePath}/calculate_cost`, data);
  }

  // Analytics
  async getUsageAnalytics(periodDays?: number): Promise<UsageAnalytics> {
    const queryString = periodDays ? `?period_days=${periodDays}` : '';
    return this.get<UsageAnalytics>(
      `${this.basePath}/usage_analytics${queryString}`
    );
  }

  // Reseller
  async enableReseller(
    discountPercentage?: number
  ): Promise<{ success: boolean; discount_percentage: number }> {
    return this.post(`${this.basePath}/enable_reseller`, {
      discount_percentage: discountPercentage,
    });
  }

  async getResellerStats(): Promise<ResellerStats> {
    return this.get<ResellerStats>(`${this.basePath}/reseller_stats`);
  }
}

export const creditsApi = new CreditsApiService();
export default creditsApi;
