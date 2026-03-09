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
    get "oauth-protected-resource", to: "well_known#oauth_protected_resource"
    get "oauth-authorization-server", to: "well_known#oauth_authorization_server"
    # RFC 8414 path-based discovery: clients like Claude Code try
    # /.well-known/oauth-authorization-server/<resource-path> first
    get "oauth-protected-resource/*path", to: "well_known#oauth_protected_resource"
    get "oauth-authorization-server/*path", to: "well_known#oauth_authorization_server"
  end


  # Doorkeeper OAuth 2.1 endpoints — outside namespace to avoid controller resolution issues
  # (namespace would prefix module path, causing Api::V1::Doorkeeper::* lookups to fail)
  scope '/api/v1', as: 'api_v1' do
    use_doorkeeper do
      skip_controllers :applications, :authorized_applications
    end
  end

  # API Routes
  namespace :api do
    # BaaS API routes are in enterprise/server/config/routes.rb (enterprise only)

    namespace :v1 do
      # A2A JSON-RPC 2.0 protocol endpoint
      post "/a2a", to: "a2a#handle"
      get "/a2a", to: "a2a#info"
      post "/a2a/stream", to: "a2a#stream"

      # Health check endpoints
      get :health, to: "health#index"
      get "health/detailed", to: "health#detailed"
      get "health/ready", to: "health#ready"
      get "health/live", to: "health#live"

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

          # Auth artifact cleanup
          post "cleanup_auth_artifacts", to: "maintenance#cleanup_auth_artifacts"
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
            collection do
              get :lookup
            end
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

          # Runners management (for worker service)
          resources :runners, only: [ :index ] do
            collection do
              post :sync
            end
            member do
              put :status, action: :update_status
              post :job_completed
            end
          end
        end

        # Internal subscriptions for worker dunning (enterprise only, see enterprise routes)

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
          scope :swarm, as: :swarm do
            get "clusters", to: "swarm#index", as: :clusters
            get "clusters/:id/connection", to: "swarm#connection", as: :cluster_connection
            post "clusters/:id/sync_results", to: "swarm#sync_results", as: :cluster_sync_results
            post "clusters/:id/health_results", to: "swarm#health_results", as: :cluster_health_results
            patch "deployments/:id", to: "swarm#update_deployment", as: :deployment
            post "events", to: "swarm#create_event", as: :events
          end

          # Docker Host internal endpoints (worker communication)
          scope :docker, as: :docker do
            get "hosts", to: "docker#index", as: :hosts
            get "hosts/:id/connection", to: "docker#connection", as: :host_connection
            post "hosts/:id/sync_results", to: "docker#sync_results", as: :host_sync_results
            post "hosts/:id/health_results", to: "docker#health_results", as: :host_health_results
            post "events", to: "docker#create_event", as: :events
          end

          # Container & DevOps maintenance (worker → server)
          scope :maintenance, controller: "maintenance" do
            post :reconcile_instances
            post :cleanup_expired_ports
            post :archive_stale_templates
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

        # Billing endpoints for worker service (enterprise only, see enterprise routes)

        # Internal AI endpoints (for worker service)
        namespace :ai do
          resources :skills, only: [] do
            collection do
              post :seed_system
              post :mutate
              post :auto_evolve
            end
            member do
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

          # Tool bridge endpoints (worker → server)
          # LLM completion endpoints removed — worker calls providers directly.
          # Only tool registry and reasoning orchestration remain server-side.
          scope "llm", controller: "llm_proxy" do
            post :tool_definitions
            post :dispatch_tool
            post :execute_with_reasoning
          end

          # Execution context endpoint (worker → server)
          post "execution_contexts", to: "execution_contexts#create"

          # Provider config for direct LLM access (worker → server)
          post "provider_config", to: "execution_contexts#provider_config"

          # Embedding provider config (worker → server)
          get "embedding_config", to: "execution_contexts#embedding_config"

          # Agent execution management (worker → server)
          get "executions/:id", to: "agent_executions#show"
          patch "executions/:id", to: "agent_executions#update"
          post "executions/:id/cancel", to: "agent_executions#cancel"

          # Team strategy execution (worker → server)
          post "teams/:team_id/execute_strategy", to: "teams#execute_strategy"

          # Self-healing endpoints (worker → server)
          scope "self_healing", controller: "self_healing" do
            post :check_stuck_workflows
            post :check_degraded_providers
            post :check_orphaned_executions
            post :check_anomalies
          end

          # Ralph loop endpoints (worker → server)
          scope "ralph_loops" do
            post "process_scheduled", to: "ralph_loops#process_scheduled"
            post ":id/run_iteration", to: "ralph_loops#run_iteration"
          end

          # Trajectory analysis endpoint (worker → server)
          post "trajectory/analyze_all", to: "trajectory#analyze_all"

          # Worktree session management (worker → server)
          resources :worktree_sessions, only: [:show] do
            member do
              post :start
              post :activate
              post :fail_session
              post :cleanup
              post :push_and_pr
              post :execute_merge
              post :detect_conflicts
              get :dispatch_status
              post :timeout_dispatches
            end
            collection do
              post :check_timeouts
            end
          end
          post "worktree_sessions/:id/worktrees/:worktree_id/provision",
               to: "worktree_sessions#provision_worktree",
               as: :provision_worktree_session_worktree

          # Kill switch check (worker → server)
          get "kill_switch/check", to: "kill_switch#check"

          # Autonomy observation pipeline (worker → server)
          get "observation_pipeline/accounts", to: "autonomy#observation_accounts"
          post "observation_pipeline/run", to: "autonomy#run_observation_pipeline"

          # Autonomy goal maintenance (worker → server)
          post "goals/maintenance", to: "autonomy#goals_maintenance"

          # Autonomy observation cleanup (worker → server)
          post "observations/cleanup", to: "autonomy#observations_cleanup"

          # Autonomy escalation auto-escalate (worker → server)
          post "escalations/auto_escalate", to: "autonomy#auto_escalate_escalations"

          # Autonomy proposal expiry (worker → server)
          post "proposals/expire_overdue", to: "autonomy#expire_overdue_proposals"

          # Autonomy intervention policy tuning (worker → server)
          post "intervention_policies/analyze_patterns", to: "autonomy#analyze_policy_patterns"

          # Phase 1: Experience replay + reflexion (worker → server)
          post "experience_replays/capture", to: "experience_replays#capture"
          post "reflexions/reflect", to: "reflexions#reflect"

          # Phase 2: Goal plan execution (worker → server)
          post "goal_plans/execute_step", to: "goal_plans#execute_step"

          # Phase 3: Coordination (worker → server)
          scope "coordination", controller: "coordination" do
            post :decay_signals
            post :measure_all_fields
            post :decay_fields
          end

          # Phase 4: Self-challenges (worker → server)
          scope "self_challenges", controller: "self_challenges" do
            post :process, action: :process_challenge
            post :schedule_daily
          end

          # Phase 4: Governance (worker → server)
          scope "governance", controller: "governance" do
            post :scan_all
            post :detect_collusion
          end
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

      # OAuth Applications Management API
      namespace :oauth do
        # Public lookup for consent page (no auth needed)
        get 'applications/lookup', to: 'applications#lookup'

        # RFC 7591 Dynamic Client Registration (public, no auth)
        post :register, to: "registrations#create"

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
            post :cleanup_sessions
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

      # ===================================================================
      # Marketing routes are in extensions/marketing/server/config/routes.rb

      # Worker authentication endpoints (for worker service)
      namespace :worker_auth do
        post :verify
        post :authenticate_user
        post :verify_session
        post :verify_platform_token
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

      # Plans management is in enterprise/server/config/routes.rb

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

        # Extensions management
        get :extensions, on: :member
        put "extensions/:slug/toggle", on: :member, action: :toggle_extension

        # Development / enterprise toggle
        get :development, on: :member
        put :development, on: :member, action: :update_development

        # Security configuration endpoints
        get :security, on: :member, action: :security_config
        put :security, on: :member, action: :update_security_config
        post "security/test", on: :member, action: :test_security_config
        post "security/regenerate_jwt_secret", on: :member, action: :regenerate_jwt_secret
        delete "security/blacklisted_tokens", on: :member, action: :clear_blacklisted_tokens
        get "security/blacklist_stats", on: :member, action: :blacklist_statistics
        get "security/audit_summary", on: :member, action: :security_audit_summary

        # Infrastructure configuration
        get :infrastructure, on: :member, action: :infrastructure_config
        put :infrastructure, on: :member, action: :update_infrastructure_config
        post "infrastructure/test_redis", on: :member, action: :test_redis_connection
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
          get "health/services", to: "maintenance#service_health"

          # Database operations
          get "database/stats", to: "maintenance#database_stats"
          post "database/analyze", to: "maintenance#analyze_database"

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

      # Customer management endpoints
      resources :customers do
        member do
          get :stats
          patch :update_status
        end
      end

      # Billing routes are in enterprise/server/config/routes.rb (enterprise only)

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

      # Analytics tiers are in enterprise/server/config/routes.rb

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

      # Predictive analytics, reseller routes are in enterprise/server/config/routes.rb

      # Payment reconciliation is in enterprise/server/config/routes.rb

      # Webhook endpoints (billing webhooks are in enterprise routes)
      namespace :webhooks do
        # Git webhook receiver (core)
        post "git/:provider_type", to: "git#handle"

        # Container registry build notifications
        post "container_registry", to: "container_registry#handle"

        # Generic webhook event processing (for worker service)
        resources :events, only: [ :show, :update ] do
          member do
            patch :processing
            patch :processed
            patch :failed
          end
        end
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

      # Impersonation routes are in enterprise/server/config/routes.rb

      # Marketplace routes are in enterprise/server/config/routes.rb

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
            # Template conversions → WorkflowTemplatesController
            post :convert_to_template, to: "workflow_templates#convert_to_template"
            post :convert_to_workflow, to: "workflow_templates#convert_to_workflow"
            post :create_from_template, to: "workflow_templates#create_from_template"
          end

          collection do
            post :import
            get :statistics
            get :templates, to: "workflow_templates#templates"
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
            get ".well-known/agent.json", to: "a2a#agent_card", as: :agent_card
          end

          collection do
            get :my_agents
            get :public_agents
            get :agent_types
            get :statistics
          end

          # Agent intelligence (experience replays, self-challenges)
          get "intelligence/summary", to: "agent_intelligence#summary", as: :intelligence_summary
          get "intelligence/experience_replays", to: "agent_intelligence#experience_replays", as: :intelligence_experience_replays
          get "intelligence/self_challenges", to: "agent_intelligence#self_challenges", as: :intelligence_self_challenges

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
              post :clear_messages
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
                delete :destroy, action: :destroy_message
                post :restore, action: :restore_message
                get :thread, action: :message_thread
                post :reply, action: :reply_to_message
                get :edit_history
              end
            end
          end
        end

        # ===================================================================
        # 3. PROVIDERS - Split into providers, credentials, sync controllers
        # ===================================================================
        resources :providers do
          member do
            get :models
            get :usage_summary
            get :check_availability
          end

          collection do
            get :available
            get :statistics
          end

          # Nested credentials → ProviderCredentialsController
          resources :credentials, controller: "provider_credentials" do
            member do
              post :test
              post :make_default
              post :rotate
            end
          end
        end

        # Flat credential decrypt route for worker access (not nested under provider)
        post "credentials/:id/decrypt", to: "provider_credentials#decrypt", as: :decrypt_ai_credential

        # Provider sync operations → ProviderSyncController
        scope :providers, controller: "provider_sync" do
          post ":id/test_connection", action: :test_connection, as: :test_connection_provider
          post ":id/sync_models", action: :sync_models, as: :sync_models_provider
          post "setup_defaults", action: :setup_defaults, as: :setup_defaults_providers
          post "test_all", action: :test_all, as: :test_all_providers
          post "sync_all", action: :sync_all, as: :sync_all_providers
        end

        # ===================================================================
        # 4. GLOBAL CONVERSATIONS CONTROLLER - Cross-agent conversation management
        # ===================================================================
        resources :conversations, only: [ :index, :show, :update, :destroy ] do
          collection do
            get :search
            patch :bulk
            post :team, action: :create_team
            post :concierge, action: :create_concierge
          end
          member do
            post :archive
            post :unarchive
            post :duplicate
            post :pin
            delete :unpin
            get :stats
            post :plan_response
            post :confirm_action
            post :worker_complete
            post :worker_stream_chunk
            post :worker_error

            # Scheduled messages nested under conversation
            get "scheduled_messages", action: :scheduled_messages_index
            post "scheduled_messages", action: :scheduled_messages_create
            patch "scheduled_messages/:id", action: :scheduled_messages_update, as: :scheduled_message_update
            delete "scheduled_messages/:id", action: :scheduled_messages_destroy, as: :scheduled_message_destroy
          end
        end

        # ===================================================================
        # WORKSPACES - Multi-agent collaborative conversations
        # ===================================================================
        resources :workspaces, only: [:index, :create, :show] do
          collection do
            get :active_sessions
          end
          member do
            post :invite
            delete "members/:agent_id", action: :remove_member, as: :remove_member
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
        # 5.5 GOVERNANCE REPORTS - Phase 4 governance scan results & collusion
        # ===================================================================
        resources :governance_reports, only: [:index, :show] do
          member do
            put :resolve
          end
          collection do
            get :summary
            get :collusion_indicators
            get :collusion_summary
          end
        end

        # ===================================================================
        # 5.6 COORDINATION DASHBOARD - Stigmergic signals, pressure fields, team events
        # ===================================================================
        scope "coordination", controller: "coordination_dashboard" do
          get :summary
          get :signals
          get :pressure_fields
          get :team_events
        end

        # ===================================================================
        # 5.7 EXECUTION TRACES - Debugging & tracing
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
        # Analytics dashboard → AnalyticsController
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
        end

        # Analytics reports → AnalyticsReportsController
        scope "analytics/reports", controller: "analytics_reports" do
          get "/", action: :reports_index
          post "/", action: :report_create
          get "templates", action: :report_templates
          get "/:id", action: :report_show
          delete "/:id", action: :report_cancel
          get "/:id/download", action: :report_download
        end

        # ===================================================================
        # 7. VALIDATION STATISTICS - Aggregate validation analytics
        # ===================================================================
        resource :validation_statistics, only: [ :show ] do
          get :common_issues
          get :health_distribution
        end

        # Marketplace routes (8) are in enterprise/server/config/routes.rb

        # Publisher routes are in enterprise/server/config/routes.rb

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
            post 'search', action: :global_search
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
        # 10.5. KNOWLEDGE GRAPH - Knowledge Graphs + Hybrid RAG
        # ===================================================================
        scope :knowledge_graph, controller: "knowledge_graph" do
          # Nodes CRUD
          get "nodes", action: :nodes
          get "nodes/:id", action: :show_node
          post "nodes", action: :create_node
          patch "nodes/:id", action: :update_node
          delete "nodes/:id", action: :destroy_node

          # Node traversal
          get "nodes/:id/neighbors", action: :neighbors

          # Edges CRUD
          get "edges", action: :edges
          post "edges", action: :create_edge
          delete "edges/:id", action: :destroy_edge

          # Graph operations
          get "shortest_path", action: :shortest_path
          post "subgraph", action: :subgraph
          post "extract", action: :extract
          get "statistics", action: :statistics
          post "reason", action: :multi_hop_reason
          post "search", action: :hybrid_search
        end

        # ===================================================================
        # 10.6. SKILL GRAPH - Skill ↔ Knowledge Graph Integration
        # ===================================================================
        scope :skill_graph, controller: "skill_graph" do
          get "subgraph", action: :subgraph
          post "sync", action: :sync
          post "discover", action: :discover
          post "edges", action: :create_edge
          patch "edges/:id", action: :update_edge
          delete "edges/:id", action: :destroy_edge
          post "auto_detect", action: :auto_detect
          get "team_coverage/:team_id", action: :team_coverage
          post "team_gaps/:team_id", action: :team_gaps
          post "suggest_agents/:team_id", action: :suggest_agents
          post "compose_team", action: :compose_team
          get "agent_context/:agent_id", action: :agent_context

          # Lifecycle - proposals
          post "research", action: :research
          get "proposals", action: :list_proposals
          post "proposals", action: :create_proposal
          get "proposals/:id", action: :show_proposal
          post "proposals/:id/submit", action: :submit_proposal
          post "proposals/:id/approve", action: :approve_proposal
          post "proposals/:id/reject", action: :reject_proposal
          post "proposals/:id/create_skill", action: :create_skill_from_proposal

          # Conflicts & Health
          get "conflicts", action: :conflicts
          post "conflicts/:id/resolve", action: :resolve_conflict
          post "conflicts/:id/dismiss", action: :dismiss_conflict
          post "scan", action: :scan_conflicts
          get "health", action: :health_score

          # Evolution
          get "skills/:skill_id/metrics", action: :skill_metrics
          get "skills/:skill_id/versions", action: :version_history
          post "skills/:skill_id/evolve", action: :propose_evolution
          post "versions/:id/activate", action: :activate_version
          post "skills/:skill_id/ab_test", action: :start_ab_test
          post "skills/:skill_id/end_ab_test", action: :end_ab_test
          post "record_outcome", action: :record_outcome

          # Optimization & Maintenance
          post "optimize", action: :run_optimization
          post "maintenance/daily", action: :maintenance_daily
          post "maintenance/weekly", action: :maintenance_weekly
          post "maintenance/monthly", action: :maintenance_monthly
          # Event-driven single-skill conflict check (called by worker jobs)
          post "conflict_check", action: :conflict_check
        end

        # ===================================================================
        # 11. TEAMS CONTROLLER - Multi-Agent Team Orchestration
        # ===================================================================
        # Revenue: Tiered subscriptions + agent seat pricing
        # - Starter: 3 agents, 1 team ($49/mo)
        # - Pro: 10 agents, 5 teams, advanced patterns ($199/mo)
        # - Enterprise: Unlimited + custom topologies ($999/mo)
        # ===================================================================
        # Team channel messages (chat integration)
        get "/channels", to: "team_channel_messages#my_channels"
        scope "teams/:team_id/channels/:channel_id", controller: "team_channel_messages" do
          get "/messages", action: :messages
          post "/messages", action: :send_message
          post "/link", action: :link_chat_channel
          delete "/unlink", action: :unlink_chat_channel
        end

        scope :teams do
          # Templates, Role Profiles, Trajectories, Reviews → TeamTemplatesReviewsController
          scope controller: "team_templates_reviews" do
            get "/templates", action: :list_templates
            get "/templates/:id", action: :show_template
            post "/templates", action: :create_template
            post "/templates/:id/publish", action: :publish_template
            get "/role_profiles", action: :list_role_profiles
            get "/role_profiles/:id", action: :show_role_profile
            get "/trajectories", action: :list_trajectories
            get "/trajectories/search", action: :search_trajectories
            get "/trajectories/:id", action: :show_trajectory
            get "/reviews/:id", action: :show_review
            post "/reviews/:id/process", action: :process_review
            get "/reviews/:review_id/comments", action: :list_review_comments
            post "/reviews/:review_id/comments", action: :create_review_comment
            patch "/reviews/:review_id/comments/:comment_id", action: :update_review_comment
          end

          # Executions, Tasks, Messages → TeamExecutionController
          scope controller: "team_execution" do
            get "/:team_id/executions", action: :list_executions
            post "/:team_id/executions", action: :start_execution
            get "/executions/:id", action: :show_execution
            post "/executions/:id/pause", action: :pause_execution
            post "/executions/:id/resume", action: :resume_execution
            post "/executions/:id/cancel", action: :cancel_execution
            post "/executions/:id/complete", action: :complete_execution
            get "/executions/:id/details", action: :execution_details
            get "/executions/:execution_id/tasks", action: :list_tasks
            post "/executions/:execution_id/tasks", action: :create_task
            get "/executions/:execution_id/tasks/:id", action: :show_task
            post "/executions/:execution_id/tasks/:id/assign", action: :assign_task
            post "/executions/:execution_id/tasks/:id/start", action: :start_task
            post "/executions/:execution_id/tasks/:id/complete", action: :complete_task
            post "/executions/:execution_id/tasks/:id/fail", action: :fail_task
            post "/executions/:execution_id/tasks/:id/delegate", action: :delegate_task
            get "/executions/:execution_id/tasks/:task_id/reviews", action: :list_task_reviews
            get "/executions/:execution_id/messages", action: :list_messages
            post "/executions/:execution_id/messages", action: :send_message
            post "/executions/:execution_id/messages/:id/reply", action: :reply_to_message
          end

          # Teams CRUD, Analytics, Health → TeamsController
          scope controller: "teams" do
            get "/", action: :index
            get "/:id", action: :show
            post "/", action: :create
            patch "/:id", action: :update
            delete "/:id", action: :destroy
            get "/:team_id/analytics", action: :analytics
            get "/:team_id/composition_health", action: :composition_health
            put "/:team_id/review_config", action: :update_review_config
          end

          # Roles, Channels, Cleanup → TeamRolesChannelsController
          scope controller: "team_roles_channels" do
            post "/cleanup_messages", action: :cleanup_messages
            get "/:team_id/roles", action: :list_roles
            post "/:team_id/roles", action: :create_role
            patch "/:team_id/roles/:id", action: :update_role
            delete "/:team_id/roles/:id", action: :delete_role
            post "/:team_id/roles/:id/assign_agent", action: :assign_agent_to_role
            post "/:team_id/roles/:id/apply_profile", action: :apply_role_profile
            get "/:team_id/channels", action: :list_channels
            post "/:team_id/channels", action: :create_channel
            get "/:team_id/channels/:id", action: :show_channel
            patch "/:team_id/channels/:id", action: :update_channel
            delete "/:team_id/channels/:id", action: :delete_channel
          end
        end

        # ===================================================================
        # 12. AGENT TEAMS CONTROLLER - CrewAI-style team orchestration (Legacy)
        # ===================================================================
        resources :agent_teams do
          member do
            post :execute
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

        # A2A Protocol - Unified scope (merged from two separate blocks)
        scope :a2a do
          # REST task operations → A2aTasksController
          resources :tasks, controller: "a2a_tasks", param: :task_id, as: :a2a_tasks do
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
          end

          # Discovery and JSON-RPC → A2aController
          post :discover, to: "a2a#discover"
          post :jsonrpc, to: "a2a#jsonrpc"
          get "task/:id", to: "a2a#show_task", as: :a2a_show_task
          post "task/:id/cancel", to: "a2a#cancel_task", as: :a2a_cancel_task
        end

        # ===================================================================
        # MISSION TEMPLATES - Reusable mission phase definitions
        # ===================================================================
        resources :mission_templates, controller: "mission_templates", only: [:index, :show, :create, :update, :destroy]

        # ===================================================================
        # MISSIONS - AI-Assisted Development Hub
        # ===================================================================
        scope :missions, controller: "missions" do
          get "/", action: :index
          post "/", action: :create
          post "analyze_repo", action: :analyze_repo
          get ":id", action: :show
          patch ":id", action: :update
          delete ":id", action: :destroy
          post ":id/start", action: :start
          post ":id/approve", action: :approve
          post ":id/reject", action: :reject
          post ":id/pause", action: :pause
          post ":id/resume", action: :resume
          post ":id/cancel", action: :cancel
          post ":id/retry", action: :retry_phase
          post ":id/deploy_callback", action: :deploy_callback

          # Worker-called phase endpoints
          post ":id/advance", action: :advance
          post ":id/create_branch", action: :create_branch
          post ":id/generate_prd", action: :generate_prd
          post ":id/run_tests", action: :run_tests
          get  ":id/test_status", action: :test_status
          post ":id/deploy", action: :deploy
          post ":id/create_pr", action: :create_pr
          post ":id/cleanup_deployment", action: :cleanup_deployment
          get  ":id/task_graph", action: :task_graph
          post ":id/save_as_template", action: :save_as_template
          post ":id/compose_plan", action: :compose_plan
        end

        # ===================================================================
        # CODE FACTORY - Risk contracts, preflight gates, SHA discipline
        # ===================================================================
        scope :code_factory, controller: "code_factory" do
          get "contracts", action: :index
          post "contracts", action: :create
          get "contracts/:id", action: :show
          put "contracts/:id", action: :update
          post "contracts/:id/activate", action: :activate
          post "preflight", action: :preflight
          get "review_states", action: :review_states
          get "review_states/:id", action: :review_state_show
          post "review_states/:id/remediate", action: :remediate
          post "review_states/:id/resolve_threads", action: :resolve_threads
          post "evidence", action: :submit_evidence
          get "evidence/:id", action: :show_evidence
          get "harness_gaps", action: :harness_gaps
          post "harness_gaps", action: :create_harness_gap
          put "harness_gaps/:id/add_case", action: :add_test_case
          put "harness_gaps/:id/close", action: :close_harness_gap
          post "webhook", action: :webhook
        end

        # ACP Protocol - Agent Communication Protocol (Cisco standard)
        # REST-based agent-centric protocol alongside A2A
        scope :acp, as: :acp_protocol do
          get "/", to: "acp#info", as: :info
          get :agents, to: "acp#list_agents"
          get "agents/:id", to: "acp#show_agent", as: :show_agent
          post "agents/:id/negotiate", to: "acp#negotiate", as: :negotiate
          post "agents/:id/messages", to: "acp#send_message", as: :send_message
          get "agents/:id/events", to: "acp#events", as: :events
          get "messages/:id", to: "acp#show_message", as: :show_message
          post "messages/:id/cancel", to: "acp#cancel_message", as: :cancel_message
        end

        # Agent Memory Enhancement - inject route consolidated into main memory scope below

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
            get :learnings
            get :progress
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

        # Ralph Loops scheduling → RalphLoopsSchedulingController
        scope "ralph_loops/:id", controller: "ralph_loops_scheduling" do
          post "run_iteration", action: :run_iteration
          post "run_all", action: :run_all
          post "stop_run_all", action: :stop_run_all
          post "pause_schedule", action: :pause_schedule
          post "resume_schedule", action: :resume_schedule
          post "regenerate_webhook_token", action: :regenerate_webhook_token
          post "parse_prd", action: :parse_prd
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
        scope :model_router do
          # Rules & decisions → ModelRouterController
          scope controller: "model_router" do
            get "rules", action: :rules_index
            post "rules", action: :create_rule
            get "rules/:id", action: :show_rule
            patch "rules/:id", action: :update_rule
            delete "rules/:id", action: :destroy_rule
            post "rules/:id/toggle", action: :toggle_rule
            get "decisions", action: :decisions
            get "decisions/:id", action: :show_decision
          end

          # Analytics & optimizations → ModelRouterAnalyticsController
          scope controller: "model_router_analytics" do
            post "route", action: :route
            get "statistics", action: :statistics
            get "cost_analysis", action: :cost_analysis
            get "provider_rankings", action: :provider_rankings
            get "recommendations", action: :recommendations
            get "optimizations", action: :optimizations_index
            post "optimizations/identify", action: :identify_optimizations
            post "optimizations/:id/apply", action: :apply_optimization
          end
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
        end

        scope "roi/calculations", controller: "roi_calculations" do
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
        # 14b. FINOPS CONTROLLER - Smart Model Routing & Financial Operations
        # ===================================================================
        # Token analytics, waste analysis, forecasting, and optimization scoring
        # ===================================================================
        scope :finops, controller: "finops" do
          get "/", action: :index
          get "cost_breakdown", action: :cost_breakdown
          get "trends", action: :trends
          get "budget_utilization", action: :budget_utilization
          get "token_analytics", action: :token_analytics
          get "waste_analysis", action: :waste_analysis
          get "forecast", action: :forecast
          get "optimization_score", action: :optimization_score
        end

        # Credits and outcome billing routes are in enterprise/server/config/routes.rb

        # Agent marketplace routes (17) are in enterprise/server/config/routes.rb

        # Governance routes are in enterprise/server/config/routes.rb

        # ===================================================================
        # 19. DEVOPS CONTROLLER - AI Pipeline Templates for DevOps
        # ===================================================================
        # Revenue: Template marketplace + enterprise customization
        # - Community templates: free
        # - Premium templates: $29-99 one-time
        # - Custom template development: $2,000-10,000
        # - Enterprise template library: $199/mo
        # ===================================================================
        scope :devops do
          # Templates & installations → DevopsController
          scope controller: "devops" do
            get "templates", action: :templates
            get "templates/:id", action: :show_template
            post "templates", action: :create_template
            patch "templates/:id", action: :update_template
            get "installations", action: :installations
            post "templates/:template_id/install", action: :install
            delete "installations/:id", action: :uninstall
          end

          # Executions & analytics → DevopsExecutionsController
          scope controller: "devops_executions" do
            get "executions", action: :executions
            post "executions", action: :create_execution
            get "executions/:id", action: :show_execution
            get "analytics", action: :analytics
          end

          # Risks & code reviews → DevopsRiskReviewController
          scope controller: "devops_risk_review" do
            get "risks", action: :risks
            post "risks/assess", action: :assess_risk
            put "risks/:id/approve", action: :approve_risk
            put "risks/:id/reject", action: :reject_risk
            get "reviews", action: :reviews
            post "reviews", action: :create_review
            get "reviews/:id", action: :show_review
          end
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

          # Scenarios & mocks → SandboxScenariosController
          get "scenarios", to: "sandbox_scenarios#scenarios"
          post "scenarios", to: "sandbox_scenarios#create_scenario"
          get "mocks", to: "sandbox_scenarios#mocks"
          post "mocks", to: "sandbox_scenarios#create_mock"

          # Test runs & benchmarks → SandboxTestingController
          get "runs", to: "sandbox_testing#runs"
          post "runs", to: "sandbox_testing#create_run"
          get "runs/:run_id", to: "sandbox_testing#show_run"
          post "runs/:run_id/execute", to: "sandbox_testing#execute_run"
          get "benchmarks", to: "sandbox_testing#benchmarks"
          post "benchmarks", to: "sandbox_testing#create_benchmark"
          post "benchmarks/:benchmark_id/run", to: "sandbox_testing#run_benchmark"
        end

        # A/B Tests → SandboxTestingController
        scope :ab_tests, controller: "sandbox_testing" do
          get "/", action: :ab_tests
          post "/", action: :create_ab_test
          put "/:id/start", action: :start_ab_test
          get "/:id/results", action: :ab_test_results
        end

        # ===================================================================
        # 20b. CONTAINER SANDBOXES - Runtime agent container management
        # ===================================================================
        resources :container_sandboxes, only: [:index, :show, :create, :destroy] do
          member do
            post :pause
            post :resume
            get :metrics
          end
          collection do
            get :stats
          end
        end

        # ===================================================================
        # 21. AUTONOMY - Trust scores, lineage, and budgets
        # ===================================================================
        scope :autonomy, controller: "autonomy" do
          get "trust_scores", action: :trust_scores
          get "trust_scores/:agent_id", action: :show_trust_score
          post "trust_scores/:agent_id/evaluate", action: :evaluate
          put "trust_scores/:agent_id/override", action: :override_trust_score
          post "trust_scores/:agent_id/emergency_demote", action: :emergency_demote
          post "trust_scores/decay", action: :decay
          get "lineage", action: :lineage_forest
          get "lineage/:agent_id", action: :lineage
          get "budgets", action: :budgets
          get "budgets/expired", action: :expired_budgets
          get "budgets/reconcile", action: :reconcile_budgets
          get "budgets/alerts", action: :budget_alerts
          post "budgets", action: :create_budget
          put "budgets/:id", action: :update_budget
          delete "budgets/:id", action: :destroy_budget
          post "budgets/:id/allocate_child", action: :allocate_child
          get "budgets/:id/check", action: :check_budget
          post "budgets/:id/rollover", action: :rollover_budget
          get "budgets/:id/transactions", action: :budget_transactions
          get "stats", action: :stats
          get "capability_matrix", action: :capability_matrix
          get "capability_matrix/:agent_id", action: :agent_capabilities
          get "circuit_breakers", action: :circuit_breakers
          get "circuit_breakers/:agent_id", action: :agent_circuit_breakers
          post "circuit_breakers/:id/reset", action: :reset_circuit_breaker
          get "approvals", action: :approval_queue
          post "approvals/:id/approve", action: :approve_action
          post "approvals/:id/reject", action: :reject_action
          get "shadow_executions", action: :shadow_executions
          get "shadow_executions/:agent_id", action: :agent_shadow_executions
          get "telemetry", action: :telemetry_events
          post "telemetry", action: :create_telemetry_event
          get "telemetry/:agent_id", action: :agent_telemetry
          get "delegation_policies", action: :delegation_policies
          get "delegation_policies/:agent_id", action: :agent_delegation_policy
          post "delegation_policies", action: :create_delegation_policy
          put "delegation_policies/:id", action: :update_delegation_policy
          delete "delegation_policies/:id", action: :destroy_delegation_policy
          get "behavioral_fingerprints/:agent_id", action: :behavioral_fingerprints
          post "broadcast", action: :relay_broadcast
          get "cost_thresholds", action: :cost_thresholds
          post "trust_scores/:agent_id/evaluate_from_execution", action: :evaluate_from_execution
          post "budgets/rollover_expired", action: :rollover_expired
          match "pricing/lookup", action: :pricing_lookup, via: [:get, :post]
          # Pricing
          post "pricing/sync", action: :sync_pricing
          get "pricing", action: :pricing_catalog
          patch "pricing/:model_id", action: :update_pricing
        end

        # ===================================================================
        # KILL SWITCH - Emergency halt for all AI activity
        # ===================================================================
        scope :kill_switch, controller: "kill_switch" do
          post :halt
          post :resume
          get :status
          get :preview_restore
          get :events
        end

        # ===================================================================
        # AGENT GOALS - Hierarchical goal tracking for autonomous agents
        # ===================================================================
        resources :goals, controller: "goals" do
          resources :plans, only: [:index, :show], controller: "goal_plans"
        end

        # ===================================================================
        # INTERVENTION POLICIES - User-configurable agent notification rules
        # ===================================================================
        resources :intervention_policies, controller: "intervention_policies" do
          collection do
            post :resolve
          end
        end

        # ===================================================================
        # PROPOSALS - Agent-initiated change proposals for human review
        # ===================================================================
        resources :proposals, controller: "proposals", only: %i[index show] do
          member do
            post :approve
            post :reject
            put :withdraw
          end
          collection do
            post :batch_review
          end
        end

        # ===================================================================
        # ESCALATIONS - Structured escalation for stuck/failed agents
        # ===================================================================
        resources :escalations, controller: "escalations", only: %i[index show] do
          member do
            post :acknowledge
            post :resolve
          end
        end

        # ===================================================================
        # FEEDBACK - User feedback on agent performance
        # ===================================================================
        resources :feedback, controller: "feedback", only: %i[create index]

        # ===================================================================
        # 22. TIERED MEMORY - Multi-tier agent memory management
        # ===================================================================
        # Nested under agents for agent-specific memory operations
        scope "agents/:agent_id" do
          get "tiered_memory/stats", to: "tiered_memory#stats"
          get "tiered_memory", to: "tiered_memory#index"
          post "tiered_memory", to: "tiered_memory#create"
          post "tiered_memory/consolidate", to: "tiered_memory#consolidate"
          delete "tiered_memory/:key", to: "tiered_memory#destroy"
        end

        # Shared knowledge (not agent-specific)
        get "memory/shared_knowledge", to: "tiered_memory#shared_knowledge"

        # Memory maintenance endpoints (called by worker jobs)
        post "memory/consolidate", to: "tiered_memory#consolidate_all"
        post "memory/decay", to: "tiered_memory#decay_all"
        post "memory/shared_maintenance", to: "tiered_memory#shared_maintenance"
        # Event-driven single-entry consolidation (called by worker jobs)
        post "memory/consolidate_entry", to: "tiered_memory#consolidate_entry"

        # ===================================================================
        # 23. SECURITY - Anomaly detection & PII scanning
        # ===================================================================
        namespace :security do
          resource :anomaly_detection, only: [] do
            post :analyze
            post :check_action
            post :detect_injection
            post :detect_rogue
            get :report
          end
          resource :pii_redaction, only: [] do
            post :scan
            post :redact
            post :apply_policy
            post :check_output
            post :batch_scan
          end

          # Phase 7: Agent Identity Management (OWASP ASI03)
          scope :identities, controller: "agent_identity" do
            get "/", action: :index
            post "/", action: :provision
            get "/:id", action: :show
            post "/:id/rotate", action: :rotate
            post "/:id/revoke", action: :revoke
            post "/verify", action: :verify
          end

          # Phase 7: Quarantine Management (OWASP ASI08/ASI10)
          scope :quarantine, controller: "quarantine" do
            get "/", action: :index
            get "/report", action: :security_report
            get "/compliance", action: :compliance_matrix
            get "/:id", action: :show
            post "/", action: :quarantine_agent
            post "/:id/escalate", action: :escalate
            post "/:id/restore", action: :restore
          end
        end

        # ===================================================================
        # 24. INTELLIGENCE - Moved to enterprise/server/config/routes.rb
        # ===================================================================

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
          post "memory_maintenance", action: :memory_maintenance
          post "knowledge_doc_sync", action: :knowledge_doc_sync
          post "knowledge_graph_maintenance", action: :knowledge_graph_maintenance
          # Event-driven single-entity endpoints (called by worker jobs)
          post "promote_learning", action: :promote_learning
          post "dedup_check", action: :dedup_check
          post "update_graph_node", action: :update_graph_node
          get "benchmarks", action: :benchmarks
          post "benchmarks", action: :create_benchmark
          post "benchmarks/:id/run", action: :run_benchmark
          get "evaluation_results", action: :evaluation_results
        end

        # ===================================================================
        # AG-UI PROTOCOL - Agent-User Interaction Protocol
        # ===================================================================
        scope :agui, controller: "agui" do
          post "run", action: :run
          get "sessions", action: :sessions
          post "sessions", action: :create_session
          get "sessions/:id", action: :show_session
          delete "sessions/:id", action: :destroy_session
          post "sessions/:id/state", action: :push_state
          get "sessions/:id/events", action: :events
        end

        # ===================================================================
        # MCP APPS - MCP Application Framework
        # ===================================================================
        scope :mcp_apps, controller: "mcp_apps" do
          get "/", action: :index
          post "/", action: :create
          get "/:id", action: :show
          patch "/:id", action: :update
          delete "/:id", action: :destroy
          post "/:id/render", action: :render_app
          post "/:id/process", action: :process_input
        end
      end

      # MCP hosting routes are in enterprise/server/config/routes.rb
      namespace :mcp do
        # MCP Streamable HTTP endpoint for external MCP clients (e.g., Claude Code)
        post "message", to: "streamable_http#message"
        get "message", to: "streamable_http#stream"
        delete "message", to: "streamable_http#terminate_session"

        # MCP session management (view/revoke active sessions)
        resources :sessions, only: [:index, :show, :destroy], controller: "sessions"

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
        # Aggregated overview
        resource :overview, only: [ :show ], controller: "overview"

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
            post :trigger_build
            get :builds
          end

          collection do
            get :categories
            get :featured
            post :create_image_repo
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

    end
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
