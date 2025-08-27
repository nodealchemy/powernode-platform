Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Health check endpoint (global, outside API namespace)
  get :health, to: 'health#index'

  # API Routes
  namespace :api do
    namespace :v1 do
      # Health check endpoint for load balancers
      get :health, to: proc { [200, {}, [{status: 'ok'}.to_json]] }
      
      # Worker test endpoints
      post 'worker/ping', to: 'worker_test#ping'
      post 'worker/process_job', to: 'worker_test#process_job'
      
      # CSRF token endpoint for authenticated users
      get :csrf_token, to: 'csrf#token'
      
      # Public endpoints (no authentication required)
      get 'public/plans', to: 'plans#public_index'
      
      # Internal API for worker service
      namespace :internal do
        resources :users, only: [:show]
        resources :accounts, only: [:show]
        
        # Background job tracking
        resources :jobs, only: [:show, :update]
        
        # Metrics tracking for worker jobs
        namespace :metrics do
          post :jobs
          post :errors
          post :custom
        end
        
        # Worker status and health
        resources :workers, only: [:index, :show] do
          member do
            post :ping
            get :status
          end
        end
        
        # Reverse proxy internal operations
        namespace :reverse_proxy do
          post :validate, to: 'reverse_proxy#validate_config'
          post :test_connectivity, to: 'reverse_proxy#test_connectivity'
          post :generate_config, to: 'reverse_proxy#generate_config'
          post :service_discovery, to: 'reverse_proxy#service_discovery'
          post :health_check, to: 'reverse_proxy#health_check'
          post :validate_services, to: 'reverse_proxy#validate_services'
        end
      end
      
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
        post "verify-2fa", to: "sessions#verify_2fa"
        post "verify-email", to: "email_verifications#verify"
        post "resend-verification", to: "email_verifications#resend"
      end

      # Two-Factor Authentication endpoints (require authentication)
      resource :two_factor, only: [] do
        collection do
          post :enable
          post :verify_setup
          delete :disable
          get :status
          post :regenerate_backup_codes
          get :backup_codes
        end
      end

      # Worker authentication endpoints (for worker service)
      namespace :worker_auth do
        post :verify
        post :authenticate_user
        post :verify_session
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
      resources :users do
        collection do
          get :stats
        end
      end
      resources :roles do
        collection do
          get :assignable
        end
        member do
          get :users
          post 'assign_to_user/:user_id', action: :assign_to_user
          delete 'remove_from_user/:user_id', action: :remove_from_user
        end
      end
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
        get :metrics, on: :member
        get :health, on: :member
        
        # Security configuration endpoints
        get :security, on: :member
        put :security, on: :member, action: :update_security_config
        post 'security/test', on: :member, action: :test_security_config
        post 'security/regenerate_jwt_secret', on: :member, action: :regenerate_jwt_secret
        delete 'security/blacklisted_tokens', on: :member, action: :clear_blacklisted_tokens
      end

      # Services Configuration (system-level)
      resource :services, only: [ :show, :update ], controller: 'services' do
        post :test_configuration, on: :member
        post :generate_config, on: :member
        get :health_check, on: :member
        get :status, on: :member
        
        # Service Discovery endpoints
        get :discovered_services, on: :member
        post :service_discovery, on: :member
        post :add_discovered_service, on: :member
        get 'health_history/:service_name', to: 'services#health_history', on: :member
        put 'health_config/:service_name', to: 'services#update_health_config', on: :member
        
        # Service Management endpoints
        post :test_service, on: :member
        post :validate_service, on: :member
        get :service_templates, on: :member
        post :duplicate_service, on: :member
        get 'export_services/:environment', to: 'services#export_services', on: :member
        post :import_services, on: :member
        
        resources :url_mappings, only: [ :create, :destroy ] do
          put :update_url_mapping, on: :member
          patch :toggle, on: :member
        end
      end

      # Admin endpoints (restricted to admin permissions)
      namespace :admin do
        # Background job tracking
        resources :jobs, only: [:index, :show]
        
        # User management
        resources :users do
          member do
            post :impersonate
          end
        end
        
        # Page management
        resources :pages do
          member do
            post :publish
            post :unpublish
            post :duplicate
          end
        end
        

        # Maintenance endpoints
        namespace :maintenance do
          get :status, to: 'maintenance#status'
          get :health, to: 'maintenance#health'
          get :metrics, to: 'maintenance#metrics'
          
          # Backup management
          get :backups, to: 'maintenance#backups'
          post :backups, to: 'maintenance#create_backup'
          delete 'backups/:id', to: 'maintenance#delete_backup'
          post 'backups/:id/restore', to: 'maintenance#restore_backup'
          
          # Cleanup operations
          get 'cleanup/stats', to: 'maintenance#cleanup_stats'
          post 'cleanup/run', to: 'maintenance#run_cleanup'
          
          # Scheduled maintenance
          get :schedules, to: 'maintenance#schedules'
          post :schedules, to: 'maintenance#create_schedule'
          delete 'schedules/:id', to: 'maintenance#delete_schedule'
          
          # Maintenance mode
          get :mode, to: 'maintenance#show_mode'
          post :mode, to: 'maintenance#update_mode'
          
          # System health
          get 'health/detailed', to: 'maintenance#detailed_health'
          get 'health/services', to: 'maintenance#service_health'
          
          # Database operations
          get 'database/stats', to: 'maintenance#database_stats'
          post 'database/analyze', to: 'maintenance#analyze_database'
          post 'operations/optimize', to: 'maintenance#optimize_database'
          
          # Scheduled tasks
          get :tasks, to: 'maintenance#list_tasks'
          post :tasks, to: 'maintenance#create_task'
          patch 'tasks/:id', to: 'maintenance#update_task'
          delete 'tasks/:id', to: 'maintenance#delete_task'
          post 'tasks/:id/execute', to: 'maintenance#execute_task'
        end

        # Rate Limiting management
        namespace :rate_limiting do
          get :statistics, to: 'rate_limiting#statistics'
          get :violations, to: 'rate_limiting#violations'
          get :status, to: 'rate_limiting#status'
          get 'limits/:identifier', to: 'rate_limiting#user_limits'
          delete 'limits/:identifier', to: 'rate_limiting#clear_user_limits'
          post :disable, to: 'rate_limiting#disable_temporarily'
          post :enable, to: 'rate_limiting#enable'
        end
      end
      
      # Email Settings endpoints (for worker service)
      resource :email_settings, only: [ :show, :update ] do
        post :test, on: :member
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
        get :live
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

      # Payment reconciliation endpoints (service-to-service)
      namespace :reconciliation do
        get :stripe_payments
        get :paypal_payments
        post :report
        post :corrections
        post :flags
        post :investigations
      end
      
      # Webhook sync endpoints (service-to-service)
      namespace :webhooks do
        namespace :stripe_sync, path: 'stripe' do
          post :invoice_paid
          post :invoice_failed
          post :subscription_updated
          post :subscription_canceled
          post :payment_succeeded
          post :payment_failed
          post :setup_intent_succeeded
          post :payment_method_attached
          post :payment_method_detached
          post :unhandled_event
          post :activate_subscription
        end
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

      # Jobs endpoint for worker service communication
      resources :jobs, only: [:create]
      
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
          delete '/', to: 'impersonations#destroy'
          get :history
          get :users, to: 'impersonations#impersonatable_users'
          post :validate, to: 'impersonations#validate_token'
          post :cleanup_expired, to: 'impersonations#cleanup_expired'
        end
      end

      # Marketplace endpoints
      resources :apps do
        collection do
          get :analytics, to: 'apps#analytics'
        end
        member do
          post :publish
          post :unpublish
          post :submit_for_review
          get :analytics
        end
        
        # Nested resources for app management
        resources :app_plans, except: [:index] do
          collection do
            get :index, to: 'app_plans#index'
            post :reorder
            get :compare
            get :analytics
          end
          member do
            post :activate
            post :deactivate
          end
        end
        
        resources :app_features, except: [:index] do
          collection do
            get :index, to: 'app_features#index'
            get :types
            get :dependencies
            post :validate_dependencies
            get :usage_report
          end
          member do
            post :enable_by_default
            post :disable_by_default
            post :duplicate
          end
        end

        resources :app_endpoints, except: [:index] do
          collection do
            get :index, to: 'app_endpoints#index'
          end
          member do
            post :activate
            post :deactivate
            post :test
            get :analytics
          end
        end

        resources :app_webhooks, except: [:index] do
          collection do
            get :index, to: 'app_webhooks#index'
          end
          member do
            post :activate
            post :deactivate
            post :test
            post :regenerate_secret
            get :deliveries
            get :analytics
          end
        end
        
        resource :marketplace_listing, except: [] do
          member do
            post :submit
            post :approve
            post :reject
            post :feature
            post :unfeature
            get :analytics
            post :screenshots
            delete :screenshots
            patch :screenshots
          end
        end
      end
      
      # Public marketplace endpoints (no authentication required)
      resources :marketplace_listings, only: [:index, :show] do
        collection do
          get :categories
        end
      end
      
      # App Subscriptions (user subscriptions to apps)
      resources :app_subscriptions, only: [:index, :show, :create, :update, :destroy] do
        member do
          post :pause
          post :resume
          post :cancel
          post :upgrade_plan
          post :downgrade_plan
          get :usage
          get :analytics
        end
        
        collection do
          get :active
          get :cancelled
          get :expired
        end
      end
      
      # App Reviews and Ratings
      resources :app_reviews, only: [:index, :show, :create, :update, :destroy] do
        member do
          post :mark_helpful
          post :mark_unhelpful
          post :flag_for_review
          post :approve_after_review
          post :remove_after_review
        end
        
        collection do
          get :by_app
          get :by_rating
          get :sentiment_analysis
          get :moderation_queue
        end
      end
      
      # Marketplace Categories (admin management)
      resources :marketplace_categories do
        member do
          post :activate
          post :deactivate
          post :reorder
        end
        
        collection do
          get :analytics
          post :bulk_reorder
        end
      end

      # System Management endpoints (admin only)
      resources :audit_logs, only: [:index, :show, :create] do
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
          post :health_test
        end
        collection do
          get :available_events, to: 'webhooks#available_events'
          get :deliveries, to: 'webhooks#delivery_history'
          get :stats
          post :retry_failed
          get :health, to: 'webhooks#health_check'
          get 'health/stats', to: 'webhooks#health_stats'
        end
      end

      # Version and health endpoints
      resource :version, only: [:show], controller: :version do
        get :full, on: :collection
        get :health, on: :collection
      end

      # Settings endpoints
      resource :settings, only: [:show, :update], controller: :settings do
        get :public, on: :collection
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

      # Metrics endpoints
      resources :metrics, only: [] do
        collection do
          get :prometheus
          get :health
          get :application
        end
      end

      # Worker management
      resources :workers do
        member do
          post :regenerate_token
          post :suspend
          post :activate
          post :revoke
          post :test_worker
          post :health_check
        end
        
        # Nested activities routes
        resources :activities, only: [:index, :show] do
          collection do
            get :summary
            delete :cleanup
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
  root to: proc { 
    version = File.exist?(Rails.root.join('..', 'VERSION')) ? 
              File.read(Rails.root.join('..', 'VERSION')).strip : '0.0.1'
    [ 200, {}, [ "Powernode API - Version #{version}" ] ] 
  }
end
