# frozen_string_literal: true

module Api
  module V1
    module Internal
      # Worker -> server door for retrying cleanup that must follow a committed
      # deletion (PlatformPurgeTask). The server runs no Sidekiq: the worker's
      # PlatformPurgeSweepJob owns the cadence and calls in here for the work.
      class PlatformPurgeTasksController < InternalBaseController
        # POST /api/v1/internal/platform/purge_tasks/sweep
        def sweep
          result = ::PlatformPurgeTask.run_due!
          render_success(data: result.merge(pending: ::PlatformPurgeTask.where(status: "pending").count))
        end
      end
    end
  end
end
