# frozen_string_literal: true

module Ai
  module Land
    # Reads CI status for a SHA from the platform's ingested pipeline data
    # (Devops::GitPipeline, populated by the git webhook / pipeline-sync jobs).
    # Used to gate the staged branch before merge and develop@merged_sha after.
    #
    #   :success  — a finished pipeline for the SHA concluded success
    #   :failure  — a finished pipeline for the SHA concluded non-success
    #   :pending  — a pipeline exists for the SHA but is still running
    #   :missing  — no pipeline ingested yet (caller should poll/wait)
    class CiGate
      RESULTS = %i[success failure pending missing].freeze

      def self.status_for(sha:, repository: nil)
        new(repository: repository).status_for(sha: sha)
      end

      def initialize(repository: nil)
        @repository = repository
      end

      def status_for(sha:)
        return :missing if sha.blank?

        scope = ::Devops::GitPipeline.by_sha(sha)
        scope = scope.where(git_repository_id: @repository.id) if @repository

        finished = scope.finished.order(created_at: :desc).first
        return finished.successful? ? :success : :failure if finished

        return :pending if scope.active.exists?

        # No pipeline ingested for this SHA yet. The land worker polls; a direct
        # Devops::Git::ApiClient lookup is a future fallback for the webhook race.
        :missing
      end
    end
  end
end
