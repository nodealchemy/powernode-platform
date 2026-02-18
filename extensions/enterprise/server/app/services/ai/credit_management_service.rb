# frozen_string_literal: true

# Credit Management Service - Comprehensive credit operations
#
# Handles all credit-related operations:
# - Credit balance management
# - Credit purchases and applications
# - B2B credit transfers
# - Reseller operations
# - Usage deduction
#
module Ai
  class CreditManagementService
    attr_reader :account, :errors

    def initialize(account)
      @account = account
      @errors = []
    end

    # ==========================================================================
    # BALANCE MANAGEMENT
    # ==========================================================================

    def get_balance
      account_credit = find_or_create_account_credit
      {
        balance: account_credit.balance.to_f,
        reserved: account_credit.reserved_balance.to_f,
        available: account_credit.available_balance.to_f,
        is_reseller: account_credit.is_reseller,
        lifetime_purchased: account_credit.lifetime_credits_purchased.to_f,
        lifetime_used: account_credit.lifetime_credits_used.to_f,
        last_purchase_at: account_credit.last_purchase_at,
        last_usage_at: account_credit.last_usage_at
      }
    end

    def get_transaction_history(limit: 50, offset: 0, transaction_type: nil)
      scope = Ai::CreditTransaction
        .where(account: account)
        .order(created_at: :desc)
        .offset(offset)
        .limit(limit)

      scope = scope.where(transaction_type: transaction_type) if transaction_type.present?

      {
        transactions: scope.map(&:summary),
        total_count: scope.except(:limit, :offset).count,
        limit: limit,
        offset: offset
      }
    end

    # ==========================================================================
    # CREDIT PURCHASES
    # ==========================================================================

    def get_available_packs
      Ai::CreditPack.active.ordered.map do |pack|
        pack_data = pack.summary
        # Apply reseller discount if applicable
        account_credit = find_or_create_account_credit
        if account_credit.is_reseller?
          discount = account_credit.reseller_discount_percentage
          pack_data[:reseller_price_usd] = (pack.price_usd * (1 - discount / 100)).round(2)
          pack_data[:reseller_discount_percentage] = discount
        end
        pack_data
      end
    end

    def initiate_purchase(pack_id:, quantity: 1, payment_method: nil, user: nil)
      pack = Ai::CreditPack.find(pack_id)

      unless pack.can_purchase_quantity?(quantity)
        @errors << "Cannot purchase #{quantity} of this pack"
        return nil
      end

      account_credit = find_or_create_account_credit
      discount_percentage = account_credit.is_reseller? ? account_credit.reseller_discount_percentage : 0

      total_credits = pack.credits * quantity
      bonus_credits = (pack.bonus_credits || 0) * quantity
      unit_price = pack.price_usd
      total_price = unit_price * quantity
      discount_amount = (total_price * discount_percentage / 100).round(2)
      final_price = (total_price - discount_amount).round(2)

      purchase = Ai::CreditPurchase.create!(
        account: account,
        credit_pack: pack,
        user: user,
        quantity: quantity,
        credits_purchased: total_credits,
        bonus_credits: bonus_credits,
        total_credits: total_credits + bonus_credits,
        unit_price_usd: unit_price,
        total_price_usd: total_price,
        discount_percentage: discount_percentage,
        discount_amount_usd: discount_amount,
        final_price_usd: final_price,
        payment_method: payment_method,
        status: "pending"
      )

      purchase.summary
    rescue ActiveRecord::RecordNotFound
      @errors << "Credit pack not found"
      nil
    rescue ActiveRecord::RecordInvalid => e
      @errors << e.message
      nil
    end

    def complete_purchase(purchase_id:, payment_reference:)
      purchase = Ai::CreditPurchase.find(purchase_id)

      unless purchase.account_id == account.id
        @errors << "Purchase does not belong to this account"
        return nil
      end

      unless purchase.status == "pending"
        @errors << "Purchase is not in pending status"
        return nil
      end

      ActiveRecord::Base.transaction do
        purchase.update!(
          status: "completed",
          payment_reference: payment_reference,
          paid_at: Time.current
        )

        account_credit = find_or_create_account_credit
        account_credit.add_credits(
          purchase.total_credits,
          transaction_type: "purchase",
          description: "Credit purchase: #{purchase.credit_pack.name} x#{purchase.quantity}",
          credit_pack: purchase.credit_pack,
          metadata: { purchase_id: purchase.id }
        )

        purchase.update!(credits_applied_at: Time.current)
      end

      purchase.reload.summary
    rescue ActiveRecord::RecordNotFound
      @errors << "Purchase not found"
      nil
    rescue StandardError => e
      @errors << e.message
      nil
    end

    # ==========================================================================
    # CREDIT TRANSFERS (B2B)
    # ==========================================================================

    def initiate_transfer(to_account:, amount:, description: nil, user:)
      account_credit = find_or_create_account_credit

      unless account_credit.available_balance >= amount
        @errors << "Insufficient available balance"
        return nil
      end

      fee_percentage = calculate_transfer_fee(amount)
      fee_amount = (amount * fee_percentage / 100).round(4)
      net_amount = (amount - fee_amount).round(4)

      transfer = Ai::CreditTransfer.create!(
        from_account: account,
        to_account: to_account,
        initiated_by: user,
        amount: amount,
        fee_percentage: fee_percentage,
        fee_amount: fee_amount,
        net_amount: net_amount,
        description: description,
        reference_code: generate_transfer_reference,
        status: "pending"
      )

      # Reserve the credits
      account_credit.reserve_credits(amount, description: "Transfer reservation: #{transfer.reference_code}")

      transfer.summary
    rescue ActiveRecord::RecordInvalid => e
      @errors << e.message
      nil
    end

    def approve_transfer(transfer_id:, user:)
      transfer = Ai::CreditTransfer.find(transfer_id)

      unless transfer.from_account_id == account.id
        @errors << "Transfer does not belong to this account"
        return nil
      end

      unless transfer.status == "pending"
        @errors << "Transfer is not in pending status"
        return nil
      end

      transfer.approve!(user)
      transfer.reload.summary
    rescue ActiveRecord::RecordNotFound
      @errors << "Transfer not found"
      nil
    rescue StandardError => e
      @errors << e.message
      nil
    end

    def complete_transfer(transfer_id:)
      transfer = Ai::CreditTransfer.find(transfer_id)

      unless transfer.status == "approved"
        @errors << "Transfer is not approved"
        return nil
      end

      transfer.complete!
      transfer.reload.summary
    rescue ActiveRecord::RecordNotFound
      @errors << "Transfer not found"
      nil
    rescue StandardError => e
      @errors << e.message
      nil
    end

    def cancel_transfer(transfer_id:, reason: nil)
      transfer = Ai::CreditTransfer.find(transfer_id)

      unless %w[pending approved].include?(transfer.status)
        @errors << "Cannot cancel transfer in #{transfer.status} status"
        return nil
      end

      transfer.cancel!(reason)
      transfer.reload.summary
    rescue ActiveRecord::RecordNotFound
      @errors << "Transfer not found"
      nil
    rescue StandardError => e
      @errors << e.message
      nil
    end

    # ==========================================================================
    # USAGE OPERATIONS
    # ==========================================================================

    def deduct_credits(amount:, operation_type:, reference: nil, description: nil, metadata: {})
      account_credit = find_or_create_account_credit

      unless account_credit.available_balance >= amount
        @errors << "Insufficient credits"
        return nil
      end

      account_credit.deduct_credits(
        amount,
        transaction_type: "usage",
        description: description || "#{operation_type} usage",
        reference_type: reference&.class&.name,
        reference_id: reference&.id,
        metadata: metadata.merge(operation_type: operation_type)
      )
    rescue StandardError => e
      @errors << e.message
      nil
    end

    def calculate_operation_cost(operation_type:, provider_type: nil, model_name: nil, metrics: {})
      rate = Ai::CreditUsageRate.find_active_rate(
        operation_type: operation_type,
        provider_type: provider_type,
        model_name: model_name
      )

      return nil unless rate

      cost = rate.base_credits || 0

      if metrics[:input_tokens] && rate.credits_per_1k_input_tokens
        cost += (metrics[:input_tokens] / 1000.0 * rate.credits_per_1k_input_tokens).round(4)
      end

      if metrics[:output_tokens] && rate.credits_per_1k_output_tokens
        cost += (metrics[:output_tokens] / 1000.0 * rate.credits_per_1k_output_tokens).round(4)
      end

      if metrics[:requests] && rate.credits_per_request
        cost += (metrics[:requests] * rate.credits_per_request).round(4)
      end

      if metrics[:duration_minutes] && rate.credits_per_minute
        cost += (metrics[:duration_minutes] * rate.credits_per_minute).round(4)
      end

      if metrics[:storage_gb] && rate.credits_per_gb_storage
        cost += (metrics[:storage_gb] * rate.credits_per_gb_storage).round(4)
      end

      { credits: cost.round(4), rate_id: rate.id, rate_details: rate.summary }
    end

    # ==========================================================================
    # RESELLER OPERATIONS
    # ==========================================================================

    def enable_reseller(discount_percentage: 15)
      account_credit = find_or_create_account_credit

      account_credit.update!(
        is_reseller: true,
        reseller_discount_percentage: discount_percentage
      )

      { success: true, discount_percentage: discount_percentage }
    rescue StandardError => e
      @errors << e.message
      nil
    end

    def get_reseller_stats
      account_credit = find_or_create_account_credit

      unless account_credit.is_reseller?
        @errors << "Account is not a reseller"
        return nil
      end

      transfers_out = Ai::CreditTransfer
        .where(from_account: account)
        .where(status: "completed")

      {
        is_reseller: true,
        discount_percentage: account_credit.reseller_discount_percentage.to_f,
        total_transfers_out: transfers_out.count,
        total_credits_transferred: transfers_out.sum(:amount).to_f,
        total_fees_collected: transfers_out.sum(:fee_amount).to_f,
        lifetime_credits_purchased: account_credit.lifetime_credits_purchased.to_f,
        lifetime_credits_transferred_out: account_credit.lifetime_credits_transferred_out.to_f
      }
    end

    # ==========================================================================
    # ANALYTICS
    # ==========================================================================

    def get_usage_analytics(period: 30.days)
      transactions = Ai::CreditTransaction
        .where(account: account)
        .where("created_at >= ?", period.ago)
        .where(transaction_type: "usage")

      by_day = transactions
        .group("DATE(created_at)")
        .sum(:amount)
        .transform_keys(&:to_s)

      by_operation = transactions
        .group("metadata->>'operation_type'")
        .sum(:amount)

      {
        period_days: period.to_i / 86400,
        total_usage: transactions.sum(:amount).abs.to_f,
        average_daily: (transactions.sum(:amount).abs / (period.to_i / 86400.0)).round(4),
        by_day: by_day.transform_values { |v| v.abs.to_f },
        by_operation: by_operation.transform_values { |v| v.abs.to_f },
        transaction_count: transactions.count
      }
    end

    private

    def find_or_create_account_credit
      Ai::AccountCredit.find_or_create_by!(account: account)
    end

    def calculate_transfer_fee(amount)
      # Tiered fee structure
      return 2.0 if amount >= 10_000
      return 3.0 if amount >= 1_000
      5.0
    end

    def generate_transfer_reference
      "TRF-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
    end
  end
end
