# frozen_string_literal: true

module Ai
  module Deploy
    # What a deploy acts on. Either the platform itself (:platform_self — the highest-guard
    # case) or a registered project (:project, backed by a Devops::GitRepository). Carries
    # the environment and free-form config: an explicit method override ("method"), a
    # strategy ("strategy"), and method-specific keys (k8s cluster/deployment/namespace,
    # docker service/cluster, etc.). The Orchestrator and MethodRegistry read it; methods
    # consume the method-specific config.
    class Target
      PLATFORM_SELF = :platform_self
      PROJECT = :project
      KINDS = [PLATFORM_SELF, PROJECT].freeze

      attr_reader :kind, :repository, :environment, :config

      def initialize(kind:, repository: nil, environment: "production", config: {})
        @kind = kind.to_sym
        raise ArgumentError, "unknown deploy target kind #{kind}" unless KINDS.include?(@kind)

        @repository = repository
        @environment = (environment.presence || "production").to_s
        @config = (config || {}).deep_stringify_keys
      end

      def platform_self?
        kind == PLATFORM_SELF
      end

      def project?
        kind == PROJECT
      end

      def production?
        environment == "production"
      end

      # Explicit method override from config (e.g. "kubernetes"); nil → registry default.
      def method_key
        config["method"].presence&.to_sym
      end

      def strategy
        config["strategy"].presence&.to_sym
      end

      def label
        project? ? "project #{repository&.full_name || repository&.id}" : "platform-self"
      end

      def to_h
        { kind: kind, repository_id: repository&.id, environment: environment, config: config }
      end
    end
  end
end
