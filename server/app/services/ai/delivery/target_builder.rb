# frozen_string_literal: true

module Ai
  module Delivery
    # Builds an account-scoped Ai::Deploy::Target from request/tool params. Shared by the MCP
    # DeliveryTool and the REST DeliveriesController so target resolution (incl. the cross-account
    # repository IDOR guard) lives in exactly one place.
    module TargetBuilder
      module_function

      # Raises ArgumentError on a project target whose repository is not in the account.
      def from_params(account:, target_kind: nil, repository_id: nil, environment: nil, strategy: nil, config: {})
        kind = (target_kind.presence || "project").to_sym
        repository = nil
        if kind == :project && repository_id.present?
          repository = account.git_repositories.find_by(id: repository_id)
          raise ArgumentError, "repository not found in this account" unless repository
        end

        cfg = (config || {}).deep_stringify_keys
        cfg["strategy"] = strategy.to_s if strategy.present?
        Ai::Deploy::Target.new(
          kind: kind, repository: repository,
          environment: environment.presence || "production", config: cfg
        )
      end
    end
  end
end
