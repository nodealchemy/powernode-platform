Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # API Routes
  namespace :api do
    namespace :v1 do
      # Health check endpoint for load balancers
      get :health, to: proc { [200, {}, [{status: 'ok'}.to_json]] }
      
      # Public endpoints (no authentication required)
      get 'public/plans', to: 'plans#public_index'
      
      # Authentication and registration endpoints
      namespace :auth do
        post :register, to: "registrations#create"
        post :login, to: "sessions#create"
        post :logout, to: "sessions#destroy"
        post :refresh, to: "sessions#refresh"
        get :me, to: "sessions#current"
        post "forgot-password", to: "passwords#forgot"
        post "reset-password", to: "passwords#reset"
        put "change-password", to: "passwords#change"
      end

      # Protected resources (will be added later)
      resources :accounts, only: [ :show, :update ] do
        resources :delegations, only: [:index, :create, :show, :update, :destroy] do
          collection do
            get :available_permissions
          end
          member do
            patch :activate
            patch :deactivate
            patch :revoke
            post :permissions, to: 'delegations#add_permission'
            delete 'permissions/:permission_id', to: 'delegations#remove_permission'
          end
        end
      end
      resources :users
      resources :roles
      resources :permissions, only: [ :index, :show ]

      # Plans management (admin only for create/update/delete)
      resources :plans do
        member do
          post :duplicate
          put :toggle_status
        end
      end

      # Settings endpoints
      resource :settings, only: [ :show, :update ]
      get "settings/notifications", to: "settings#notifications"
      put "settings/notifications", to: "settings#update_notifications"
      get "settings/preferences", to: "settings#preferences"
      put "settings/preferences", to: "settings#update_preferences"

      # Admin Settings endpoints (restricted to admin/owner roles)
      resource :admin_settings, only: [ :show, :update ] do
        get :users, on: :member
        get :accounts, on: :member
        get :system_logs, on: :member
        post :suspend_account, on: :member
        post :activate_account, on: :member
      end

      # Payment Gateways management (admin only)
      resources :payment_gateways, only: [ :index, :show, :update ] do
        member do
          post :test_connection
          get :webhook_events
          get :transactions
        end
      end

      # Billing and payments
      get "billing", to: "billing#overview"
      get "billing/invoices", to: "billing#invoices"
      post "billing/invoices", to: "billing#create_invoice"
      get "billing/payment-methods", to: "billing#payment_methods"
      post "billing/payment-methods", to: "billing#create_payment_method"
      post "billing/payment-intent", to: "billing#create_payment_intent"
      get "billing/subscription", to: "billing#subscription_billing"

      # Customer management endpoints
      resources :customers do
        member do
          get :stats
          patch :update_status
        end
      end

      # Payment-related endpoints
      resources :payment_methods, except: [ :show ]
      resources :subscriptions do
        collection do
          get :history
        end
      end
      resources :invoices, only: [ :index, :show ]
      resources :payments, only: [ :index, :show ]

      # PayPal integration endpoints
      resource :paypal, only: [] do
        collection do
          post :create_payment, path: 'payments'
          post :execute_payment, path: 'payments/:id/execute'
          post :create_refund, path: 'payments/:id/refund'
          post :create_subscription_plan, path: 'subscriptions/plans'
          post :create_subscription, path: 'subscriptions'
          post :execute_subscription, path: 'subscriptions/:id/execute'
          delete :cancel_subscription, path: 'subscriptions/:id'
        end
      end

      # Analytics endpoints
      namespace :analytics do
        get :revenue
        get :growth
        get :churn
        get :cohorts
        get :customers
        match :export, via: [ :get, :post ]
        
        # Worker service endpoints
        post :recalculate
        post :update_revenue_snapshots
        post :update_metrics
      end

      # Service authentication endpoint for worker
      namespace :service do
        match :verify, via: [:get, :post]
        post :authenticate_user
        post :verify_session
        get :health
      end

      # Billing endpoints for worker service
      namespace :billing do
        post :process_renewal
        post :retry_payment
        post :process_payment
        post :generate_invoice
        post :suspend_subscription
        post :cancel_subscription
        post :cleanup
        post :health_report
        post :reactivate_suspended_accounts
      end

      # Notifications endpoint for worker service
      resources :notifications, only: [:create]

      # Enhanced reports endpoints for worker integration
      resources :reports, only: [:show, :index, :create] do
        collection do
          get :templates
          get :scheduled
          post :generate
          post :schedule
          get :requests, to: 'reports#requests'
          post :requests, to: 'reports#create_request'
        end
        
        member do
          delete :scheduled, to: 'reports#destroy_scheduled'
        end
      end

      # Report requests nested endpoints
      get 'reports/requests/:id', to: 'reports#request_details'
      patch 'reports/requests/:id', to: 'reports#update_request'
      delete 'reports/requests/:id', to: 'reports#cancel_request'
      get 'reports/requests/:id/download', to: 'reports#download_request'

      # Pages management
      resources :pages, only: [:index, :show], param: :slug
      
      # Impersonation endpoints (admin only)
      resources :impersonations, only: [:index, :create, :destroy] do
        collection do
          get :history
          get :users, to: 'impersonations#impersonatable_users'
          post :validate, to: 'impersonations#validate_token'
          post :cleanup_expired, to: 'impersonations#cleanup_expired'
        end
      end

      # System Management endpoints (admin only)
      resources :audit_logs, only: [:index, :show] do
        collection do
          get :stats
          post :export
          delete :cleanup
        end
      end

      resources :webhooks, only: [:index, :show, :create, :update, :destroy] do
        member do
          post :test
          post :toggle_status
        end
        collection do
          get :available_events, to: 'webhooks#available_events'
          get :deliveries, to: 'webhooks#delivery_history'
          get :stats
          post :retry_failed
        end
      end

      resources :api_keys, only: [:index, :show, :create, :update, :destroy] do
        member do
          post :regenerate
          post :toggle_status
        end
        collection do
          get :usage, to: 'api_keys#usage_stats'
          get :scopes, to: 'api_keys#available_scopes'
          post :validate, to: 'api_keys#validate_key'
        end
      end

      # Admin services management
      namespace :admin do
        resources :users do
          member do
            post :impersonate
          end
        end
        
        resources :pages do
          member do
            post :publish
            post :unpublish
            post :duplicate
          end
        end
        
        resources :services do
          member do
            post :regenerate_token
            post :suspend
            post :activate
            post :revoke
          end
          
          resources :service_activities, path: 'activities' do
            collection do
              get :summary
              delete :cleanup
            end
          end
        end
      end
    end
  end

  # Webhook endpoints (outside of API versioning and auth)
  namespace :webhooks do
    post "stripe", to: "stripe#handle"
    post "paypal", to: "paypal#handle"
  end

  # ActionCable WebSocket endpoint
  mount ActionCable.server => '/cable'

  # Root route for API
  root to: proc { [ 200, {}, [ "Powernode API - Version 1.0" ] ] }
end
