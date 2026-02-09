# frozen_string_literal: true

Rails.application.routes.draw do
  # OpenAPI/Swagger documentation
  mount Rswag::Ui::Engine => "/api-docs"
  mount Rswag::Api::Engine => "/api-docs"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # =========================================================================
  # A2A Protocol - Well-Known Endpoints (outside API namespace)
  # =========================================================================
  # These endpoints implement the A2A protocol for agent-to-agent discovery
  # and communication. They must be at the root level per the A2A spec.
  # =========================================================================
  scope "/.well-known" do
    get "agent-card.json", to: "well_known#agent_card"
  end

  # A2A JSON-RPC 2.0 endpoint
  post "/a2a", to: "a2a#handle"
  get "/a2a", to: "a2a#info"
  post "/a2a/stream", to: "a2a#stream"

  # Health check endpoints (global, outside API namespace)
  get :health, to: "health#index"
  get "health/detailed", to: "health#detailed"
  get "health/ready", to: "health#ready"
  get "health/live", to: "health#live"

  # API Routes
  namespace :api do
    # =========================================================================
    # BaaS API - Billing-as-a-Service for external customers
    # =========================================================================
    namespace :baas do
      namespace :v1 do
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
    end

    namespace :v1 do
      # Health check endpoint for load balancers
      get :health, to: proc { [ 200, {}, [ { status: "ok" }.to_json ] ] }

      # Worker test endpoints
      post "worker/ping", to: "worker_test#ping"
      post "worker/process_job", to: "worker_test#process_job"

      # E2E test endpoints (development/test only)
      post "test/reset", to: "test#reset"
      post "test/seed", to: "test#seed"

      # CSRF token endpoint for authenticated users
      get :csrf_token, to: "csrf#token"

      # Configuration endpoints (no authentication required)
      get :config, to: "config#index"
      get "config/allowed_hosts", to: "config#allowed_hosts"

      # Public endpoints (no authentication required)
      get "public/plans", to: "plans#public_index"
      get "public/footer", to: "site_settings#public_footer"

      # Public status page endpoints
      namespace :public do
        get "status", to: "status#index"
        get "status/summary", to: "status#summary"
        get "status/history", to: "status#history"
      end

      # DevOps Approval Tokens (public, token-based auth)
      namespace :devops do
        resources :approval_tokens, only: [ :show ], param: :token do
          member do
            post :approve
            post :reject
          end
        end
      end

      # AI Workflow Approval Tokens (public, token-based auth)
      namespace :ai_workflows do
        resources :approval_tokens, only: [ :show ], param: :token do
          member do
            post :approve
            post :reject
          end
        end
      end

      # Internal API for worker service
      namespace :internal do
        resources :users, only: [ :show ]
        resources :accounts, only: [ :show ]
        resources :invitations, only: [ :show ]

        # Background job tracking
        resources :jobs, only: [ :show, :update ]

        # Webhook deliveries
        resources :webhook_deliveries, only: [ :show, :update ] do
          member do
            patch :increment_attempt
          end
        end

        # Webhook endpoints (for circuit breaker management)
        resources :webhook_endpoints, only: [ :show ] do
          member do
            post :record_success
            post :record_failure
          end
        end

        # Review notifications
        resources :review_notifications, only: [ :show, :update ]

        # DevOps Approval Tokens (for worker service)
        resources :approval_tokens, only: [ :show ], param: :step_execution_id do
          member do
            post :create_tokens
          end
        end

        # MCP (Model Context Protocol) internal endpoints
        resources :mcp_servers, only: [ :index, :show, :update ] do
          member do
            post :health_result
            post :register_tools
          end
        end
        resources :mcp_tool_executions, only: [ :show, :update ]

        # Metrics tracking for worker jobs
        namespace :metrics do
          post :jobs
          post :errors
          post :custom
        end

        # Worker status and health
        resources :workers, only: [ :index, :show ] do
          member do
            post :ping
            post :test_results
            get :status
          end
        end

        # Reverse proxy internal operations
        scope :reverse_proxy do
          post :validate, to: "reverse_proxy#validate_config"
          post :test_connectivity, to: "reverse_proxy#test_connectivity"
          post :generate_config, to: "reverse_proxy#generate_config"
          post :service_discovery, to: "reverse_proxy#service_discovery"
          post :health_check, to: "reverse_proxy#health_check"
          post :validate_services, to: "reverse_proxy#validate_services"
        end

        # GDPR Compliance endpoints for worker service
        resources :data_deletion_requests, only: [ :show, :create, :update ]
        resources :data_export_requests, only: [ :show, :create, :update ]

        # Account termination processing
        resources :account_terminations, only: [ :index, :show, :update ]

        # Data retention policies
        resources :data_retention_policies, only: [ :index ]

        # User data export endpoints
        scope "users/:user_id" do
          get "export/profile", to: "data_exports#user_profile"
          get "export/activity", to: "data_exports#user_activity"
          get "export/audit_logs", to: "data_exports#user_audit_logs"
          get "export/consents", to: "data_exports#user_consents"
          patch :anonymize, to: "users#anonymize"
          patch :anonymize_audit_logs, to: "users#anonymize_audit_logs"
          delete :consents, to: "users#delete_consents"
          delete :terms_acceptances, to: "users#delete_terms_acceptances"
          delete :password_histories, to: "users#delete_password_histories"
          delete :roles, to: "users#delete_roles"
        end

        # Account data export endpoints
        scope "accounts/:account_id" do
          get "export/payments", to: "data_exports#account_payments"
          get "export/invoices", to: "data_exports#account_invoices"
          get "export/subscriptions", to: "data_exports#account_subscriptions"
          get "export/files", to: "data_exports#account_files"
          get :users, to: "accounts#users"
          patch :anonymize_audit_logs, to: "accounts#anonymize_audit_logs"
          patch :anonymize_payments, to: "accounts#anonymize_payments"
          delete :files, to: "accounts#delete_files"
          delete :api_keys, to: "accounts#delete_api_keys"
          delete :webhooks, to: "accounts#delete_webhooks"
          delete :data_export_requests, to: "accounts#delete_data_export_requests"
          delete :data_deletion_requests, to: "accounts#delete_data_deletion_requests"
        end

        # Internal services namespace for worker service communication
        namespace :services do
          post :health_check
          post :generate_config
          post :service_discovery
          post :validate
          post :test_connectivity
          post :validate_services
        end

        # Maintenance internal endpoints (for worker service)
        scope :maintenance do
          # Database backups
          get "backups/:id", to: "maintenance#show_backup"
          patch "backups/:id", to: "maintenance#update_backup"
          post "backups/cleanup", to: "maintenance#cleanup_old_backups"

          # Database restores
          get "restores/:id", to: "maintenance#show_restore"
          patch "restores/:id", to: "maintenance#update_restore"

          # Scheduled tasks
          get :scheduled_tasks, to: "maintenance#list_due_tasks"
          post "scheduled_tasks/:id/executions", to: "maintenance#create_task_execution"
          patch "task_executions/:id", to: "maintenance#update_task_execution"
        end

        # Git provider internal endpoints (for worker service)
        namespace :git do
          resources :webhook_events, only: [ :show, :update ] do
            member do
              patch :processing
              patch :processed
              patch :failed
              post :trigger_workflows
            end
          end

          resources :repositories, only: [ :show, :create, :update ] do
            member do
              post :sync_branches
              post :sync_commits
              post :sync_pipelines
            end
          end

          resources :credentials, only: [ :index, :show ] do
            member do
              get :decrypted
              get :repositories
            end
          end

          resources :pipelines, only: [ :show, :update ] do
            member do
              post :sync_jobs
            end
          end

          # Job logs broadcasting (for WebSocket streaming from worker)
          resources :job_logs, only: [] do
            member do
              post :broadcast
              post :error
              post :status
            end
          end

          # Runners sync (for worker service)
          resources :runners, only: [] do
            collection do
              post :sync
            end
            member do
              put :status, action: :update_status
              post :job_completed
            end
          end
        end

        # Internal subscriptions for worker dunning
        resources :subscriptions, only: [ :show ] do
          member do
            post :dunning
          end
        end

        # Email sending for worker notifications
        namespace :emails do
          post :review_notification
          post :security_alert
        end

        # Notifications for worker service
        resources :notifications, only: [ :create ] do
          collection do
            post :send, action: :send_notification
            post :security_alert
          end
        end

        # DevOps internal endpoints for worker service
        namespace :devops do
          resources :pipeline_runs, only: [ :show, :update ]
          resources :step_executions, only: [ :show, :create, :update ]

          # Approval token management for worker service
          resources :approval_tokens, only: [] do
            collection do
              post :expire_stale
              get :pending_count
            end
          end

          # Docker Swarm internal endpoints (worker communication)
          namespace :swarm do
            resources :clusters, only: [:index] do
              member do
                get :connection
                post :sync_results
                post :health_results
              end
            end
            resources :deployments, only: [:update]
            resources :events, only: [:create]
          end

          # Docker Host internal endpoints (worker communication)
          scope :docker, as: :docker do
            get "hosts", to: "docker#index", as: :hosts
            get "hosts/:id/connection", to: "docker#connection", as: :host_connection
            post "hosts/:id/sync_results", to: "docker#sync_results", as: :host_sync_results
            post "hosts/:id/health_results", to: "docker#health_results", as: :host_health_results
            post "events", to: "docker#create_event", as: :events
          end
        end

        # AI Workflow approval management for worker service
        resources :ai_workflow_approvals, only: [ :show ], param: :node_execution_id do
          member do
            post :create_tokens
          end
          collection do
            post :expire_stale
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

        # Internal AI endpoints (for worker service)
        namespace :ai do
          resources :skills, only: [] do
            collection do
              post :seed_system
            end
            member do
              post :record_usage
              post :refresh_connectors
            end
          end

          # Discovery data endpoints (worker → server)
          get "discovery/mcp_servers", to: "discovery#mcp_servers"
          get "discovery/docker_hosts", to: "discovery#docker_hosts"
          get "discovery/swarm_clusters", to: "discovery#swarm_clusters"

          # Discovery callbacks (worker → server)
          post "discovery/:scan_id/complete", to: "discovery#complete"
          post "discovery/:scan_id/failed", to: "discovery#failed"

          # Code review callbacks (worker → server)
          post "code_reviews/:review_id/comments", to: "code_reviews#create_comments"

          # Team data endpoints (worker → server)
          get "teams/:team_id", to: "teams#show"
          get "agents", to: "teams#agents"

          # Team optimization callbacks (worker → server)
          post "teams/:team_id/optimization_results", to: "teams#optimization_results"

          # Memory pool data endpoints (worker → server)
          get "memory_pools/expired", to: "memory_pools#expired"
          delete "memory_pools/:id", to: "memory_pools#destroy"

          # Memory pool cleanup callbacks (worker → server)
          post "memory_pools/cleanup_results", to: "memory_pools#cleanup_results"
        end

        # Container execution callbacks for Gitea workflow
        scope "container_executions/:execution_id" do
          post :complete, to: "container_executions#complete"
          post :status, to: "container_executions#status"
          post :logs, to: "container_executions#logs"
          post :resource_usage, to: "container_executions#resource_usage"
          post :security_violation, to: "container_executions#security_violation"
          get "/", to: "container_executions#show"
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

      # Privacy and GDPR compliance endpoints
      namespace :privacy do
        get :dashboard
        get :consents
        put :consents, action: :update_consents
        post :export, action: :request_export
        get :exports, action: :export_requests
        get "exports/:id/download", action: :download_export
        post :deletion, action: :request_deletion
        get :deletion, action: :deletion_request_status
        delete "deletion/:id", action: :cancel_deletion
        get :terms, action: :terms_status
        post "terms/:document_type/accept", action: :accept_terms
        get :cookies, action: :cookie_preferences
        put :cookies, action: :update_cookie_preferences
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
            delete :tokens, to: "applications#revoke_tokens"
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

      # ===================================================================
      # CHAT GATEWAY - Multi-platform chat integration
      # ===================================================================
      # Connects external chat platforms (Telegram, Discord, Slack, etc.)
      # to AI agents via A2A protocol
      # ===================================================================

      namespace :chat do
        # Webhook endpoints (public, token-authenticated)
        scope :webhooks do
          post ":token", to: "webhooks#receive", as: :webhook_receive
          get ":token/verify", to: "webhooks#verify", as: :webhook_verify
        end

        # Channel management
        resources :channels do
          member do
            post :connect
            post :disconnect
            post :test
            post :regenerate_token
            get :sessions
            get :metrics
          end

          collection do
            get :platforms
          end
        end

        # Session management
        resources :sessions do
          member do
            post :transfer
            post :close
            get :messages
            post :messages, action: :send_message
          end

          collection do
            get :active
            get :stats
          end
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
        resources :files, only: [ :show, :update ], controller: "worker_files" do
          member do
            get :download
            post :processed
          end
        end

        resources :processing_jobs, only: [ :show, :update ], controller: "processing_jobs"
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
            patch :bulk, to: "articles#bulk_update"
            delete :bulk, to: "articles#bulk_delete"
          end
          member do
            post :publish
            post :unpublish
          end
          resources :comments, only: [ :index, :create ]
        end

        resources :comments, only: [ :show ] do
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

        resources :tags, only: [ :index ] do
          member do
            get :articles
          end
        end

        resources :attachments, only: [ :show, :create, :destroy ]
      end

      # Protected resources (will be added later)
      resources :accounts, only: [ :show, :update ] do
        collection do
          get :accessible
          post :switch
          post :switch_to_primary
        end
        resources :delegations, only: [ :index, :create, :show, :update, :destroy ] do
          collection do
            get :available_permissions
          end
          member do
            patch :activate
            patch :deactivate
            patch :revoke
            post :permissions, to: "delegations#add_permission"
            delete "permissions/:permission_id", to: "delegations#remove_permission"
          end
        end
      end

      # Invitation management
      resources :invitations, only: [ :index, :show, :create, :update, :destroy ] do
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
        member do
          put :suspend
          put :activate
          put :unlock
          post :reset_password
          post :resend_verification
        end
      end

      # Notifications
      resources :notifications, only: [ :index, :show, :destroy ] do
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
          post "assign_to_user/:user_id", action: :assign_to_user
          delete "remove_from_user/:user_id", action: :remove_from_user
        end
      end
      resources :permissions, only: [ :index, :show ]

      # Plans management (admin only for create/update/delete)
      resources :plans do
        collection do
          get :status
        end
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
        get :security, on: :member, action: :security_config
        put :security, on: :member, action: :update_security_config
        post "security/test", on: :member, action: :test_security_config
        post "security/regenerate_jwt_secret", on: :member, action: :regenerate_jwt_secret
        delete "security/blacklisted_tokens", on: :member, action: :clear_blacklisted_tokens
        get "security/blacklist_stats", on: :member, action: :blacklist_statistics
        get "security/audit_summary", on: :member, action: :security_audit_summary
      end

      # Services Configuration (system-level)
      resource :services, only: [ :show, :update ], controller: "services" do
        post :test_configuration, on: :member
        post :generate_config, on: :member
        get :health_check, on: :member
        get :status, on: :member

        # Service Discovery endpoints
        get :discovered_services, on: :member
        post :service_discovery, on: :member
        post :add_discovered_service, on: :member
        get "health_history/:service_name", to: "services#health_history", on: :member
        put "health_config/:service_name", to: "services#update_health_config", on: :member

        # Service Management endpoints
        post :test_service, on: :member
        post :validate_service, on: :member
        get :service_templates, on: :member
        post :duplicate_service, on: :member
        get "export_services/:environment", to: "services#export_services", on: :member
        post :import_services, on: :member

        resources :url_mappings, only: [ :create, :destroy ], controller: "services" do
          put :update_url_mapping, on: :member, controller: "services"
          patch :toggle, on: :member, controller: "services"
        end
      end

      # Admin endpoints (restricted to admin permissions)
      namespace :admin do
        # Background job tracking
        resources :jobs, only: [ :index, :show ]

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
          get :status, to: "maintenance#status"
          get :health, to: "maintenance#health"
          get :metrics, to: "maintenance#metrics"

          # Backup management
          get :backups, to: "maintenance#backups"
          post :backups, to: "maintenance#create_backup"
          delete "backups/:id", to: "maintenance#delete_backup"
          post "backups/:id/restore", to: "maintenance#restore_backup"

          # Cleanup operations
          get "cleanup/stats", to: "maintenance#cleanup_stats"
          post "cleanup/run", to: "maintenance#run_cleanup"

          # Scheduled maintenance
          get :schedules, to: "maintenance#schedules"
          post :schedules, to: "maintenance#create_schedule"
          delete "schedules/:id", to: "maintenance#delete_schedule"

          # Maintenance mode
          get :mode, to: "maintenance#show_mode"
          post :mode, to: "maintenance#update_mode"

          # System health
          get "health/detailed", to: "maintenance#detailed_health"
          get "health/services", to: "maintenance#service_health"

          # Database operations
          get "database/stats", to: "maintenance#database_stats"
          post "database/analyze", to: "maintenance#analyze_database"
          post "operations/optimize", to: "maintenance#optimize_database"

          # Scheduled tasks
          get :tasks, to: "maintenance#list_tasks"
          post :tasks, to: "maintenance#create_task"
          patch "tasks/:id", to: "maintenance#update_task"
          delete "tasks/:id", to: "maintenance#delete_task"
          post "tasks/:id/execute", to: "maintenance#execute_task"
        end

        # Rate Limiting management
        namespace :rate_limiting do
          get :statistics, to: "rate_limiting#statistics"
          get :violations, to: "rate_limiting#violations"
          get :status, to: "rate_limiting#status"
          get :tiers, to: "rate_limiting#tiers"
          get :accounts, to: "rate_limiting#accounts_usage"
          get "limits/:identifier", to: "rate_limiting#user_limits"
          delete "limits/:identifier", to: "rate_limiting#clear_user_limits"
          post :disable, to: "rate_limiting#disable_temporarily"
          post :enable, to: "rate_limiting#enable"

          # Account tier management
          scope "accounts/:account_id" do
            get :statistics, to: "rate_limiting#account_statistics", as: :account_statistics
            post :override_tier, to: "rate_limiting#override_tier"
            delete :override_tier, to: "rate_limiting#clear_tier_override"
          end
        end

        # Database health monitoring (for worker service)
        namespace :database do
          get :pool_stats
          get :ping
          get :health
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
            delete "trusted_hosts/:pattern", action: :remove_trusted_host
            put "trusted_hosts/reorder", action: :reorder_trusted_hosts
            post :wildcard_patterns, action: :add_wildcard_pattern
            delete "wildcard_patterns/:pattern", action: :remove_wildcard_pattern
            put "wildcard_patterns/reorder", action: :reorder_wildcard_patterns
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
      resources :gateway_connection_jobs, only: [ :show, :update ]

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

      # Analytics tiers (controller is Api::V1::AnalyticsTiersController, not under analytics namespace)
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

      # Usage tracking endpoints
      resources :usage, only: [] do
        collection do
          get :dashboard
          get :meters
          get :history
          get :billing_summary
          get :quotas
          get :export
          post :quotas, to: "usage#set_quota"
          post "quotas/reset", to: "usage#reset_quotas"
        end
      end
      get "usage/meters/:slug", to: "usage#meter"
      resources :usage_events, only: [ :create ], path: "usage_events", controller: "usage" do
        collection do
          post :batch, to: "usage#track_events_batch"
        end
      end
      post "usage_events", to: "usage#track_event"

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
        namespace :stripe_sync, path: "stripe" do
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

        # Generic webhook event processing (for worker service)
        resources :events, only: [ :show, :update ] do
          member do
            patch :processing
            patch :processed
            patch :failed
          end
        end

        # Generic webhook processing endpoints (for worker service compatibility)
        post :payment_succeeded
        post :payment_failed
        post :subscription_updated
        post :subscription_cancelled
        post :subscription_activated
        post :payment_method_attached
        post :payment_intent_succeeded
        post :payment_intent_failed
      end

      # Webhook events resource (top-level for worker compatibility)
      resources :webhook_events, only: [ :show, :update ] do
        member do
          patch :processing
          patch :processed
          patch :failed
        end
      end

      # Jobs endpoint for worker service communication
      resources :jobs, only: [ :create ]

      # Notifications endpoint for worker service
      resources :notifications, only: [ :create ]

      # Enhanced reports endpoints for worker integration
      resources :reports, only: [ :show, :index, :create ] do
        collection do
          get :templates
          get :scheduled
          post :generate
          post :schedule
          get :requests, to: "reports#requests"
          post :requests, to: "reports#create_request"
        end

        member do
          delete :scheduled, to: "reports#destroy_scheduled"
        end
      end

      # Report requests nested endpoints
      get "reports/requests/:id", to: "reports#request_details"
      patch "reports/requests/:id", to: "reports#update_request"
      delete "reports/requests/:id", to: "reports#cancel_request"
      get "reports/requests/:id/download", to: "reports#download_request"
      delete "reports/scheduled/:id", to: "reports#destroy_scheduled"

      # Pages management
      resources :pages, only: [ :index, :show ], param: :slug

      # Impersonation endpoints (admin only)
      resources :impersonations, only: [ :index, :create, :destroy ] do
        collection do
          delete "/", to: "impersonations#destroy"
          get :history
          get :users, to: "impersonations#impersonatable_users"
          post :validate, to: "impersonations#validate_token"
          post :cleanup_expired, to: "impersonations#cleanup_expired"
        end
      end

      # Marketplace endpoints (templates, integrations)
      namespace :marketplace do
        # Browse and discover
        get "/", to: "items#index"
        get "featured", to: "items#featured"
        get "categories", to: "items#categories"

        # Subscriptions
        resources :subscriptions, only: [ :index, :show, :create, :update, :destroy ] do
          member do
            post :pause
            post :resume
            patch :configure
            post :upgrade_tier
            get :usage
          end
        end

        # Reviews
        resources :reviews, only: [ :index, :show, :create, :update, :destroy ] do
          member do
            post :helpful
            post :approve
            post :reject
            post :flag
          end
        end

        # Feature template management (must come before :type/:id catch-all)
        scope :templates do
          # Create templates from existing features
          post "from_workflow/:id", to: "templates#create_from_workflow"
          post "from_pipeline/:id", to: "templates#create_from_pipeline"
          post "from_integration/:id", to: "templates#create_from_integration"
          post "from_prompt/:id", to: "templates#create_from_prompt"

          # User's published templates
          get "my_published", to: "templates#my_published"

          # Admin: Pending review
          get "pending_review", to: "templates#pending_review"

          # Template actions
          post ":type/:id/submit", to: "templates#submit"
          post ":type/:id/withdraw", to: "templates#withdraw"
          post ":type/:id/approve", to: "templates#approve"
          post ":type/:id/reject", to: "templates#reject"
          post ":type/:id/create_instance", to: "templates#create_instance"
        end

        # Item details and actions (catch-all routes must come after specific routes)
        get ":type/:id", to: "items#show"
        post ":type/:id/subscribe", to: "items#subscribe"
        delete ":type/:id/unsubscribe", to: "items#unsubscribe"
      end

      # System Management endpoints (admin only)
      resources :audit_logs, only: [ :index, :show, :create ] do
        collection do
          get :stats
          get :security_summary
          get :compliance_summary
          get :activity_timeline
          get :risk_analysis
          post :export
          delete :cleanup
        end
      end

      resources :webhooks, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          post :test
          post :toggle_status
          post :health_test
        end
        collection do
          get :available_events, to: "webhooks#available_events"
          get :deliveries, to: "webhooks#delivery_history"
          get :failed_deliveries, to: "webhooks#failed_deliveries"
          get :stats
          post :retry_failed
          get :health, to: "webhooks#health_check"
          get "health/stats", to: "webhooks#health_stats"
        end
        resources :deliveries, only: [ :index, :show ], controller: "webhooks" do
          member do
            post :retry, to: "webhooks#retry_delivery"
          end
        end
      end

      # Version and health endpoints
      resource :version, only: [ :show ], controller: :version do
        get :full, on: :collection
        get :health, on: :collection
      end

      # Settings endpoints
      resource :settings, only: [ :show, :update ], controller: :settings do
        get :public, on: :collection
      end

      resources :api_keys, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          post :regenerate
          post :toggle_status
        end
        collection do
          get :usage, to: "api_keys#usage_stats"
          get :scopes, to: "api_keys#available_scopes"
          post :validate, to: "api_keys#validate_key"
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
      get "mcp/oauth/callback", to: "mcp_oauth#callback", as: :mcp_oauth_callback

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
          scope :oauth, as: :oauth do
            post "/", to: "mcp_oauth#authorize", as: :authorize
            get :status, to: "mcp_oauth#status"
            delete :disconnect, to: "mcp_oauth#disconnect"
            post :refresh, to: "mcp_oauth#refresh"
          end
        end

        resources :mcp_tools, only: [ :index, :show ] do
          member do
            post :execute
            get :stats
          end

          resources :mcp_tool_executions, path: "executions", only: [ :index, :show ] do
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
            patch :bulk, to: "articles#bulk_update"
            delete :bulk, to: "articles#bulk_delete"
          end
          member do
            post :publish
            post :unpublish
          end
          resources :comments, only: [ :index, :create ]
        end
        resources :tags, only: [ :index ] do
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
        resources :attachments, only: [ :create, :destroy ]
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
          get :config, action: :show_config
          put :config, action: :update_config
          post "config/reset", action: :reset_config
        end

        # Nested activities routes
        resources :activities, only: [ :index, :show ] do
          collection do
            get :summary
            delete :cleanup
          end
        end
      end

      # ===================================================================
      # GIT PROVIDER MANAGEMENT SYSTEM
      # ===================================================================
      # Multi-provider Git integration with CI/CD support
      # Supports GitHub, GitLab, and Gitea (with act runner)
      # ===================================================================

      namespace :git do
        # Providers with nested credentials
        resources :providers, only: [ :index, :show, :create, :update, :destroy ] do
          member do
            # OAuth flow
            post "oauth/authorize", action: :oauth_authorize
            post "oauth/callback", action: :oauth_callback

            # Credentials management
            get :credentials
            post :credentials, action: :create_credential
          end

          # Collection routes
          collection do
            post :sync, action: :sync_all
            get :available
          end
        end

        # Credential actions with credential_id param
        scope "providers/:id/credentials/:credential_id" do
          patch "/", to: "providers#update_credential"
          delete "/", to: "providers#destroy_credential"
          post :test, to: "providers#test_credential"
          post :make_default, to: "providers#make_default"
          get :available_repositories, to: "providers#available_repositories"
          post :import_repositories, to: "providers#import_repositories"
          post :sync_repositories, to: "providers#sync_repositories"  # deprecated, use import_repositories
        end

        # Repositories
        resources :repositories, only: [ :index, :show, :destroy ] do
          collection do
            post :sync
          end

          member do
            post :configure_webhook
            patch :update_webhook_config
            delete :remove_webhook
            get :branches
            get :commits
            get :pull_requests
            get :issues
            get :pipelines
            get :tags

            # Commit detail and diff
            get "commits/:sha", action: :commit, as: :commit_detail
            get "commits/:sha/diff", action: :commit_diff, as: :commit_diff

            # Compare commits
            get "compare/:base...:head", action: :compare, as: :compare_commits

            # File content and tree browsing
            get "contents/*path", action: :file_content, as: :file_content
            get "tree(/:sha)", action: :tree, as: :tree
          end
        end

        # Pipelines (can be accessed directly or via repository)
        resources :pipelines, only: [ :index, :show ] do
          collection do
            get :stats
          end

          member do
            post :cancel
            post :retry
            get :jobs
          end
        end

        # Pipeline trigger (requires repository context)
        post "repositories/:repository_id/pipelines/trigger", to: "pipelines#trigger"

        # Job logs
        get "pipelines/:pipeline_id/jobs/:id/logs", to: "pipelines#job_logs"

        # Webhook events (read-only history)
        resources :webhook_events, only: [ :index, :show ] do
          collection do
            get :stats
          end

          member do
            post :retry
            post :redeliver
          end
        end

        # Account-level Git Webhooks (organization-wide webhook configs)
        resources :account_webhooks, controller: "account_webhooks" do
          collection do
            get :available_events
          end

          member do
            post :test
            post :toggle_status
            post :regenerate_secret
          end
        end

        # CI/CD Runners (self-hosted runners management)
        resources :runners, only: [ :index, :show, :destroy ] do
          collection do
            post :sync
          end

          member do
            post :registration_token
            post :removal_token
            put :labels, action: :update_labels
          end
        end

        # Pipeline Schedules (scheduled/cron pipelines)
        resources :pipeline_schedules, only: [ :show, :update, :destroy ] do
          member do
            post :trigger
            post :pause
            post :resume
          end
        end

        # Repository-scoped schedule creation
        scope "repositories/:repository_id" do
          resources :schedules, controller: "pipeline_schedules", only: [ :index, :create ]
        end

        # Pipeline Approvals (approval gates for deployments)
        resources :pipeline_approvals, only: [ :index, :show ] do
          collection do
            get :pending
          end

          member do
            post :approve
            post :reject
            post :cancel
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
        # DISCOVERY - Agent auto-discovery and scanning
        # ===================================================================
        scope :discovery, controller: "discovery" do
          get "/", action: :index
          get "/:id", action: :show
          post "/scan", action: :scan
          post "/recommend", action: :recommend
        end

        # ===================================================================
        # MEMORY POOLS - Scoped memory management
        # ===================================================================
        resources :memory_pools do
          member do
            get "data/*key", action: :read_data
            post :write_data
            post :query
          end
        end

        # ===================================================================
        # 1. WORKFLOWS CONTROLLER - Consolidated workflow management
        # ===================================================================

        # Lookup endpoint for worker service (finds workflow by run_id)
        get "workflows/runs/lookup/:run_id", to: "workflows#runs_lookup"

        # Collection route for listing all workflow runs across all workflows
        # Used by worker service for cleanup operations
        get "workflow_runs", to: "workflows#runs_index"
        # Direct update route for workflow runs (used by worker cleanup jobs)
        patch "workflow_runs/:run_id", to: "workflows#run_update_direct"

        resources :workflows do
          member do
            post :execute
            post :duplicate
            get :validate
            get :export
            post :convert_to_template
            post :convert_to_workflow
            post :create_from_template
          end

          collection do
            post :import
            get :statistics
            get :templates
          end

          # Nested runs (replaces workflow_runs, workflow_executions, workflow_node_executions)
          # Explicitly map REST actions to prefixed controller methods
          get "runs", to: "workflows#runs_index"
          get "runs/:run_id", to: "workflows#run_show", as: :workflow_run
          patch "runs/:run_id", to: "workflows#run_update"
          put "runs/:run_id", to: "workflows#run_update"
          delete "runs/:run_id", to: "workflows#run_destroy"
          delete "runs", to: "workflows#runs_destroy_all", as: :destroy_all_workflow_runs

          # Run-specific member actions
          post "runs/:run_id/cancel", to: "workflows#run_cancel", as: :cancel_workflow_run
          post "runs/:run_id/retry", to: "workflows#run_retry", as: :retry_workflow_run
          post "runs/:run_id/pause", to: "workflows#run_pause", as: :pause_workflow_run
          post "runs/:run_id/resume", to: "workflows#run_resume", as: :resume_workflow_run
          get "runs/:run_id/logs", to: "workflows#run_logs", as: :workflow_run_logs
          get "runs/:run_id/node_executions", to: "workflows#run_node_executions", as: :workflow_run_node_executions
          get "runs/:run_id/metrics", to: "workflows#run_metrics", as: :workflow_run_metrics
          get "runs/:run_id/download", to: "workflows#run_download", as: :download_workflow_run
          post "runs/:run_id/process", to: "workflows#run_process", as: :process_workflow_run
          post "runs/:run_id/broadcast", to: "workflows#run_broadcast", as: :broadcast_workflow_run
          post "runs/:run_id/check_timeout", to: "workflows#run_check_timeout", as: :check_timeout_workflow_run

          # Nested schedules
          resources :schedules, controller: "workflows" do
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
          resources :triggers, controller: "workflows" do
            member do
              post :activate
              post :deactivate
              post :test
            end

            collection do
              post :webhook_endpoint, path: "webhook"
              post :event_endpoint, path: "event"
            end

            # Git workflow triggers - maps git events to workflow triggers
            resources :git_triggers, controller: "workflow_git_triggers" do
              member do
                post :test
              end
            end
          end

          # All git triggers for a workflow (across all triggers)
          get "git_triggers", to: "workflow_git_triggers#workflow_index", as: :workflow_git_triggers

          # Nested versions
          resources :versions, controller: "workflows" do
            member do
              post :restore
              get :compare
            end
          end

          # Nested validations
          resources :validations, controller: "workflow_validations", only: [ :index, :show, :create ] do
            collection do
              get :latest
              post :auto_fix
              post "auto_fix/:issue_code", action: :auto_fix_single
              get :preview_fixes
            end
          end

          # Workflow-specific actions
          member do
            post :dry_run, action: :workflows_dry_run
            get "dry_run/validate", action: :workflows_dry_run_validate
          end
        end

        # ===================================================================
        # Git Workflow Triggers - Top-level routes for managing git triggers
        # Used for CRUD operations when trigger_id is provided as a param
        # ===================================================================
        resources :workflow_git_triggers, only: [ :index, :show, :create, :update, :destroy ] do
          member do
            post :test
          end

          collection do
            get :workflow_index
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
            get :connections
            get :skills
            post :assign_skill
            delete "skills/:skill_id", action: :remove_skill
          end

          collection do
            get :my_agents
            get :public_agents
            get :agent_types
            get :statistics
          end

          # Nested executions (replaces ai_agent_executions)
          # Explicitly map REST actions to prefixed controller methods
          get "executions", to: "agents#executions_index"
          get "executions/:execution_id", to: "agents#execution_show", as: :agent_execution
          patch "executions/:execution_id", to: "agents#execution_update"
          put "executions/:execution_id", to: "agents#execution_update"
          delete "executions/:execution_id", to: "agents#execution_destroy"
          post "executions/:execution_id/cancel", to: "agents#execution_cancel", as: :cancel_agent_execution
          post "executions/:execution_id/retry", to: "agents#execution_retry", as: :retry_agent_execution
          get "executions/:execution_id/logs", to: "agents#execution_logs", as: :agent_execution_logs

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
            end

            # Nested messages
            resources :messages, controller: "agents" do
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
            post :sync_all
          end

          # Nested credentials (replaces ai_provider_credentials)
          resources :credentials, controller: "providers" do
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
        resources :conversations, only: [ :index, :show, :update, :destroy ] do
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
          get "health/detailed", action: :health_detailed
          get "health/connectivity", action: :health_connectivity
          get :alerts
          post "alerts/check", action: :alerts_check

          # Circuit breakers (replaces circuit_breakers_controller)
          get :circuit_breakers, action: :circuit_breakers_index
          get "circuit_breakers/:service_name", action: :circuit_breaker_show
          post "circuit_breakers/:service_name/reset", action: :circuit_breaker_reset
          post "circuit_breakers/:service_name/open", action: :circuit_breaker_open
          post "circuit_breakers/:service_name/close", action: :circuit_breaker_close
          post "circuit_breakers/reset_all", action: :circuit_breakers_reset_all
          get "circuit_breakers/category/:category", action: :circuit_breakers_category
          post "circuit_breakers/category/:category/reset", action: :circuit_breakers_category_reset
          get "circuit_breakers/monitor", action: :circuit_breakers_monitor

          # Real-time monitoring
          post :broadcast, action: :broadcast_metrics
          post :start, action: :start_monitoring
          post :stop, action: :stop_monitoring
        end

        # ===================================================================
        # 5.5 EXECUTION TRACES - Debugging & tracing
        # ===================================================================
        resources :execution_traces, only: [ :index, :show ] do
          member do
            get :spans
            get :timeline
          end

          collection do
            get :summary
          end
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
          get "workflows/:workflow_id", action: :workflow_analytics
          get "agents/:agent_id", action: :agent_analytics

          # Reports system (custom actions)
          get :reports, action: :reports_index
          post :reports, action: :report_create
          get "reports/templates", action: :report_templates
          get "reports/:id", action: :report_show
          delete "reports/:id", action: :report_cancel
          get "reports/:id/download", action: :report_download

          # Reports (replaces reports_controller) - DEPRECATED nested resource
          resources :reports, controller: "analytics" do
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
        resource :validation_statistics, only: [ :show ] do
          get :common_issues
          get :health_distribution
        end

        # ===================================================================
        # 8. MARKETPLACE CONTROLLER - Consolidated marketplace & templates
        # ===================================================================
        # Marketplace Templates - No namespace to match controller location at Api::V1::Ai::MarketplaceController
        # Note: Using standard RESTful action names (index, show, create, update, destroy)
        get "marketplace/templates", controller: "marketplace", action: :index, as: :templates_index
        get "marketplace/templates/:id", controller: "marketplace", action: :show, as: :template_show
        post "marketplace/templates", controller: "marketplace", action: :create, as: :templates_create
        patch "marketplace/templates/:id", controller: "marketplace", action: :update, as: :template_update
        put "marketplace/templates/:id", controller: "marketplace", action: :update
        delete "marketplace/templates/:id", controller: "marketplace", action: :destroy, as: :template_destroy

        # Template member actions
        post "marketplace/templates/:id/install", controller: "marketplace", action: :install, as: :install_template
        post "marketplace/templates/:id/publish", controller: "marketplace", action: :publish, as: :publish_template
        get "marketplace/templates/:id/validate", controller: "marketplace", action: :validate_template, as: :validate_template
        post "marketplace/templates/:id/rate", controller: "marketplace", action: :rate, as: :rate_template
        get "marketplace/templates/:id/analytics", controller: "marketplace", action: :template_analytics, as: :template_analytics

        # Template collection actions
        post "marketplace/templates/from_workflow", controller: "marketplace", action: :create_from_workflow, as: :create_from_workflow
        post "marketplace/templates/publish_workflow", controller: "marketplace", action: :publish_workflow, as: :publish_workflow_template
        get "marketplace/templates/featured", controller: "marketplace", action: :featured, as: :featured_templates
        get "marketplace/templates/popular", controller: "marketplace", action: :popular, as: :popular_templates
        get "marketplace/templates/categories", controller: "marketplace", action: :categories, as: :template_categories
        get "marketplace/templates/tags", controller: "marketplace", action: :tags, as: :template_tags
        get "marketplace/templates/statistics", controller: "marketplace", action: :statistics, as: :template_statistics

        # Marketplace general actions
        get "marketplace/discover", controller: "marketplace", action: :discover
        post "marketplace/search", controller: "marketplace", action: :search
        get "marketplace/recommendations", controller: "marketplace", action: :recommendations
        post "marketplace/compare", controller: "marketplace", action: :compare
        # Short routes for featured/popular/categories/tags/statistics (without templates/ prefix)
        get "marketplace/featured", controller: "marketplace", action: :featured
        get "marketplace/popular", controller: "marketplace", action: :popular
        get "marketplace/categories", controller: "marketplace", action: :categories
        get "marketplace/tags", controller: "marketplace", action: :tags
        get "marketplace/statistics", controller: "marketplace", action: :statistics

        # Installations - Note: Controller uses custom action names (installations_index, installation_show, etc.)
        get "marketplace/installations", controller: "marketplace", action: :installations_index, as: :installations_index
        get "marketplace/installations/:id", controller: "marketplace", action: :installation_show, as: :installation_show
        delete "marketplace/installations/:id", controller: "marketplace", action: :installation_destroy, as: :installation_destroy

        # Updates
        get "marketplace/updates", controller: "marketplace", action: :check_updates
        post "marketplace/updates/apply", controller: "marketplace", action: :apply_updates

        # ===================================================================
        # 8b. PUBLISHER CONTROLLER - Publisher dashboard and earnings
        # ===================================================================
        # Publisher-specific routes for marketplace publishers
        get "publisher/me", controller: "publisher", action: :me, as: :publisher_me
        resources :publisher, only: [ :index, :show, :create ], controller: "publisher" do
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

        # ===================================================================
        # 9. PERSISTENT CONTEXT CONTROLLER - Cross-session AI memory
        # ===================================================================
        # Knowledge bases, agent memory, and shared context management
        # ===================================================================

        resources :contexts do
          member do
            post :search
            post :archive
            post :unarchive
            get :export
            post :clone
            get :stats
          end

          collection do
            post :import
          end

          # Nested entries
          resources :entries, controller: "context_entries" do
            member do
              post :archive
              post :unarchive
              post :boost
              get :history
            end

            collection do
              post :bulk, action: :bulk_create
            end
          end
        end

        # Agent Memory - convenient shorthand for agent-specific memory
        scope "agents/:agent_id" do
          get "memory", to: "agent_memory#index"
          post "memory", to: "agent_memory#create"
          get "memory/stats", to: "agent_memory#stats"
          post "memory/search", to: "agent_memory#search"
          post "memory/clear", to: "agent_memory#clear"
          post "memory/sync", to: "agent_memory#sync"
          get "memory/:key", to: "agent_memory#show"
          patch "memory/:key", to: "agent_memory#update"
          delete "memory/:key", to: "agent_memory#destroy"
        end

        # ===================================================================
        # 10. RAG CONTROLLER - Knowledge-Augmented Agents
        # ===================================================================
        # Revenue: Storage fees + query pricing + embedding fees
        # - Storage: $0.10-0.25/GB/month
        # - Embeddings: $0.0001-0.0004/1K tokens
        # - Queries: $0.001-0.01/query based on complexity
        # ===================================================================
        scope :rag, controller: "rag" do
          # Knowledge bases
          get "knowledge_bases", action: :index
          get "knowledge_bases/:id", action: :show_knowledge_base
          post "knowledge_bases", action: :create_knowledge_base
          patch "knowledge_bases/:id", action: :update_knowledge_base
          delete "knowledge_bases/:id", action: :delete_knowledge_base

          # Documents
          get "knowledge_bases/:knowledge_base_id/documents", action: :list_documents
          post "knowledge_bases/:knowledge_base_id/documents", action: :create_document
          get "knowledge_bases/:knowledge_base_id/documents/:id", action: :show_document
          delete "knowledge_bases/:knowledge_base_id/documents/:id", action: :delete_document
          post "knowledge_bases/:knowledge_base_id/documents/:id/process", action: :process_document

          # Embeddings
          post "knowledge_bases/:knowledge_base_id/embed", action: :embed_chunks

          # Queries
          post "knowledge_bases/:knowledge_base_id/query", action: :query
          get "knowledge_bases/:knowledge_base_id/query_history", action: :query_history

          # Data connectors
          get "knowledge_bases/:knowledge_base_id/connectors", action: :list_connectors
          post "knowledge_bases/:knowledge_base_id/connectors", action: :create_connector
          post "knowledge_bases/:knowledge_base_id/connectors/:id/sync", action: :sync_connector

          # Analytics
          get "knowledge_bases/:knowledge_base_id/analytics", action: :analytics
        end

        # ===================================================================
        # 11. TEAMS CONTROLLER - Multi-Agent Team Orchestration
        # ===================================================================
        # Revenue: Tiered subscriptions + agent seat pricing
        # - Starter: 3 agents, 1 team ($49/mo)
        # - Pro: 10 agents, 5 teams, advanced patterns ($199/mo)
        # - Enterprise: Unlimited + custom topologies ($999/mo)
        # ===================================================================
        scope :teams, controller: "teams" do
          # Templates (before /:id to avoid matching "templates" as an id)
          get "/templates", action: :list_templates
          get "/templates/:id", action: :show_template
          post "/templates", action: :create_template
          post "/templates/:id/publish", action: :publish_template

          # Role Profiles (before /:id to avoid matching as team id)
          get "/role_profiles", action: :list_role_profiles
          get "/role_profiles/:id", action: :show_role_profile

          # Trajectories (before /:id to avoid matching as team id)
          get "/trajectories", action: :list_trajectories
          get "/trajectories/search", action: :search_trajectories
          get "/trajectories/:id", action: :show_trajectory

          # Reviews (global)
          get "/reviews/:id", action: :show_review
          post "/reviews/:id/process", action: :process_review

          # Review Comments
          get "/reviews/:review_id/comments", action: :list_review_comments
          post "/reviews/:review_id/comments", action: :create_review_comment
          patch "/reviews/:review_id/comments/:comment_id", action: :update_review_comment

          # Executions (before /:id to avoid matching "executions" as an id)
          get "/executions/:id", action: :show_execution
          post "/executions/:id/pause", action: :pause_execution
          post "/executions/:id/resume", action: :resume_execution
          post "/executions/:id/cancel", action: :cancel_execution
          post "/executions/:id/complete", action: :complete_execution
          get "/executions/:id/details", action: :execution_details

          # Tasks
          get "/executions/:execution_id/tasks", action: :list_tasks
          post "/executions/:execution_id/tasks", action: :create_task
          get "/executions/:execution_id/tasks/:id", action: :show_task
          post "/executions/:execution_id/tasks/:id/assign", action: :assign_task
          post "/executions/:execution_id/tasks/:id/start", action: :start_task
          post "/executions/:execution_id/tasks/:id/complete", action: :complete_task
          post "/executions/:execution_id/tasks/:id/fail", action: :fail_task
          post "/executions/:execution_id/tasks/:id/delegate", action: :delegate_task

          # Task Reviews
          get "/executions/:execution_id/tasks/:task_id/reviews", action: :list_task_reviews

          # Messages
          get "/executions/:execution_id/messages", action: :list_messages
          post "/executions/:execution_id/messages", action: :send_message
          post "/executions/:execution_id/messages/:id/reply", action: :reply_to_message

          # Teams
          get "/", action: :index
          get "/:id", action: :show
          post "/", action: :create
          patch "/:id", action: :update
          delete "/:id", action: :destroy

          # Roles
          get "/:team_id/roles", action: :list_roles
          post "/:team_id/roles", action: :create_role
          patch "/:team_id/roles/:id", action: :update_role
          delete "/:team_id/roles/:id", action: :delete_role
          post "/:team_id/roles/:id/assign_agent", action: :assign_agent_to_role
          post "/:team_id/roles/:id/apply_profile", action: :apply_role_profile

          # Channels
          get "/:team_id/channels", action: :list_channels
          post "/:team_id/channels", action: :create_channel

          # Executions (team-specific)
          get "/:team_id/executions", action: :list_executions
          post "/:team_id/executions", action: :start_execution

          # Analytics & Health
          get "/:team_id/analytics", action: :analytics
          get "/:team_id/composition_health", action: :composition_health

          # Review Configuration
          put "/:team_id/review_config", action: :update_review_config
        end

        # ===================================================================
        # 12. AGENT TEAMS CONTROLLER - CrewAI-style team orchestration (Legacy)
        # ===================================================================
        resources :agent_teams do
          member do
            post :execute
            post :execute_complete      # Internal - called by worker
            post :execute_failed        # Internal - called by worker
            post :auto_assign_lead
            post :optimize
            get :autonomy_config
            put :autonomy_config, action: :update_autonomy_config
            post :bind_infrastructure

            # Team members management
            post "members", to: "agent_teams#add_member"
            delete "members/:member_id", to: "agent_teams#remove_member"
          end

          # Team execution history and controls
          resources :executions, only: [:index, :show], controller: "agent_team_executions" do
            member do
              post :cancel
              post :pause
              post :resume
              post :retry, action: :retry_execution
            end
          end

          collection do
            get :statistics
            get :templates
          end
        end

        # ===================================================================
        # 11. PROMPT TEMPLATES CONTROLLER - Reusable AI prompts
        # ===================================================================
        resources :prompt_templates do
          member do
            post :preview
            post :duplicate
          end
        end

        # ===================================================================
        # A2A PROTOCOL - Agent-to-Agent Communication
        # ===================================================================
        # Agent Cards for A2A discovery
        resources :agent_cards do
          member do
            get :a2a  # Get A2A-compliant JSON
            post :publish
            post :deprecate
            post :refresh_metrics
          end

          collection do
            get :discover
            post :find_for_task
          end
        end

        # A2A Tasks
        scope :a2a, as: :a2a do
          resources :tasks, controller: "a2a_tasks", param: :task_id do
            member do
              get :details
              post :cancel
              post :input, action: :provide_input
              get :events
              get "events/poll", action: :events_poll
              get :artifacts
              get "artifacts/:artifact_id", action: :artifact
              post :push_notifications, action: :configure_push_notifications
            end

            collection do
              # tasks/send endpoint
            end
          end
        end

        # Agent Memory Enhancement (adds to existing memory routes)
        scope "agents/:agent_id" do
          post "memory/inject", to: "agent_memory#inject"
        end

        # ===================================================================
        # RALPH LOOPS - AI-Driven Iterative Development
        # ===================================================================
        # Implements the Ralph pattern for AI-assisted development:
        # Parse PRD -> Execute Tasks -> Learn -> Iterate until completion
        # Supports multiple AI tools (AMP, Claude Code)
        # ===================================================================
        resources :ralph_loops do
          member do
            post :start
            post :pause
            post :resume
            post :cancel
            post :reset
            post :run_iteration
            post :run_all
            post :stop_run_all
            post :parse_prd
            get :learnings
            get :progress
            # Scheduling actions
            post :pause_schedule
            post :resume_schedule
            post :regenerate_webhook_token
            # Nested tasks (inside member to use :id param)
            get :tasks
            get "tasks/:task_id", action: :task, as: :task
            patch "tasks/:task_id", action: :update_task, as: :update_task
            # Nested iterations (inside member to use :id param)
            get :iterations
            get "iterations/:iteration_id", action: :iteration, as: :iteration
          end

          collection do
            get :statistics
          end
        end

        # Event-triggered Ralph Loop webhook endpoint
        # POST /api/v1/ai/ralph_loops/webhook/:token - Trigger loop execution
        # GET /api/v1/ai/ralph_loops/webhook/:token/status - Get loop status
        scope "ralph_loops/webhook/:token", controller: "ralph_loop_webhooks" do
          post "/", action: :trigger
          get "/status", action: :status
        end

        # ===================================================================
        # API REFERENCE - Filterable API specification for agents
        # ===================================================================
        scope :api_reference, controller: "api_reference" do
          get "/", action: :index
          get "/search", action: :search
          get "/:section", action: :show
        end

        # ===================================================================
        # EXECUTION RESOURCES - Unified resource browsing
        # ===================================================================
        scope :execution_resources, controller: "execution_resources" do
          get "/", action: :index
          get "/counts", action: :counts
          get "/:resource_type/:id", action: :show
        end

        # ===================================================================
        # WORKTREE SESSIONS - Parallel execution with git worktrees
        # ===================================================================
        resources :worktree_sessions, only: [:index, :show, :create] do
          member do
            post :cancel
            get :status
            get :merge_operations
            post :retry_merge
            get :conflicts
            get :file_locks
            post :acquire_locks
            post :release_locks
          end
        end

        # ===================================================================
        # COMMUNITY AGENTS - Public agent registry and discovery
        # ===================================================================
        # Enables publishing, discovering, and rating AI agents across
        # organizations. Federation support for cross-org agent sharing.
        # ===================================================================
        scope :community, as: :community do
          resources :agents, controller: "community_agents" do
            member do
              post :publish
              post :unpublish
              post :rate
              post :report
            end

            collection do
              get :my_agents
              get :categories
              get :skills
              post :discover
            end
          end
        end

        # ===================================================================
        # FEDERATION - Cross-organization agent sharing
        # ===================================================================
        # Enables trusted organizations to share agents via mTLS and
        # JWT-based authentication. Federation partners can discover
        # and invoke each other's agents.
        # ===================================================================
        scope :federation, as: :federation do
          resources :partners, controller: "federation" do
            member do
              post :verify
              get :agents
              post :sync
            end
          end

          # External registration endpoints
          post :register, to: "federation#register_external"
          post :verify_key, to: "federation#verify_key"
          get :discover, to: "federation#discover"
        end

        # ===================================================================
        # 12. MODEL ROUTER CONTROLLER - Intelligent AI Request Routing
        # ===================================================================
        # Routes AI requests to optimal providers based on cost, latency, quality
        # Revenue: Usage-based + optimization savings share
        # ===================================================================
        scope :model_router, controller: "model_router" do
          # Routing rules management
          get "rules", action: :rules_index
          post "rules", action: :create_rule
          get "rules/:id", action: :show_rule
          patch "rules/:id", action: :update_rule
          delete "rules/:id", action: :destroy_rule
          post "rules/:id/toggle", action: :toggle_rule

          # Routing operations
          post "route", action: :route

          # Routing decisions history
          get "decisions", action: :decisions
          get "decisions/:id", action: :show_decision

          # Statistics and analytics
          get "statistics", action: :statistics
          get "cost_analysis", action: :cost_analysis
          get "provider_rankings", action: :provider_rankings
          get "recommendations", action: :recommendations

          # Cost optimization management
          get "optimizations", action: :optimizations_index
          post "optimizations/identify", action: :identify_optimizations
          post "optimizations/:id/apply", action: :apply_optimization
        end

        # ===================================================================
        # 13. AIOPS CONTROLLER - Real-Time AI Operations Dashboard
        # ===================================================================
        # Comprehensive observability for AI workflows: latency, costs, errors
        # Revenue: Monitoring tiers + alerting add-ons
        # ===================================================================
        scope :aiops, controller: "ai_ops" do
          # Dashboard and health
          get "dashboard", action: :dashboard
          get "health", action: :health
          get "overview", action: :overview

          # Provider metrics
          get "providers", action: :providers
          get "providers/:id/metrics", action: :provider_metrics
          get "providers/comparison", action: :provider_comparison

          # Workflow and agent metrics
          get "workflows", action: :workflows
          get "agents", action: :agents

          # Cost analysis
          get "cost_analysis", action: :cost_analysis

          # Alerts and circuit breakers
          get "alerts", action: :alerts
          get "circuit_breakers", action: :circuit_breakers

          # Real-time metrics
          get "real_time", action: :real_time
          post "record_metrics", action: :record_metrics
        end

        # ===================================================================
        # 14. ROI CONTROLLER - Workflow Revenue Analytics & ROI Tracking
        # ===================================================================
        # Tracks business value and ROI of AI workflows with cost attribution
        # Revenue: Premium analytics tiers
        # ===================================================================
        scope :roi, controller: "roi" do
          # Dashboard and summary
          get "dashboard", action: :dashboard
          get "summary", action: :summary

          # Trends and daily metrics
          get "trends", action: :trends
          get "daily_metrics", action: :daily_metrics

          # Breakdown analysis
          get "by_workflow", action: :by_workflow
          get "by_agent", action: :by_agent
          get "by_provider", action: :by_provider
          get "cost_breakdown", action: :cost_breakdown

          # Cost attributions
          get "attributions", action: :attributions

          # ROI metrics
          get "metrics", action: :metrics
          get "metrics/:id", action: :show_metric

          # Projections and recommendations
          get "projections", action: :projections
          get "recommendations", action: :recommendations

          # Period comparison
          get "compare", action: :compare

          # Metric calculation (admin/system)
          post "calculate", action: :calculate
          post "aggregate", action: :aggregate
        end

        # ===================================================================
        # 15. CREDITS CONTROLLER - Prepaid AI Credit System
        # ===================================================================
        # Revenue: Prepaid credits + reseller margins
        # - Credit packs: 1K ($99), 10K ($899), 100K ($7,999)
        # - Reseller margin: 15-30% based on volume
        # - Credit marketplace for B2B trading
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
        # 16. OUTCOME BILLING CONTROLLER - Success-Based AI Billing
        # ===================================================================
        # Revenue: Success fees + SLA premiums
        # - Per-successful-outcome pricing ($0.01-$5.00 based on complexity)
        # - SLA tiers: 99% ($X), 99.9% ($2X), 99.99% ($5X)
        # - Refund credits for SLA breaches
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
        # 17. AGENT MARKETPLACE CONTROLLER - Pre-Built Vertical AI Agents
        # ===================================================================
        # Revenue: Commission (15-30%) + listing fees
        # - Free tier: 3 community agents
        # - Pro: Unlimited community + 5 premium ($149/mo)
        # - Enterprise: Private marketplace + custom agents ($999+/mo)
        # - Publisher revenue share: 70-85% to creators
        # ===================================================================
        scope :agent_marketplace, controller: "agent_marketplace" do
          # Templates
          get "templates", action: :templates
          get "templates/featured", action: :featured
          get "templates/:id", action: :show_template
          get "categories", action: :categories

          # Installations
          get "installations", action: :installations
          post "templates/:template_id/install", action: :install
          delete "installations/:id", action: :uninstall

          # Reviews
          get "templates/:template_id/reviews", action: :reviews
          post "templates/:template_id/reviews", action: :create_review

          # Publisher
          get "publisher", action: :publisher
          post "publisher", action: :create_publisher
          get "publisher/analytics", action: :publisher_analytics
        end

        # ===================================================================
        # 18. GOVERNANCE CONTROLLER - AI Workflow Governance & Compliance
        # ===================================================================
        # Revenue: Enterprise licensing + compliance certifications
        # - Compliance add-on: $299-999/mo based on tier
        # - SOC 2 certification support: $5,000 one-time
        # - Dedicated compliance officer support: $2,000/mo
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
        # 19. DEVOPS CONTROLLER - AI Pipeline Templates for DevOps
        # ===================================================================
        # Revenue: Template marketplace + enterprise customization
        # - Community templates: free
        # - Premium templates: $29-99 one-time
        # - Custom template development: $2,000-10,000
        # - Enterprise template library: $199/mo
        # ===================================================================
        scope :devops, controller: "devops" do
          # Templates
          get "templates", action: :templates
          get "templates/:id", action: :show_template
          post "templates", action: :create_template
          patch "templates/:id", action: :update_template

          # Installations
          get "installations", action: :installations
          post "templates/:template_id/install", action: :install
          delete "installations/:id", action: :uninstall

          # Executions
          get "executions", action: :executions
          post "executions", action: :create_execution
          get "executions/:id", action: :show_execution

          # Deployment risks
          get "risks", action: :risks
          post "risks/assess", action: :assess_risk
          put "risks/:id/approve", action: :approve_risk
          put "risks/:id/reject", action: :reject_risk

          # Code reviews
          get "reviews", action: :reviews
          post "reviews", action: :create_review
          get "reviews/:id", action: :show_review

          # Analytics
          get "analytics", action: :analytics
        end

        # ===================================================================
        # 20. SANDBOXES CONTROLLER - Enterprise AI Agent Testing
        # ===================================================================
        # Revenue: Sandbox environments + testing infrastructure
        # - Basic sandbox: included
        # - Advanced testing: $99/mo (recording, playback)
        # - Performance profiling: $199/mo
        # - Enterprise (dedicated environments): $499/mo
        # ===================================================================
        resources :sandboxes, controller: "sandboxes" do
          member do
            put :activate
            put :deactivate
            get :analytics
          end

          # Scenarios
          get "scenarios", to: "sandboxes#scenarios"
          post "scenarios", to: "sandboxes#create_scenario"

          # Mocks
          get "mocks", to: "sandboxes#mocks"
          post "mocks", to: "sandboxes#create_mock"

          # Test runs
          get "runs", to: "sandboxes#runs"
          post "runs", to: "sandboxes#create_run"
          get "runs/:run_id", to: "sandboxes#show_run"
          post "runs/:run_id/execute", to: "sandboxes#execute_run"

          # Benchmarks
          get "benchmarks", to: "sandboxes#benchmarks"
          post "benchmarks", to: "sandboxes#create_benchmark"
          post "benchmarks/:benchmark_id/run", to: "sandboxes#run_benchmark"
        end

        # A/B Tests (account-level, not sandbox-specific)
        scope :ab_tests, controller: "sandboxes" do
          get "/", action: :ab_tests
          post "/", action: :create_ab_test
          put "/:id/start", action: :start_ab_test
          get "/:id/results", action: :ab_test_results
        end

        # ===================================================================
        # AI SKILLS - Domain-specific skill bundles
        # ===================================================================
        resources :skills do
          member do
            post :activate
            post :deactivate
            get :agents
          end

          collection do
            get :categories
          end
        end

        # ===================================================================
        # SELF-HEALING - Automated Remediation Dashboard
        # ===================================================================
        scope :self_healing, controller: "self_healing" do
          get "remediation_logs", action: :remediation_logs
          get "health_summary", action: :health_summary
          get "correlations", action: :correlations
        end

        # ===================================================================
        # AGENT CONTAINERS - Containerized agent lifecycle + chat bridge
        # ===================================================================
        resources :agent_containers, only: [:show, :destroy] do
          member do
            post :launch
            get :status
          end
          collection do
            post :callback
          end
        end

        # ===================================================================
        # LEARNING - AI Improvement Recommendations & Insights
        # ===================================================================
        scope :learning, controller: "learning" do
          get "recommendations", action: :recommendations
          post "recommendations/:id/apply", action: :apply_recommendation
          post "recommendations/:id/dismiss", action: :dismiss_recommendation
          get "agent_trends", action: :agent_trends
          get "cache_metrics", action: :cache_metrics
          get "compound_metrics", action: :compound_metrics
          get "learnings", action: :learnings
          post "reinforce/:id", action: :reinforce
          post "promote", action: :promote
          post "compound_maintenance", action: :compound_maintenance
        end
      end

      # ===================================================================
      # MCP HOSTING - Managed MCP Server Operations
      # ===================================================================
      # Revenue: Hosting fees + marketplace commission
      # - Free tier: 1 server, limited requests
      # - Pro: 5 servers, 10K requests/mo ($79/mo)
      # - Enterprise: Unlimited + private registry ($299/mo)
      # - Marketplace commission: 20% on paid tools
      # ===================================================================
      namespace :mcp do
        scope :hosting, controller: "hosting" do
          # Server management
          get "servers", action: :index
          get "servers/:id", action: :show
          post "servers", action: :create
          patch "servers/:id", action: :update
          delete "servers/:id", action: :destroy

          # Deployment operations
          post "servers/:id/deploy", action: :deploy
          post "servers/:id/rollback", action: :rollback
          get "servers/:id/deployments", action: :deployments

          # Lifecycle operations
          post "servers/:id/start", action: :start
          post "servers/:id/stop", action: :stop
          post "servers/:id/restart", action: :restart

          # Monitoring
          get "servers/:id/metrics", action: :metrics
          get "servers/:id/health", action: :health

          # Marketplace operations
          post "servers/:id/publish", action: :publish
          post "servers/:id/unpublish", action: :unpublish
          get "marketplace", action: :marketplace
          post "marketplace/:server_id/subscribe", action: :subscribe

          # Subscriptions
          get "subscriptions", action: :subscriptions
        end

        # Container orchestration routes moved to namespace :devops

        # ===================================================================
        # MCP RESOURCES & PROMPTS - Dynamic discovery from servers
        # ===================================================================
        # Resources and prompts are discovered dynamically from MCP servers
        # ===================================================================

        resources :mcp_servers, only: [] do
          resources :resources, controller: "resources", only: [ :index, :show ] do
            member do
              post :read
            end
          end

          resources :prompts, controller: "prompts", only: [ :index, :show ] do
            member do
              post :execute
            end
          end
        end
      end

      # ===================================================================
      # FILE MANAGEMENT SYSTEM - Universal file storage
      # ===================================================================
      # Multi-provider file storage system with workflow integration
      # ===================================================================

      # Files management endpoints
      resources :files, except: [ :new, :edit ] do
        member do
          get :download
          get :download_public, path: "public"  # Public endpoint for serving public files (no auth)
          post :restore
          post :share
          post :create_version, path: "versions"
          post :add_tags, path: "tags"
          delete :remove_tags, path: "tags"
        end

        collection do
          get :stats
        end
      end

      # Alias for upload
      post "files/upload", to: "files#upload"

      # Storage providers configuration endpoints
      resources :storage_providers, path: "storage", except: [ :new, :edit ] do
        member do
          post :test_connection, path: "test"
          get :health_check, path: "health"
          post :set_default
          post :initialize_storage, path: "initialize"
          get :list_files, path: "files"
        end

        collection do
          get :supported
          get :aggregate_stats, path: "stats"
        end
      end

      # ===================================================================
      # EXTERNAL INTEGRATION FRAMEWORK
      # ===================================================================
      # ===================================================================
      # DEVOPS MANAGEMENT SYSTEM
      # ===================================================================
      # AI-powered CI/CD pipelines, integrations, and infrastructure management
      # Combines pipeline management with third-party integrations
      # ===================================================================

      namespace :devops do
        # Container Orchestration
        resources :containers do
          member do
            post :cancel
            get :logs
            get :artifacts
          end

          collection do
            post :execute
            get :active
            get :stats
          end
        end

        resources :container_templates do
          member do
            post :publish
            post :unpublish
            get :executions
            get :stats
          end

          collection do
            get :categories
            get :featured
          end
        end

        resource :container_quotas, only: [ :show, :update ] do
          post :reset_usage
          get :usage_history
          get :overage
          patch :overage, action: :update_overage
        end

        # Git Providers (Gitea, GitHub, GitLab)
        resources :providers do
          member do
            post :test_connection
            post :sync_repositories
          end
        end

        # AI Configuration (Anthropic, Bedrock, Vertex)
        resources :ai_configs do
          member do
            post :set_default
          end
        end

        # Prompt Templates with Liquid templating
        resources :prompt_templates do
          member do
            post :preview
            post :duplicate
          end
        end

        # Pipeline Definitions
        resources :pipelines do
          member do
            post :trigger
            get :export_yaml
            post :duplicate
          end

          # Nested runs
          resources :runs, controller: "pipeline_runs", only: [ :index ]
        end

        # Pipeline Runs (top-level for direct access)
        resources :pipeline_runs, only: [ :index, :show ] do
          member do
            post :cancel
            post :retry
            get :logs
          end
        end

        # Scheduled Pipeline Runs
        resources :schedules do
          member do
            post :toggle
          end
        end

        # Repository Connections
        resources :repositories do
          member do
            post :sync
            post :attach_pipeline
            delete :detach_pipeline
          end
        end

        # Integration Templates (system-wide, admin-managed)
        resources :integration_templates do
          collection do
            get :search
            get :categories
            get :types
          end
        end

        # Integration Instances (per-account installations)
        resources :integration_instances do
          member do
            post :activate
            post :deactivate
            post :test
            post :execute
            get :health
            get :stats
          end
        end

        # Integration Credentials (per-account secrets)
        resources :integration_credentials do
          member do
            post :rotate
            post :verify
          end
        end

        # Integration Executions (history and management)
        resources :integration_executions, only: [ :index, :show ] do
          member do
            post :retry
            post :cancel
          end

          collection do
            get :stats
          end
        end

        # Docker Swarm Management
        namespace :swarm do
          resources :clusters do
            member do
              post :test_connection
              post :sync
              get :health
            end
            resources :nodes, only: [:index, :show] do
              member do
                post :promote
                post :demote
                post :drain
                post :activate
                delete :remove
              end
            end
            resources :services do
              collection do
                get :available
                post :import
              end
              member do
                post :scale
                post :rollback
                get :logs
                get :tasks
              end
            end
            resources :stacks do
              member do
                post :deploy
                post :remove_stack
              end
            end
            resources :deployments, only: [:index, :show]
            resources :secrets, only: [:index, :show, :create, :destroy]
            resources :configs, only: [:index, :show, :create, :destroy]
            resources :networks, only: [:index, :show, :create, :destroy]
            resources :volumes, only: [:index, :show, :create, :destroy]
            resources :events, only: [:index, :show] do
              member do
                post :acknowledge
              end
            end
          end
        end

        # Docker Host Management
        namespace :docker do
          resources :hosts do
            member do
              post :test_connection
              post :sync
              get :health
            end
            resources :containers do
              collection do
                get :available
                post :import
              end
              member do
                post :start
                post :stop
                post :restart
                get :logs
                get :stats
              end
            end
            resources :images, only: [:index, :show, :destroy] do
              collection do
                get :available
                post :import
                post :pull
                get :registries
              end
              member do
                post :tag
              end
            end
            resources :networks, only: [:index, :show, :create, :destroy]
            resources :volumes, only: [:index, :show, :create, :destroy]
            resources :activities, only: [:index, :show]
            resources :events, only: [:index, :show] do
              member do
                post :acknowledge
              end
            end
          end
        end
      end

      # ===================================================================
      # SOFTWARE SUPPLY CHAIN MANAGEMENT SYSTEM
      # ===================================================================
      # Comprehensive SBOM, vulnerability, attestation, container, license,
      # and vendor risk management
      # ===================================================================

      namespace :supply_chain do
        # SBOM Management
        resources :sboms do
          member do
            get :components
            get :vulnerabilities
            post :export
            get :compliance_status
            post :correlate_vulnerabilities
            post :calculate_risk
          end

          collection do
            get :statistics
          end

          # Nested components
          resources :components, only: [ :index, :show ] do
            member do
              get :vulnerabilities
            end
          end

          # Nested vulnerabilities
          resources :vulnerabilities, only: [ :index, :show, :update ] do
            member do
              post :suppress
              post :unsuppress
              post :mark_false_positive
            end
          end

          # SBOM Diffs
          resources :diffs, only: [ :index, :show, :create ]
        end

        # Vulnerability Feeds
        resources :vulnerability_feeds, only: [ :index, :show ] do
          member do
            post :sync
          end

          collection do
            post :sync_all
          end
        end

        # Remediation Plans
        resources :remediation_plans do
          member do
            post :generate_pr
            post :approve
            post :reject
            post :execute
          end
        end

        # Attestations (SLSA)
        resources :attestations do
          member do
            post :verify
            post :sign
            post :record_to_rekor
            get :verification_logs
          end

          collection do
            get :statistics
          end
        end

        # Build Provenance
        resources :build_provenance, only: [ :index, :show ] do
          member do
            post :verify_reproducibility
          end
        end

        # Signing Keys
        resources :signing_keys do
          member do
            post :rotate
            post :revoke
            get :public_key
          end

          collection do
            post :generate
          end
        end

        # Container Images
        resources :container_images do
          member do
            post :scan
            post :evaluate_policies
            get :vulnerabilities
            get :sbom
            post :quarantine
            post :verify
          end

          collection do
            get :statistics
          end
        end

        # Image Policies
        resources :image_policies do
          member do
            post :evaluate
            post :activate
            post :deactivate
          end
        end

        # Vulnerability Scans
        resources :vulnerability_scans, only: [ :index, :show ] do
          member do
            get :details
          end
        end

        # CVE Monitors
        resources :cve_monitors do
          collection do
            post :run_all
          end
          member do
            post :run
            post :pause
            post :resume
            get :alerts
          end
        end

        # License Management
        resources :licenses, only: [ :index, :show ] do
          collection do
            get :categories
            post :check_compatibility
          end
        end

        resources :license_policies do
          member do
            post :evaluate
          end
        end

        resources :license_detections, only: [ :index, :show ] do
          member do
            post :mark_review
          end
        end

        resources :license_violations do
          collection do
            get :statistics
          end
          member do
            post :resolve
            post :request_exception
            post :approve_exception
            post :reject_exception
            post :acknowledge
          end
        end

        resources :attributions do
          collection do
            post :generate_notice_file
            get :export
          end
        end

        # Vendor Risk Management
        resources :vendors do
          member do
            post :assess
            post :reassess
            get :risk_profile
            get :monitoring_events
          end

          collection do
            get :statistics
            get :risk_dashboard
          end

          # Nested assessments
          resources :assessments, controller: "risk_assessments", only: [ :index, :show, :create ] do
            member do
              post :submit_for_review
              post :complete
            end
          end

          # Nested questionnaires
          resources :questionnaires, controller: "questionnaire_responses", only: [ :index, :show, :create ] do
            member do
              post :send_reminder
              post :submit
              post :review
            end
          end
        end

        # Questionnaire Templates (admin/system)
        resources :questionnaire_templates do
          member do
            post :duplicate
            post :publish
            post :unpublish
            post :send_to_vendor
          end
        end

        # Questionnaire Responses (top-level access)
        resources :questionnaire_responses, only: [ :index, :show, :update ] do
          member do
            post :submit
            post :review
            post :send_reminder
            post :approve
            post :reject
            post :request_changes
          end

          collection do
            get "token/:token", to: "questionnaire_responses#show_by_token"
            post "token/:token/submit", to: "questionnaire_responses#submit_by_token"
          end
        end

        # Vendor Monitoring Events
        resources :vendor_monitoring_events, only: [ :index, :show ] do
          member do
            post :acknowledge
            post :resolve
          end
        end

        # Scan Templates (Marketplace)
        resources :scan_templates do
          member do
            post :install
            post :publish
            post :unpublish
          end

          collection do
            get :featured
            get :categories
          end
        end

        # Scan Instances (per-account)
        resources :scan_instances do
          member do
            post :execute
            post :pause
            post :resume
            get :executions
          end
        end

        # Scan Executions
        resources :scan_executions, only: [ :index, :show ] do
          member do
            post :cancel
            get :logs
          end
        end

        # Reports
        resources :reports do
          member do
            get :download
            post :regenerate
          end

          collection do
            post :generate_sbom
            post :generate_attribution
            post :generate_compliance
            post :generate_vulnerability
            post :generate_vendor_risk
          end
        end

        # Dashboard and analytics
        get :dashboard, to: "dashboard#index"
        get :analytics, to: "dashboard#analytics"
        get :compliance_summary, to: "dashboard#compliance_summary"
      end
    end
  end

  # Webhook endpoints (outside of API versioning and auth)
  namespace :webhooks do
    post "stripe", to: "stripe#handle"
    post "paypal", to: "paypal#handle"
    post "git/:provider_type", to: "git#handle"
  end

  # ActionCable WebSocket endpoint
  mount ActionCable.server => "/cable"

  # Root route for API
  root to: proc {
    version = File.exist?(Rails.root.join("..", "VERSION")) ?
              File.read(Rails.root.join("..", "VERSION")).strip : "0.0.1"
    [ 200, {}, [ "Powernode API - Version #{version}" ] ]
  }
end
