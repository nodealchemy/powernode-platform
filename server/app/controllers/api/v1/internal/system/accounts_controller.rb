# frozen_string_literal: true

module Api
  module V1
    module Internal
      module System
        # Internal API controller for system maintenance operations on accounts
        class AccountsController < BaseController
          # GET /api/v1/internal/system/accounts
          # Returns accounts that need maintenance
          def index
            accounts = if params[:for_maintenance]
                        Account.includes(:subscription)
                               .where(subscriptions: { status: %w[active trialing] })
                               .or(Account.includes(:subscription).where(subscriptions: { id: nil }))
                       else
                        Account.all
                       end

            accounts = accounts.limit(params[:limit] || 100)

            render_success(
              data: {
                accounts: accounts.map { |a| account_data(a) }
              }
            )
          end

          # GET /api/v1/internal/system/accounts/:id
          def show
            account = Account.find(params[:id])

            render_success(
              data: {
                account: account_data(account)
              }
            )
          rescue ActiveRecord::RecordNotFound
            render_not_found("Account")
          end

          # GET /api/v1/internal/system/accounts/:id/nodes
          # Returns nodes for an account (used by maintenance)
          def nodes
            account = Account.find(params[:id])
            nodes = account.system_nodes.includes(:node_template, :node_instances)

            render_success(
              data: {
                nodes: nodes.map { |n| node_data(n) }
              }
            )
          rescue ActiveRecord::RecordNotFound
            render_not_found("Account")
          end

          # GET /api/v1/internal/system/accounts/:id/pending_operations
          # Returns pending operations for an account
          def pending_operations
            account = Account.find(params[:id])
            operations = ::System::Operation.where(account: account)
                                            .where(status: %w[pending scheduled])
                                            .where("scheduled_at IS NULL OR scheduled_at <= ?", Time.current)
                                            .order(:created_at)
                                            .limit(params[:limit] || 50)

            render_success(
              data: {
                operations: operations.map { |o| operation_data(o) }
              }
            )
          rescue ActiveRecord::RecordNotFound
            render_not_found("Account")
          end

          private

          def account_data(account)
            {
              id: account.id,
              name: account.name,
              status: account.subscription&.status || "inactive",
              has_system_worker: account.has_system_worker?,
              system_worker_token: account.system_worker_token,
              created_at: account.created_at
            }
          end

          def node_data(node)
            {
              id: node.id,
              name: node.name,
              enabled: node.enabled,
              node_template_id: node.node_template_id,
              instance_count: node.node_instances.size,
              created_at: node.created_at
            }
          end

          def operation_data(operation)
            {
              id: operation.id,
              command: operation.command,
              status: operation.status,
              operable_type: operation.operable_type,
              operable_id: operation.operable_id,
              options: operation.options,
              scheduled_at: operation.scheduled_at,
              created_at: operation.created_at
            }
          end
        end
      end
    end
  end
end
