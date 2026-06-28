# frozen_string_literal: true

module Ai
  # Single entry point for "develop software in project X" — the platform's
  # primary purpose. Targets ANY registered project (improve/extend an existing
  # repo) and, for greenfield, records a new-project campaign whose repo creation
  # is approval-gated (the live Gitea creation runs at the gated step — see
  # ~/.claude/plans/autoland-initiative-questions.md Q4).
  class ProjectWorkflowService
    DEV_WORKLOADS = %w[feature-development new-project improvement-campaign].freeze

    def initialize(account:, user: nil)
      @account = account
      @user = user
    end

    # Drive a development/improvement campaign on an already-registered repo.
    def start_for_repository(repository:, objective:, name: nil, workload: "feature-development",
                             decision_authority: "trusted", stop_conditions: {})
      repo = resolve_repository(repository)
      raise ArgumentError, "repository not found in account" unless repo

      workload = "feature-development" unless DEV_WORKLOADS.include?(workload)
      driver.start(
        name: name || "#{workload}: #{repo.name}",
        description: objective,
        workload: workload,
        decision_authority: decision_authority,
        stop_conditions: stop_conditions,
        configuration: {
          "repository_id" => repo.id,
          "repository" => repo.full_name,
          "objective" => objective
        }
      )
    end

    # Record a greenfield new-project campaign. The repository does not exist yet;
    # its creation is approval-gated (decision_authority supervised) and performed
    # at the gated step against the account's git provider. Org resolves from
    # account config — never hardcoded.
    def propose_new_project(name:, objective:, org: nil, private_repo: true,
                            decision_authority: "supervised", stop_conditions: {})
      driver.start(
        name: name,
        description: objective,
        workload: "new-project",
        decision_authority: decision_authority,
        stop_conditions: stop_conditions,
        configuration: {
          "objective" => objective,
          "new_project" => {
            "name" => name,
            "org" => org || default_project_org,
            "private" => private_repo,
            "status" => "pending_creation"
          }
        }
      )
    end

    private

    def driver
      @driver ||= Ai::DevLoop::CampaignDriver.new(account: @account, user: @user)
    end

    def resolve_repository(ref)
      return ref if ref.is_a?(::Devops::GitRepository)

      @account.git_repositories.find_by(id: ref) ||
        @account.git_repositories.find_by(full_name: ref) ||
        @account.git_repositories.find_by(name: ref)
    end

    # Configurable per account; no hardcoded org/host.
    def default_project_org
      [
        (@account.respond_to?(:default_project_org) ? @account.default_project_org : nil),
        (@account.respond_to?(:slug) ? @account.slug : nil),
        @account.name.to_s.parameterize.presence
      ].compact.first
    end
  end
end
