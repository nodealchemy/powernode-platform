# frozen_string_literal: true

module Devops
  class ContainerImageBuildService
    class BuildError < StandardError; end

    def initialize(account:)
      @account = account
      @gitea_client = build_gitea_client
    end

    # Trigger a build for a container template.
    #
    # @param template [Devops::ContainerTemplate]
    # @param trigger_type [String] "push", "cascade", or "manual"
    # @param git_sha [String, nil]
    # @param triggered_by_build [Devops::ContainerImageBuild, nil] parent build for cascades
    # @return [Devops::ContainerImageBuild]
    def trigger_build(template:, trigger_type:, git_sha: nil, triggered_by_build: nil)
      raise BuildError, "Template has no Gitea repo linked" unless template.gitea_repo_full_name.present?

      build = Devops::ContainerImageBuild.create!(
        account: @account,
        container_template: template,
        trigger_type: trigger_type,
        status: "pending",
        git_sha: git_sha,
        triggered_by_build: triggered_by_build
      )

      # Trigger the Gitea Actions workflow
      owner, repo = template.gitea_repo_full_name.split("/", 2)
      result = @gitea_client.trigger_workflow(
        owner: owner,
        repo: repo,
        workflow: "build-push.yml",
        ref: "main",
        inputs: { build_id: build.id, git_sha: git_sha }.compact
      )

      build.update!(gitea_workflow_run_id: result[:id]&.to_s) if result[:id]
      build.start!

      Rails.logger.info "[ContainerImageBuild] Triggered #{trigger_type} build #{build.id} for #{template.name}"
      build
    rescue StandardError => e
      build&.fail!(build_log: e.message) if build&.persisted?
      Rails.logger.error "[ContainerImageBuild] Build trigger failed: #{e.message}"
      raise BuildError, "Build trigger failed: #{e.message}"
    end

    # Handle a completed build — update template and trigger cascades.
    #
    # @param template [Devops::ContainerTemplate]
    # @param image_tag [String] the new image tag (typically a git SHA)
    # @param git_sha [String]
    # @param build [Devops::ContainerImageBuild, nil]
    def handle_build_completed(template:, image_tag:, git_sha:, build: nil)
      template.update!(
        image_tag: image_tag,
        last_build_sha: git_sha,
        last_built_at: Time.current
      )

      build&.complete!(image_tag: image_tag)

      Rails.logger.info "[ContainerImageBuild] Build completed for #{template.name}: #{image_tag}"

      # Trigger cascade rebuilds if this is a base image with children
      trigger_cascade_rebuilds(parent_build: build, parent_template: template) if template.child_templates.any?
    end

    # Trigger rebuilds for all child templates of a base image.
    #
    # @param parent_build [Devops::ContainerImageBuild] the completed parent build
    # @param parent_template [Devops::ContainerTemplate]
    def trigger_cascade_rebuilds(parent_build:, parent_template:)
      parent_template.child_templates.active.with_gitea_repo.find_each do |child_template|
        next unless child_template.auto_update?

        trigger_build(
          template: child_template,
          trigger_type: "cascade",
          git_sha: parent_build&.git_sha,
          triggered_by_build: parent_build
        )
      rescue StandardError => e
        Rails.logger.warn "[ContainerImageBuild] Cascade build failed for #{child_template.name}: #{e.message}"
      end
    end

    private

    def build_gitea_client
      provider = Devops::GitProvider.where(provider_type: "gitea", is_active: true)
                                     .joins(:credentials)
                                     .first
      raise BuildError, "No active Gitea provider configured" unless provider

      Devops::Git::GiteaApiClient.new(provider.credentials.first)
    end
  end
end
