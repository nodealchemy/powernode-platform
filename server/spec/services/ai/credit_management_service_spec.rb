# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::CreditManagementService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  subject(:service) { described_class.new(account) }

  describe '#initialize' do
    it 'initializes with account' do
      expect(service.account).to eq(account)
    end

    it 'initializes with empty errors' do
      expect(service.errors).to be_empty
    end
  end

  describe '#get_balance' do
    it 'returns balance information' do
      balance = service.get_balance

      expect(balance).to include(
        :balance,
        :reserved,
        :available,
        :is_reseller,
        :lifetime_purchased,
        :lifetime_used
      )
    end

    it 'returns numeric values' do
      balance = service.get_balance

      expect(balance[:balance]).to be_a(Numeric)
      expect(balance[:available]).to be_a(Numeric)
      expect(balance[:reserved]).to be_a(Numeric)
    end

    it 'creates account credit record if none exists' do
      expect {
        service.get_balance
      }.to change { Ai::AccountCredit.where(account: account).count }.by(1)
    end

    it 'returns existing account credit when present' do
      Ai::AccountCredit.create!(account: account, balance: 100.0)

      balance = service.get_balance
      expect(balance[:balance]).to eq(100.0)
    end
  end

  describe '#get_transaction_history' do
    before do
      # Ensure account credit exists
      Ai::AccountCredit.find_or_create_by!(account: account)
    end

    it 'returns transaction list structure' do
      result = service.get_transaction_history

      expect(result).to include(
        :transactions,
        :total_count,
        :limit,
        :offset
      )
    end

    it 'respects limit parameter' do
      result = service.get_transaction_history(limit: 10)
      expect(result[:limit]).to eq(10)
    end

    it 'respects offset parameter' do
      result = service.get_transaction_history(offset: 5)
      expect(result[:offset]).to eq(5)
    end

    it 'filters by transaction_type' do
      result = service.get_transaction_history(transaction_type: 'purchase')
      expect(result[:transactions]).to be_an(Array)
    end
  end

  describe '#initiate_purchase' do
    let!(:credit_pack) do
      Ai::CreditPack.create!(
        name: 'Starter Pack',
        pack_type: 'standard',
        credits: 1000,
        bonus_credits: 100,
        price_usd: 9.99,
        is_active: true,
        sort_order: 1
      )
    end

    context 'with valid pack' do
      it 'creates a pending purchase' do
        result = service.initiate_purchase(
          pack_id: credit_pack.id,
          quantity: 1,
          user: user
        )

        expect(result).to be_present
        expect(result[:status]).to eq('pending')
      end

      it 'calculates correct total credits' do
        result = service.initiate_purchase(
          pack_id: credit_pack.id,
          quantity: 2,
          user: user
        )

        expect(result).to be_present
        expect(result[:total_credits]).to eq(2200) # (1000 + 100) * 2
      end

      it 'calculates correct price' do
        result = service.initiate_purchase(
          pack_id: credit_pack.id,
          quantity: 1,
          user: user
        )

        expect(result).to be_present
        expect(result[:final_price_usd]).to eq(9.99)
      end
    end

    context 'with invalid pack' do
      it 'returns nil for nonexistent pack' do
        result = service.initiate_purchase(
          pack_id: SecureRandom.uuid,
          quantity: 1,
          user: user
        )

        expect(result).to be_nil
        expect(service.errors).to include('Credit pack not found')
      end
    end
  end

  describe '#complete_purchase' do
    let!(:credit_pack) do
      Ai::CreditPack.create!(
        name: 'Starter Pack',
        pack_type: 'standard',
        credits: 1000,
        bonus_credits: 0,
        price_usd: 9.99,
        is_active: true,
        sort_order: 1
      )
    end

    let!(:purchase) do
      Ai::CreditPurchase.create!(
        account: account,
        credit_pack: credit_pack,
        user: user,
        quantity: 1,
        credits_purchased: 1000,
        bonus_credits: 0,
        total_credits: 1000,
        unit_price_usd: 9.99,
        total_price_usd: 9.99,
        discount_percentage: 0,
        discount_amount_usd: 0,
        final_price_usd: 9.99,
        status: 'pending'
      )
    end

    context 'with valid pending purchase' do
      it 'completes purchase and adds credits' do
        result = service.complete_purchase(
          purchase_id: purchase.id,
          payment_reference: 'PAY-123'
        )

        expect(result).to be_present
        expect(result[:status]).to eq('completed')

        balance = service.get_balance
        expect(balance[:balance]).to eq(1000.0)
      end
    end

    context 'with already completed purchase' do
      before { purchase.update!(status: 'completed') }

      it 'returns nil with error' do
        result = service.complete_purchase(
          purchase_id: purchase.id,
          payment_reference: 'PAY-123'
        )

        expect(result).to be_nil
        expect(service.errors).to include('Purchase is not in pending status')
      end
    end

    context 'with purchase from another account' do
      let(:other_account) { create(:account) }

      before { purchase.update!(account: other_account) }

      it 'returns nil with error' do
        result = service.complete_purchase(
          purchase_id: purchase.id,
          payment_reference: 'PAY-123'
        )

        expect(result).to be_nil
        expect(service.errors).to include('Purchase does not belong to this account')
      end
    end
  end

  describe '#deduct_credits' do
    before do
      account_credit = Ai::AccountCredit.find_or_create_by!(account: account)
      account_credit.update!(balance: 500.0)
    end

    context 'with sufficient credits' do
      it 'deducts credits successfully' do
        result = service.deduct_credits(
          amount: 100,
          operation_type: 'agent_execution',
          description: 'Agent execution cost'
        )

        expect(result).to be_present

        balance = service.get_balance
        expect(balance[:balance]).to eq(400.0)
      end
    end

    context 'with insufficient credits' do
      it 'returns nil with error' do
        result = service.deduct_credits(
          amount: 1000,
          operation_type: 'agent_execution'
        )

        expect(result).to be_nil
        expect(service.errors).to include('Insufficient credits')
      end
    end
  end

  describe '#initiate_transfer' do
    let(:to_account) { create(:account) }

    before do
      account_credit = Ai::AccountCredit.find_or_create_by!(account: account)
      account_credit.update!(balance: 5000.0)
    end

    context 'with sufficient balance' do
      it 'creates a pending transfer' do
        result = service.initiate_transfer(
          to_account: to_account,
          amount: 1000,
          description: 'B2B transfer',
          user: user
        )

        expect(result).to be_present
        expect(result[:status]).to eq('pending')
      end

      it 'calculates transfer fee' do
        result = service.initiate_transfer(
          to_account: to_account,
          amount: 1000,
          description: 'B2B transfer',
          user: user
        )

        expect(result).to be_present
        expect(result[:fee_percentage]).to eq(3.0) # 3% for 1000+
        expect(result[:net_amount]).to be < 1000
      end

      it 'applies tiered fee structure' do
        # Small transfer - 5% fee
        small_result = service.initiate_transfer(
          to_account: to_account,
          amount: 100,
          user: user
        )
        expect(small_result[:fee_percentage]).to eq(5.0)
      end
    end

    context 'with insufficient balance' do
      it 'returns nil with error' do
        result = service.initiate_transfer(
          to_account: to_account,
          amount: 50_000,
          user: user
        )

        expect(result).to be_nil
        expect(service.errors).to include('Insufficient available balance')
      end
    end
  end

  describe '#enable_reseller' do
    it 'enables reseller status' do
      result = service.enable_reseller(discount_percentage: 20)

      expect(result).to include(success: true, discount_percentage: 20)

      account_credit = Ai::AccountCredit.find_by(account: account)
      expect(account_credit.is_reseller).to be true
      expect(account_credit.reseller_discount_percentage).to eq(20)
    end
  end

  describe '#get_reseller_stats' do
    context 'when account is not a reseller' do
      it 'returns nil with error' do
        Ai::AccountCredit.find_or_create_by!(account: account)

        result = service.get_reseller_stats
        expect(result).to be_nil
        expect(service.errors).to include('Account is not a reseller')
      end
    end

    context 'when account is a reseller' do
      before do
        account_credit = Ai::AccountCredit.find_or_create_by!(account: account)
        account_credit.update!(is_reseller: true, reseller_discount_percentage: 15)
      end

      it 'returns reseller statistics' do
        result = service.get_reseller_stats

        expect(result).to include(
          :is_reseller,
          :discount_percentage,
          :total_transfers_out,
          :total_credits_transferred
        )
        expect(result[:is_reseller]).to be true
      end
    end
  end

  describe '#get_usage_analytics' do
    it 'returns usage analytics structure' do
      result = service.get_usage_analytics(period: 30.days)

      expect(result).to include(
        :period_days,
        :total_usage,
        :average_daily,
        :by_day,
        :by_operation,
        :transaction_count
      )
    end

    it 'returns numeric values for totals' do
      result = service.get_usage_analytics

      expect(result[:total_usage]).to be_a(Numeric)
      expect(result[:average_daily]).to be_a(Numeric)
      expect(result[:transaction_count]).to be_a(Integer)
    end
  end

  describe '#calculate_operation_cost' do
    context 'when no rate exists' do
      it 'returns nil' do
        result = service.calculate_operation_cost(
          operation_type: 'nonexistent_type'
        )

        expect(result).to be_nil
      end
    end
  end
end
