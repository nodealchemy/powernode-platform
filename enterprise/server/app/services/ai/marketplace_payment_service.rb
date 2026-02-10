# frozen_string_literal: true

module Ai
  class MarketplacePaymentService
    attr_reader :account, :user

    def initialize(account:, user:)
      @account = account
      @user = user
    end

    # Purchase a template
    def purchase_template(template:, payment_method: "credits", discount_code: nil)
      return { success: false, error: "Template is free" } if template.free?
      return { success: false, error: "Template is not available for purchase" } unless template.published?

      # Check if already purchased
      existing = account.ai_agent_installations.find_by(agent_template: template, status: "active")
      return { success: false, error: "Template already purchased" } if existing

      price = template.price_usd
      discount = calculate_discount(price, discount_code)
      final_price = price - discount

      # Create purchase record
      purchase = Ai::MarketplacePurchase.create!(
        account: account,
        user: user,
        agent_template: template,
        purchase_type: template.pricing_type == "subscription" ? "subscription" : "one_time",
        price: price,
        discount_amount: discount,
        final_price: final_price,
        payment_method: payment_method
      )

      # Process payment based on method
      case payment_method
      when "credits"
        process_credit_payment(purchase, final_price)
      when "credit_card"
        process_card_payment(purchase, final_price)
      else
        { success: false, error: "Invalid payment method" }
      end
    rescue ActiveRecord::RecordInvalid => e
      { success: false, error: e.message }
    end

    # Process payout to publisher (via Stripe Connect)
    def process_publisher_payout(publisher:, amount:)
      return { success: false, error: "Publisher not configured for payouts" } unless publisher.stripe_payout_enabled?
      return { success: false, error: "Amount exceeds available earnings" } if amount > publisher.pending_payout_usd

      begin
        # Create Stripe transfer to connected account
        transfer = Stripe::Transfer.create({
          amount: (amount * 100).to_i, # Convert to cents
          currency: "usd",
          destination: publisher.stripe_account_id,
          description: "Powernode Marketplace Payout - #{Date.current.strftime('%B %Y')}"
        })

        # Update publisher
        publisher.process_payout(amount)

        Rails.logger.info "Payout processed: Publisher #{publisher.id}, Amount #{amount}, Transfer #{transfer.id}"
        { success: true, transfer_id: transfer.id, amount: amount }
      rescue Stripe::StripeError => e
        Rails.logger.error "Payout failed: Publisher #{publisher.id}, Error: #{e.message}"
        { success: false, error: e.message }
      end
    end

    # Setup Stripe Connect for publisher
    def setup_stripe_connect(publisher:, return_url:, refresh_url:)
      begin
        # Create or get Stripe Connect account
        if publisher.stripe_account_id.blank?
          account = Stripe::Account.create({
            type: "express",
            country: "US",
            email: publisher.account.users.first&.email,
            capabilities: {
              transfers: { requested: true }
            },
            business_type: "individual",
            metadata: {
              publisher_id: publisher.id
            }
          })

          publisher.update!(stripe_account_id: account.id, stripe_account_status: "pending")
        end

        # Create onboarding link
        link = Stripe::AccountLink.create({
          account: publisher.stripe_account_id,
          refresh_url: refresh_url,
          return_url: return_url,
          type: "account_onboarding"
        })

        { success: true, onboarding_url: link.url }
      rescue Stripe::StripeError => e
        Rails.logger.error "Stripe Connect setup failed: #{e.message}"
        { success: false, error: e.message }
      end
    end

    # Check and update Stripe account status
    def verify_stripe_account(publisher:)
      return { success: false, error: "No Stripe account" } unless publisher.stripe_account_id

      begin
        account = Stripe::Account.retrieve(publisher.stripe_account_id)

        publisher.update!(
          stripe_account_status: account.charges_enabled ? "active" : "pending",
          stripe_onboarding_completed: account.details_submitted,
          stripe_payout_enabled: account.payouts_enabled
        )

        {
          success: true,
          status: publisher.stripe_account_status,
          onboarding_completed: publisher.stripe_onboarding_completed,
          payout_enabled: publisher.stripe_payout_enabled
        }
      rescue Stripe::StripeError => e
        { success: false, error: e.message }
      end
    end

    private

    def process_credit_payment(purchase, amount)
      account_credits = account.ai_account_credits

      unless account_credits&.can_afford?(amount)
        purchase.fail!("Insufficient credits")
        return { success: false, error: "Insufficient credits" }
      end

      # Deduct credits
      account_credits.deduct_credits(
        amount,
        transaction_type: "usage",
        description: "Marketplace purchase: #{purchase.agent_template.name}",
        reference_type: "Ai::MarketplacePurchase",
        reference_id: purchase.id
      )

      # Complete purchase
      purchase.complete!("CREDIT-#{SecureRandom.hex(8).upcase}")

      Rails.logger.info "Credit purchase completed: Purchase #{purchase.id}, Template #{purchase.agent_template.name}"
      { success: true, purchase: purchase, installation: purchase.installation }
    end

    def process_card_payment(purchase, amount)
      # This would integrate with Stripe Payment Intents
      # Simplified for now
      begin
        # Create payment intent
        payment_intent = Stripe::PaymentIntent.create({
          amount: (amount * 100).to_i,
          currency: "usd",
          customer: get_or_create_stripe_customer,
          metadata: {
            purchase_id: purchase.id,
            template_id: purchase.agent_template_id
          }
        })

        purchase.update!(payment_reference: payment_intent.id)

        {
          success: true,
          requires_action: true,
          client_secret: payment_intent.client_secret,
          purchase_id: purchase.id
        }
      rescue Stripe::StripeError => e
        purchase.fail!(e.message)
        { success: false, error: e.message }
      end
    end

    def calculate_discount(price, discount_code)
      return 0 unless discount_code

      # Implement discount code logic here
      0
    end

    def get_or_create_stripe_customer
      # Implementation would look up or create Stripe customer for account
      nil
    end
  end
end
