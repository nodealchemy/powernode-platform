# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class KillSwitchController < InternalBaseController
          # GET /api/v1/internal/ai/kill_switch/check
          # Lightweight endpoint for worker jobs to check AI suspension status.
          # Params: account_id (optional — falls back to @current_account)
          def check
            account = resolve_account
            unless account
              return render_error("Account not found", status: :not_found)
            end

            render_success(
              suspended: account.ai_suspended?,
              since: account.ai_suspended_at&.iso8601
            )
          end

          private

          def resolve_account
            if params[:account_id].present?
              Account.find_by(id: params[:account_id])
            else
              @current_account
            end
          end
        end
      end
    end
  end
end
