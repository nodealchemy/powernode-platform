# frozen_string_literal: true

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
      
      # Configuration endpoints (no authentication required)
      get :config, to: 'config#index'
      get 'config/allowed_hosts', to: 'config#allowed_hosts'
      
      # Public endpoints (no authentication required)
      get 'public/plans', to: 'plans#public_index'
      get 'public/footer', to: 'site_settings#public_footer'

      # Public status page endpoints
      namespace :public do
        get 'status', to: 'status#index'
        get 'status/summary', to: 'status#summary'
        get 'status/history', to: 'status#history'
      end
      
      # Internal API for worker service
      namespace :internal do
        resources :users, only: [:show]
        resources :accounts, only: [:show]
        resources :invitations, only: [:show]

        # Background job tracking
        resources :jobs, only: [:show, :update]

        # Template installations (AI workflows)
        resources :template_installations, only: [] do
          member do
            post :update
          end
        end

        # Webhook deliveries
        resources :webhook_deliveries, only: [:show, :update] do
          member do
            patch :increment_attempt
          end
        end

        # Review notifications
        resources :review_notifications, only: [:show, :update]

        # MCP (Model Context Protocol) internal endpoints
        resources :mcp_servers, only: [:index, :show, :update] do
          member do
            post :health_result
            post :register_tools
          end
        end
        resources :mcp_tool_executions, only: [:show, :update]

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
            post :test_results
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

        # Permissions endpoint (separate from JWT payload)
        get :permissions, to: "permissions#index"
        get "permissions/check", to: "permissions#check"
      end

      # OAuth 2.0 Provider (Doorkeeper) - Standard OAuth endpoints
      use_doorkeeper do
        # Skip default controllers, we use custom API controllers
        skip_controllers :applications, :authorized_applications
      end

      # OAuth Applications Management API
      namespace :oauth do
        resources :applications do
          member do
            post :regenerate_secret
            post :suspend
            post :activate
            post :revoke
            get :tokens
            delete :tokens, to: 'applications#revoke_tokens'
          end
        end
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

      # Worker file processing endpoints (for worker service)
      namespace :worker do
        resources :files, only: [:show, :update], controller: 'worker/worker_files' do
          member do
            get :download
            post :processed
          end
        end

        resources :processing_jobs, only: [:show, :update], controller: 'worker/processing_jobs'
      end

      # Knowledge Base endpoints (public access + editing for authorized users)
      namespace :kb do
        resources :categories do
          collection do
            get :tree
          end
        end
        
        resources :articles do
          collection do
            get :search
            get :analytics
            patch :bulk, to: 'articles#bulk_update'
            delete :bulk, to: 'articles#bulk_delete'
          end
          member do
            post :publish
            post :unpublish
          end
          resources :comments, only: [:index, :create]
        end
        
        resources :comments, only: [:show] do
          collection do
            get :moderate
          end
          member do
            post :approve
            post :reject
            post :spam
            delete :destroy
          end
        end
        
        resources :tags, only: [:index] do
          member do
            get :articles
          end
        end
        
        resources :attachments, only: [:show, :create, :destroy]
      end

      # Protected resources (will be added later)
      resources :accounts, only: [ :show, :update ] do
        collection do
          get :accessible
          post :switch
          post :switch_to_primary
        end
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

      # Invitation management
      resources :invitations, only: [:index, :show, :create, :update, :destroy] do
        member do
          post :resend    # Resend invitation email
          post :cancel    # Cancel pending invitation
        end

        collection do
          post :accept    # Public endpoint - accept invitation via token
        end
      end

      resources :users do
        collection do
          get :stats
        end
      end

      # Notifications
      resources :notifications, only: [:index, :show, :destroy] do
        collection do
          get :unread_count
          post :mark_all_read
          delete :dismiss_all
        end
        member do
          put :read, action: :mark_as_read
          put :unread, action: :mark_as_unread
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
      
      # Site settings management (admin only)
      resources :site_settings do
        collection do
          get :footer
          put :bulk_update
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

        # Circuit Breakers management
        resources :circuit_breakers do
          member do
            post :reset
            get :health
            get :events
          end
        end

        # Validation Rules management
        resources :validation_rules do
          member do
            patch :enable
            patch :disable
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
          get :tiers, to: 'rate_limiting#tiers'
          get :accounts, to: 'rate_limiting#accounts_usage'
          get 'limits/:identifier', to: 'rate_limiting#user_limits'
          delete 'limits/:identifier', to: 'rate_limiting#clear_user_limits'
          post :disable, to: 'rate_limiting#disable_temporarily'
          post :enable, to: 'rate_limiting#enable'

          # Account tier management
          scope 'accounts/:account_id' do
            get :statistics, to: 'rate_limiting#account_statistics', as: :account_statistics
            post :override_tier, to: 'rate_limiting#override_tier'
            delete :override_tier, to: 'rate_limiting#clear_tier_override'
          end
        end

        # Database health monitoring (for worker service)
        namespace :database do
          get :pool_stats
          get :ping
          get :health
        end

        # Review Moderation
        resource :review_moderation, only: [] do
          collection do
            get :queue
            post :bulk_action
            get :analytics
            get :settings
            post :update_settings
          end

          member do
            get 'history/:review_id', to: 'review_moderation#history'
          end
        end

        # Reverse Proxy URL Configuration
        resources :proxy_settings, only: [] do
          collection do
            get :url_config
            put :url_config, action: :update_url_config
            post :validate_host
            post :test_headers
            get :current_detection
            post :trusted_hosts, action: :add_trusted_host
            delete 'trusted_hosts/:pattern', action: :remove_trusted_host
            put 'trusted_hosts/reorder', action: :reorder_trusted_hosts
            post :wildcard_patterns, action: :add_wildcard_pattern
            delete 'wildcard_patterns/:pattern', action: :remove_wildcard_pattern
            put 'wildcard_patterns/reorder', action: :reorder_wildcard_patterns
            get :export
            post :import
          end
        end
      end
      
      # Email Settings endpoints (for worker service)
      resource :email_settings, only: [ :show, :update ] do
        post :test, on: :collection
      end

      # Payment Gateways management (admin only)
      resources :payment_gateways, only: [ :index, :show, :update ] do
        member do
          post :test_connection
          get :webhook_events
          get :transactions
        end
      end

      # Gateway connection jobs (for async testing)
      resources :gateway_connection_jobs, only: [:show, :update]

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

      # Unified Marketplace endpoints (apps, plugins, templates in one interface)
      namespace :marketplace do
        get 'unified', to: 'unified#index'
        get 'unified/installations', to: 'unified#installations'
        get 'unified/:type/:id', to: 'unified#show'
        post 'unified/:type/:id/install', to: 'unified#install'
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
      
      # Enhanced App reviews with comprehensive functionality
      resources :apps, only: [] do
        resources :app_reviews, path: 'reviews', only: [:index, :create] do
          collection do
            get :summary
          end
        end
      end

      resources :app_reviews, path: 'reviews', only: [:show, :update, :destroy] do
        member do
          post :vote
          post :flag
          post :moderate
        end
        
        resources :review_responses, path: 'responses', only: [:index, :create]
      end

      resources :review_responses, only: [:show, :update, :destroy] do
        member do
          post :approve
          post :reject
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
          get :failed_deliveries, to: 'webhooks#failed_deliveries'
          get :stats
          post :retry_failed
          get :health, to: 'webhooks#health_check'
          get 'health/stats', to: 'webhooks#health_stats'
        end
        resources :deliveries, only: [:index, :show], controller: 'webhooks' do
          member do
            post :retry, to: 'webhooks#retry_delivery'
          end
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

      # MCP (Model Context Protocol) OAuth callback (outside server-specific routes)
      get 'mcp/oauth/callback', to: 'mcp_oauth#callback', as: :mcp_oauth_callback

      # MCP (Model Context Protocol) resources
      resources :mcp_servers do
        collection do
          get :for_workflow_builder
        end
        member do
          post :connect
          post :disconnect
          post :health_check
          post :discover_tools

          # OAuth endpoints for MCP server authentication
          namespace :oauth do
            post '/', to: 'mcp_oauth#authorize', as: :authorize
            get :status, to: 'mcp_oauth#status'
            delete :disconnect, to: 'mcp_oauth#disconnect'
            post :refresh, to: 'mcp_oauth#refresh'
          end
        end

        resources :mcp_tools, only: [:index, :show] do
          member do
            post :execute
            get :stats
          end

          resources :mcp_tool_executions, path: 'executions', only: [:index, :show] do
            member do
              post :cancel
            end
          end
        end
      end

      # Knowledge Base endpoints with integrated editing
      namespace :kb do
        resources :categories do
          collection do
            get :tree
          end
        end
        resources :articles do
          collection do
            get :search
            get :analytics
            patch :bulk, to: 'articles#bulk_update'
            delete :bulk, to: 'articles#bulk_delete'
          end
          member do
            post :publish
            post :unpublish
          end
          resources :comments, only: [:index, :create]
        end
        resources :tags, only: [:index] do
          member do
            get :articles
          end
        end
        resources :comments do
          member do
            post :approve
            post :reject
            post :spam
          end
        end
        resources :attachments, only: [:create, :destroy]
      end

      # Worker management
      resources :workers do
        collection do
          get :stats
        end
        member do
          get :current_token
          post :regenerate_token
          post :suspend
          post :activate
          post :revoke
          post :test_worker
          post :test_results
          post :health_check
          get :config
          put :config, action: :update_config
          post 'config/reset', action: :reset_config
        end

        # Nested activities routes
        resources :activities, only: [:index, :show] do
          collection do
            get :summary
            delete :cleanup
          end
        end
      end

      # ===================================================================
      # AI ORCHESTRATION SYSTEM - CONSOLIDATED CONTROLLERS
      # ===================================================================
      # 6 RESTful resource controllers replacing 25+ old controllers
      # See: docs/platform/AI_ORCHESTRATION_CLEAN_MIGRATION_PLAN.md
      # ===================================================================

      namespace :ai do
        # ===================================================================
        # 1. WORKFLOWS CONTROLLER - Consolidated workflow management
        # ===================================================================

        # Lookup endpoint for worker service (finds workflow by run_id)
        get 'workflows/runs/lookup/:run_id', to: 'workflows#runs_lookup'

        resources :workflows do
          member do
            post :execute
            post :duplicate
            get :validate
            get :export
          end

          collection do
            post :import
            get :statistics
            get :templates
          end

          # Nested runs (replaces workflow_runs, workflow_executions, workflow_node_executions)
          # Explicitly map REST actions to prefixed controller methods
          get 'runs', to: 'workflows#runs_index'
          get 'runs/:run_id', to: 'workflows#run_show', as: :workflow_run
          patch 'runs/:run_id', to: 'workflows#run_update'
          put 'runs/:run_id', to: 'workflows#run_update'
          delete 'runs/:run_id', to: 'workflows#run_destroy'
          delete 'runs', to: 'workflows#runs_destroy_all', as: :destroy_all_workflow_runs

          # Run-specific member actions
          post 'runs/:run_id/cancel', to: 'workflows#run_cancel', as: :cancel_workflow_run
          post 'runs/:run_id/retry', to: 'workflows#run_retry', as: :retry_workflow_run
          post 'runs/:run_id/pause', to: 'workflows#run_pause', as: :pause_workflow_run
          post 'runs/:run_id/resume', to: 'workflows#run_resume', as: :resume_workflow_run
          get 'runs/:run_id/logs', to: 'workflows#run_logs', as: :workflow_run_logs
          get 'runs/:run_id/node_executions', to: 'workflows#run_node_executions', as: :workflow_run_node_executions
          get 'runs/:run_id/metrics', to: 'workflows#run_metrics', as: :workflow_run_metrics
          get 'runs/:run_id/download', to: 'workflows#run_download', as: :download_workflow_run
          post 'runs/:run_id/process', to: 'workflows#run_process', as: :process_workflow_run
          post 'runs/:run_id/broadcast', to: 'workflows#run_broadcast', as: :broadcast_workflow_run
          post 'runs/:run_id/check_timeout', to: 'workflows#run_check_timeout', as: :check_timeout_workflow_run

          # Nested schedules
          resources :schedules, controller: 'workflows' do
            member do
              post :activate
              post :deactivate
              post :trigger_now
              get :execution_history
            end

            collection do
              get :due
              post :validate_cron
            end
          end

          # Nested triggers
          resources :triggers, controller: 'workflows' do
            member do
              post :activate
              post :deactivate
              post :test
            end

            collection do
              post :webhook_endpoint, path: 'webhook'
              post :event_endpoint, path: 'event'
            end
          end

          # Nested versions
          resources :versions, controller: 'workflows' do
            member do
              post :restore
              get :compare
            end
          end

          # Nested validations
          resources :validations, controller: 'workflow_validations', only: [:index, :show, :create] do
            collection do
              get :latest
              post :auto_fix
              post 'auto_fix/:issue_code', action: :auto_fix_single
              get :preview_fixes
            end
          end

          # Workflow-specific actions
          member do
            post :dry_run, action: :workflows_dry_run
            get 'dry_run/validate', action: :workflows_dry_run_validate
          end
        end

        # ===================================================================
        # 2. AGENTS CONTROLLER - Consolidated agent management
        # ===================================================================
        resources :agents do
          member do
            post :execute
            post :clone
            post :test
            get :validate
            post :pause
            post :resume
            post :archive
            get :stats
            get :analytics
          end

          collection do
            get :my_agents
            get :public_agents
            get :agent_types
            get :statistics
          end

          # Nested executions (replaces ai_agent_executions)
          # Explicitly map REST actions to prefixed controller methods
          get 'executions', to: 'agents#executions_index'
          get 'executions/:execution_id', to: 'agents#execution_show', as: :agent_execution
          patch 'executions/:execution_id', to: 'agents#execution_update'
          put 'executions/:execution_id', to: 'agents#execution_update'
          delete 'executions/:execution_id', to: 'agents#execution_destroy'
          post 'executions/:execution_id/cancel', to: 'agents#execution_cancel', as: :cancel_agent_execution
          post 'executions/:execution_id/retry', to: 'agents#execution_retry', as: :retry_agent_execution
          get 'executions/:execution_id/logs', to: 'agents#execution_logs', as: :agent_execution_logs

          # Nested conversations (replaces ai_conversations)
          resources :conversations do
            member do
              post :send_message
              post :pause
              post :resume
              post :complete
              post :archive
              get :messages
              get :export
            end

            collection do
              get :active
              post :start_conversation
            end

            # Nested messages
            resources :messages, controller: 'agents' do
              member do
                patch :edit_content
                post :regenerate
                post :rate
              end
            end
          end
        end

        # ===================================================================
        # 3. PROVIDERS CONTROLLER - Consolidated provider management
        # ===================================================================
        resources :providers do
          member do
            post :test_connection
            post :sync_models
            get :models
            get :usage_summary
            get :check_availability
          end

          collection do
            get :available
            get :statistics
            post :setup_defaults
            post :test_all
          end

          # Nested credentials (replaces ai_provider_credentials)
          resources :credentials, controller: 'providers' do
            collection do
              post :test_all
            end

            member do
              post :test, action: :credential_test
              post :make_default, action: :credential_make_default
              post :rotate, action: :credential_rotate
            end
          end
        end

        # ===================================================================
        # 4. GLOBAL CONVERSATIONS CONTROLLER - Cross-agent conversation management
        # ===================================================================
        resources :conversations, only: [:index, :show, :update, :destroy] do
          member do
            post :archive
            post :unarchive
            post :duplicate
            get :stats
          end
        end

        # ===================================================================
        # 5. MONITORING CONTROLLER - Consolidated monitoring & health
        # ===================================================================
        resource :monitoring, only: [], controller: :monitoring do
          get :dashboard
          get :metrics
          get :overview
          get :health
          get 'health/detailed', action: :health_detailed
          get 'health/connectivity', action: :health_connectivity
          get :alerts
          post 'alerts/check', action: :alerts_check

          # Circuit breakers (replaces circuit_breakers_controller)
          get :circuit_breakers, action: :circuit_breakers_index
          get 'circuit_breakers/:service_name', action: :circuit_breaker_show
          post 'circuit_breakers/:service_name/reset', action: :circuit_breaker_reset
          post 'circuit_breakers/:service_name/open', action: :circuit_breaker_open
          post 'circuit_breakers/:service_name/close', action: :circuit_breaker_close
          post 'circuit_breakers/reset_all', action: :circuit_breakers_reset_all
          get 'circuit_breakers/category/:category', action: :circuit_breakers_category
          post 'circuit_breakers/category/:category/reset', action: :circuit_breakers_category_reset
          get 'circuit_breakers/monitor', action: :circuit_breakers_monitor

          # Real-time monitoring
          post :broadcast, action: :broadcast_metrics
          post :start, action: :start_monitoring
          post :stop, action: :stop_monitoring
        end

        # ===================================================================
        # 6. ANALYTICS CONTROLLER - Consolidated analytics & reporting
        # ===================================================================
        resource :analytics, only: [] do
          get :dashboard
          get :overview
          get :metrics
          get :real_time
          get :cost_analysis
          get :performance_analysis
          get :performance
          get :costs
          get :usage
          get :insights
          get :recommendations
          get :trends
          post :export
          get :formats, action: :export_formats

          # Workflow/Agent specific analytics
          get 'workflows/:workflow_id', action: :workflow_analytics
          get 'agents/:agent_id', action: :agent_analytics

          # Reports system (custom actions)
          get :reports, action: :reports_index
          post :reports, action: :report_create
          get 'reports/templates', action: :report_templates
          get 'reports/:id', action: :report_show
          delete 'reports/:id', action: :report_cancel
          get 'reports/:id/download', action: :report_download

          # Reports (replaces reports_controller) - DEPRECATED nested resource
          resources :reports, controller: 'analytics' do
            member do
              post :generate
              post :schedule
              post :share
              get :download
            end

            collection do
              get :types
            end
          end
        end

        # ===================================================================
        # 7. VALIDATION STATISTICS - Aggregate validation analytics
        # ===================================================================
        resource :validation_statistics, only: [:show] do
          get :common_issues
          get :health_distribution
        end

        # ===================================================================
        # 8. MARKETPLACE CONTROLLER - Consolidated marketplace & templates
        # ===================================================================
        # Marketplace Templates - No namespace to match controller location at Api::V1::Ai::MarketplaceController
        # Note: Using standard RESTful action names (index, show, create, update, destroy)
        get 'marketplace/templates', controller: 'marketplace', action: :index, as: :templates_index
        get 'marketplace/templates/:id', controller: 'marketplace', action: :show, as: :template_show
        post 'marketplace/templates', controller: 'marketplace', action: :create, as: :templates_create
        patch 'marketplace/templates/:id', controller: 'marketplace', action: :update, as: :template_update
        put 'marketplace/templates/:id', controller: 'marketplace', action: :update
        delete 'marketplace/templates/:id', controller: 'marketplace', action: :destroy, as: :template_destroy

        # Template member actions
        post 'marketplace/templates/:id/install', controller: 'marketplace', action: :install, as: :install_template
        post 'marketplace/templates/:id/publish', controller: 'marketplace', action: :publish, as: :publish_template
        get 'marketplace/templates/:id/validate', controller: 'marketplace', action: :validate_template, as: :validate_template
        post 'marketplace/templates/:id/rate', controller: 'marketplace', action: :rate, as: :rate_template
        get 'marketplace/templates/:id/analytics', controller: 'marketplace', action: :template_analytics, as: :template_analytics

        # Template collection actions
        post 'marketplace/templates/from_workflow', controller: 'marketplace', action: :create_from_workflow, as: :create_from_workflow
        post 'marketplace/templates/publish_workflow', controller: 'marketplace', action: :publish_workflow, as: :publish_workflow_template
        get 'marketplace/templates/featured', controller: 'marketplace', action: :featured, as: :featured_templates
        get 'marketplace/templates/popular', controller: 'marketplace', action: :popular, as: :popular_templates
        get 'marketplace/templates/categories', controller: 'marketplace', action: :categories, as: :template_categories
        get 'marketplace/templates/tags', controller: 'marketplace', action: :tags, as: :template_tags
        get 'marketplace/templates/statistics', controller: 'marketplace', action: :statistics, as: :template_statistics

        # Marketplace general actions
        get 'marketplace/discover', controller: 'marketplace', action: :discover
        post 'marketplace/search', controller: 'marketplace', action: :search
        get 'marketplace/recommendations', controller: 'marketplace', action: :recommendations
        post 'marketplace/compare', controller: 'marketplace', action: :compare

        # Installations - Note: Controller uses custom action names (installations_index, installation_show, etc.)
        get 'marketplace/installations', controller: 'marketplace', action: :installations_index, as: :installations_index
        get 'marketplace/installations/:id', controller: 'marketplace', action: :installation_show, as: :installation_show
        delete 'marketplace/installations/:id', controller: 'marketplace', action: :installation_destroy, as: :installation_destroy

        # Updates
        get 'marketplace/updates', controller: 'marketplace', action: :check_updates
        post 'marketplace/updates/apply', controller: 'marketplace', action: :apply_updates

        # ===================================================================
        # 7. AGENT TEAMS CONTROLLER - CrewAI-style team orchestration
        # ===================================================================
        resources :agent_teams do
          member do
            post :execute
            post :execute_complete      # Internal - called by worker
            post :execute_failed        # Internal - called by worker

            # Team members management
            post 'members', to: 'agent_teams#add_member'
            delete 'members/:member_id', to: 'agent_teams#remove_member'
          end

          collection do
            get :statistics
          end
        end
      end

      # ===================================================================
      # FILE MANAGEMENT SYSTEM - Universal file storage
      # ===================================================================
      # Multi-provider file storage system with workflow integration
      # ===================================================================

      # Files management endpoints
      resources :files, except: [:new, :edit] do
        member do
          get :download
          get :download_public, path: 'public'  # Public endpoint for serving public files (no auth)
          post :restore
          post :share
          post :create_version, path: 'versions'
          post :add_tags, path: 'tags'
          delete :remove_tags, path: 'tags'
        end

        collection do
          get :stats
        end
      end

      # Alias for upload
      post 'files/upload', to: 'files#upload'

      # Storage providers configuration endpoints
      resources :storage_providers, path: 'storage', except: [:new, :edit] do
        member do
          post :test_connection, path: 'test'
          get :health_check, path: 'health'
          post :set_default
          post :initialize_storage, path: 'initialize'
          get :list_files, path: 'files'
        end

        collection do
          get :supported
          get :aggregate_stats, path: 'stats'
        end
      end

      # ===================================================================
      # PLUGIN SYSTEM - Universal plugin architecture
      # ===================================================================
      # Platform-agnostic plugin system supporting AI providers, workflow nodes,
      # and extensible plugin types with marketplace management
      # ===================================================================

      resources :plugin_marketplaces do
        member do
          post :sync
        end
      end

      resources :plugins do
        member do
          post :install
          delete :uninstall
        end

        collection do
          get :search
          get :by_capability
        end
      end

      resources :plugin_installations do
        member do
          post :activate
          post :deactivate
          patch :configure
          post :set_credential
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
