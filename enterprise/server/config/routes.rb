# frozen_string_literal: true

# Enterprise routes - loaded automatically by the Rails::Engine add_routing_paths
# initializer. Routes defined here are only available when the enterprise engine is loaded.

Rails.application.routes.draw do
  # API Routes
  namespace :api do
    namespace :v1 do
    # =========================================================================
    # BaaS API - Billing-as-a-Service for external customers
    # =========================================================================
    namespace :baas do
      # Tenant management
      resource :tenant, only: [ :show, :create, :update ], controller: "tenants" do
        get :dashboard
        get :limits
        get :billing_configuration
        patch :billing_configuration, action: :update_billing_configuration
      end

      # API Keys
      resources :api_keys, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          post :roll
        end
      end

      # Customers
      resources :customers, only: [ :index, :show, :create, :update, :destroy ], param: :id

      # Subscriptions
      resources :subscriptions, only: [ :index, :show, :create, :update ], param: :id do
        member do
          post :cancel
          post :pause
          post :resume
        end
      end

      # Invoices
      resources :invoices, only: [ :index, :show, :create, :update, :destroy ], param: :id do
        member do
          post :finalize
          post :pay
          post :void
          post :line_items, action: :add_line_item
          delete "line_items/:item_id", action: :remove_line_item
        end
      end

      # Usage events/metering
      resources :usage_events, only: [ :create ], controller: "usage" do
        collection do
          post :batch
        end
      end

      # Usage queries
      get "usage", to: "usage#index"
      get "usage/summary", to: "usage#summary"
      get "usage/aggregate", to: "usage#aggregate"
      get "usage/analytics", to: "usage#analytics"
    end
    # =========================================================================
    # Billing & Payments (moved from core)
    # =========================================================================

    # Payment Gateways management (admin only)
    resources :payment_gateways, only: [ :index, :show, :update ] do
      member do
        post :test_connection
        get :webhook_events
        get :transactions
      end
    end

    # Gateway connection jobs (for async testing)
    resources :gateway_connection_jobs, only: [ :show, :update ]

    # Billing and payments
    get "billing", to: "billing#overview"
    get "billing/invoices", to: "billing#invoices"
    post "billing/invoices", to: "billing#create_invoice"
    get "billing/payment-methods", to: "billing#payment_methods"
    post "billing/payment-methods", to: "billing#create_payment_method"
    post "billing/payment-intent", to: "billing#create_payment_intent"
    get "billing/subscription", to: "billing#subscription_billing"

    # Payment-related endpoints
    resources :payment_methods, except: [ :show ] do
      member do
        post :set_default
      end
      collection do
        post :setup_intent
        post :confirm
      end
    end
    resources :subscriptions do
      collection do
        get :history
      end
      member do
        get :by_stripe_id
        post :pause
        post :resume
        get :preview_proration
      end
    end
    # Subscriptions lookup by external ID
    get "subscriptions/by_stripe_id/:stripe_id", to: "subscriptions#by_stripe_id"
    get "subscriptions/by_paypal_id/:paypal_id", to: "subscriptions#by_paypal_id"

    resources :invoices, only: [ :index, :show ] do
      member do
        post :send_invoice, path: "send"
        post :mark_paid
        post :void
        post :retry_payment
        get :pdf
      end
      collection do
        get :statistics
      end
    end
    resources :payments, only: [ :index, :show ]

    # PayPal integration endpoints
    resource :paypal, only: [], controller: "paypal" do
      collection do
        post :create_payment, path: "payments"
        post :execute_payment, path: "payments/:id/execute"
        post :create_refund, path: "payments/:id/refund"
        post :create_subscription_plan, path: "subscriptions/plans"
        post :create_subscription, path: "subscriptions"
        post :execute_subscription, path: "subscriptions/:id/execute"
        delete :cancel_subscription, path: "subscriptions/:id"
      end
    end

    # Predictive Analytics & Revenue Intelligence
    namespace :predictive_analytics, path: "predictive-analytics" do
      # Health scores
      get :health_scores
      get "health_scores/:id", action: :health_score
      post "health_scores/calculate", action: :calculate_health_score

      # Churn predictions
      get :churn_predictions
      get "churn_predictions/:id", action: :churn_prediction
      post "churn_predictions/predict", action: :predict_churn

      # Revenue forecasts
      get :revenue_forecasts
      post "revenue_forecasts/generate", action: :generate_forecast

      # Alerts
      get :alerts
      post :alerts, action: :create_alert
      get "alerts/:id", action: :alert
      patch "alerts/:id", action: :update_alert
      delete "alerts/:id", action: :delete_alert
      get "alerts/:id/events", action: :alert_events
      post "alerts/:id/acknowledge", action: :acknowledge_alert

      # Summary and recommendations
      get :summary
      get :recommendations
    end

    # Analytics tiers (enterprise revenue intelligence)
    scope "analytics" do
      resources :tiers, only: [ :index, :show ], controller: "analytics_tiers", param: :slug do
        collection do
          get :current
          get :comparison
          get :feature_gates
          post :upgrade
        end
      end
    end

    # Reseller program endpoints
    resources :resellers do
      collection do
        get :me
        get :tiers
        post :track_referral
      end
      member do
        get :dashboard
        get :commissions
        get :referrals
        get :payouts
        post :request_payout
        post :approve
        post :activate
        post :suspend
      end
    end
    post "resellers/payouts/:payout_id/process", to: "resellers#process_payout"

    # Impersonation endpoints (admin only - enterprise)
    resources :impersonations, only: [ :index, :create, :destroy ] do
      collection do
        delete "/", to: "impersonations#destroy"
        get :history
        get :users, to: "impersonations#impersonatable_users"
        post :validate, to: "impersonations#validate_token"
        post :cleanup_expired, to: "impersonations#cleanup_expired"
      end
    end

    # Enterprise AI routes
    namespace :ai do
      # ===================================================================
      # CREDITS CONTROLLER - Prepaid AI Credit System (Enterprise)
      # ===================================================================
      scope :credits, controller: "credits" do
        # Balance and transactions
        get "balance", action: :balance
        get "transactions", action: :transactions

        # Credit packs
        get "packs", action: :packs

        # Purchases
        post "purchases", action: :create_purchase
        post "purchases/:id/complete", action: :complete_purchase

        # Transfers (B2B)
        post "transfers", action: :create_transfer
        post "transfers/:id/approve", action: :approve_transfer
        post "transfers/:id/complete", action: :complete_transfer
        post "transfers/:id/cancel", action: :cancel_transfer

        # Usage
        post "deduct", action: :deduct
        post "calculate_cost", action: :calculate_cost

        # Analytics
        get "usage_analytics", action: :usage_analytics

        # Reseller
        post "enable_reseller", action: :enable_reseller
        get "reseller_stats", action: :reseller_stats
      end

      # ===================================================================
      # OUTCOME BILLING CONTROLLER - Success-Based AI Billing (Enterprise)
      # ===================================================================
      scope :outcome_billing, controller: "outcome_billing" do
        # Outcome definitions
        get "definitions", action: :definitions
        get "definitions/:id", action: :show_definition
        post "definitions", action: :create_definition
        patch "definitions/:id", action: :update_definition

        # SLA contracts
        get "contracts", action: :contracts
        get "contracts/:id", action: :show_contract
        post "contracts", action: :create_contract
        post "contracts/:id/activate", action: :activate_contract
        post "contracts/:id/suspend", action: :suspend_contract
        post "contracts/:id/cancel", action: :cancel_contract

        # Billing records
        get "records", action: :records
        post "records", action: :create_record
        patch "records/:id/complete", action: :complete_record
        post "records/mark_billed", action: :mark_billed

        # SLA violations
        get "violations", action: :violations
        post "violations/:id/approve", action: :approve_violation
        post "violations/:id/apply", action: :apply_violation
        post "violations/:id/reject", action: :reject_violation

        # Analytics
        get "summary", action: :summary
        get "sla_performance", action: :sla_performance
      end

      # ===================================================================
      # GOVERNANCE CONTROLLER - AI Workflow Governance & Compliance (Enterprise)
      # ===================================================================
      scope :governance, controller: "governance" do
        # Policies
        get "policies", action: :policies
        post "policies", action: :create_policy
        put "policies/:id/activate", action: :activate_policy
        post "policies/evaluate", action: :evaluate_policies

        # Violations
        get "violations", action: :violations
        put "violations/:id/acknowledge", action: :acknowledge_violation
        put "violations/:id/resolve", action: :resolve_violation

        # Approval chains
        get "approval_chains", action: :approval_chains
        post "approval_chains", action: :create_approval_chain

        # Approval requests
        get "approval_requests", action: :approval_requests
        get "approval_requests/pending", action: :pending_approvals
        post "approval_requests/:id/decide", action: :decide_approval

        # Data classifications
        get "classifications", action: :classifications
        post "classifications", action: :create_classification

        # Data scanning
        post "scan", action: :scan_data
        post "mask", action: :mask_data

        # Reports
        get "reports", action: :reports
        post "reports", action: :generate_report

        # Summary and audit
        get "summary", action: :summary
        get "audit_log", action: :audit_log
      end

      # ===================================================================
      # PUBLISHER CONTROLLER - Publisher dashboard and earnings (Enterprise)
      # ===================================================================
      get "publisher/me", controller: "publisher", action: :me, as: :enterprise_publisher_me
      resources :publisher, only: [ :index, :show, :create ], controller: "publisher", as: :enterprise_publishers do
        member do
          get :dashboard
          get :analytics
          get :earnings
          get :templates
          get :payouts
          post :request_payout
          post :stripe_setup
          get :stripe_status
        end
      end

      # Enterprise intelligence routes (all intelligence moved from core)
      namespace :intelligence do
        resource :supply_chain, only: [] do
          post :analyze
          get :risk_summary
          get :vulnerability_report
        end
        resource :pipeline, only: [] do
          post :analyze_failure
          get :health
          get :trends
        end
        resource :revenue, only: [] do
          get :forecast
          get :churn_risks
          get :health_scores
        end
        resource :reviews, only: [] do
          post :sentiment_analysis
          get :spam_detection
          post :generate_response
          get :agent_quality
        end
        resource :notifications, only: [] do
          post :smart_routing
          get :fatigue_analysis
          get :digest_recommendations
        end
        resource :monitoring, only: [] do
          get :predictive_failure
          get :self_healing
          get :sla_breach_risk
        end
        resource :baas, only: [] do
          get :usage_anomalies
          get :tenant_churn
          get :pricing_recommendations
          get :api_fraud
        end
        resource :reseller, only: [] do
          get :performance_scores
          get :commission_optimization
          get :referral_churn_risks
        end
      end
    end
  end
end
end
