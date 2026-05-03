# frozen_string_literal: true

module Ai
  module Tools
    # MCP tool surface for Gitea Actions: action secrets management +
    # workflow_dispatch + run monitoring. Lets Claude Code (and other
    # MCP clients) drive a Gitea CI workflow end-to-end without leaving
    # the chat — set the secrets a workflow needs, dispatch it, watch
    # the run, fetch logs.
    #
    # Action vocabulary:
    #   set_gitea_action_secret      — create or update a per-repo secret
    #   list_gitea_action_secrets    — list secret names (values not returned)
    #   delete_gitea_action_secret   — delete a secret
    #   dispatch_gitea_workflow      — trigger workflow_dispatch with inputs
    #   list_gitea_workflow_runs     — list recent runs for a workflow file
    #   get_gitea_workflow_run       — fetch a specific run's status + jobs
    #
    # All actions require the operator's account to have an active Gitea
    # credential configured (Settings → Integrations → Gitea). Same
    # discovery + auth pattern as RepoManagementTool.
    #
    # Reference plan:
    #   docs/plans/wondrous-yawning-anchor.md (Phase 2 — operator-driven CI)
    class GiteaActionsTool < BaseTool
      REQUIRED_PERMISSION = "ai.workflows.update"

      ACTIONS = %w[
        set_gitea_action_secret
        list_gitea_action_secrets
        delete_gitea_action_secret
        dispatch_gitea_workflow
        list_gitea_workflow_runs
        get_gitea_workflow_run
      ].freeze

      def self.definition
        {
          name: "gitea_actions",
          description: "Gitea Actions secrets management + workflow_dispatch + run monitoring",
          parameters: {
            action: { type: "string", required: true, description: "One of: #{ACTIONS.join(', ')}" },
            owner:  { type: "string", required: true,  description: "Repository owner (username or organization)" },
            repo:   { type: "string", required: true,  description: "Repository name" },
            # set_gitea_action_secret + delete_gitea_action_secret
            secret_name:  { type: "string", required: false, description: "Secret key (e.g. POWERNODE_DISK_IMAGE_WEBHOOK_SECRET)" },
            secret_value: { type: "string", required: false, description: "Secret plaintext (set actions only — not returned by list)" },
            # dispatch_gitea_workflow
            workflow_file: { type: "string", required: false, description: "Workflow filename (e.g. 'build-disk-image.yaml')" },
            ref:           { type: "string", required: false, description: "Branch/tag ref to run against (e.g. 'master', 'refs/tags/v1.0.0')" },
            inputs:        { type: "object", required: false, description: "Workflow_dispatch inputs as a hash" },
            # get_gitea_workflow_run / list_gitea_workflow_runs
            run_id: { type: "string", required: false, description: "Workflow run ID (for get/cancel actions)" },
            limit:  { type: "integer", required: false, description: "Max results for list actions (default 20)" }
          }
        }
      end

      def self.action_definitions
        {
          "set_gitea_action_secret" => {
            description: "Create or update a per-repo Actions secret. Plaintext value never echoed back; subsequent list_gitea_action_secrets returns names only.",
            parameters: {
              owner:        { type: "string",  required: true },
              repo:         { type: "string",  required: true },
              secret_name:  { type: "string",  required: true, description: "Secret key (e.g. POWERNODE_DISK_IMAGE_WEBHOOK_SECRET)" },
              secret_value: { type: "string",  required: true, description: "Secret plaintext to store" }
            }
          },
          "list_gitea_action_secrets" => {
            description: "List secret names for a repo (values not returned by Gitea API)",
            parameters: {
              owner: { type: "string", required: true },
              repo:  { type: "string", required: true }
            }
          },
          "delete_gitea_action_secret" => {
            description: "Delete a per-repo Actions secret",
            parameters: {
              owner:       { type: "string", required: true },
              repo:        { type: "string", required: true },
              secret_name: { type: "string", required: true }
            }
          },
          "dispatch_gitea_workflow" => {
            description: "Trigger a workflow_dispatch event for a Gitea Actions workflow",
            parameters: {
              owner:         { type: "string", required: true },
              repo:          { type: "string", required: true },
              workflow_file: { type: "string", required: true, description: "Workflow filename (e.g. 'build-disk-image.yaml')" },
              ref:           { type: "string", required: true, description: "Branch/tag ref (e.g. 'master')" },
              inputs:        { type: "object", required: false, description: "Workflow input values as a hash" }
            }
          },
          "list_gitea_workflow_runs" => {
            description: "List recent workflow runs for a repo (optionally filtered by workflow_file)",
            parameters: {
              owner:         { type: "string", required: true },
              repo:          { type: "string", required: true },
              workflow_file: { type: "string", required: false, description: "Filter to a specific workflow filename" },
              limit:         { type: "integer", required: false, description: "Max results (default 20)" }
            }
          },
          "get_gitea_workflow_run" => {
            description: "Get a specific workflow run including its jobs",
            parameters: {
              owner:  { type: "string", required: true },
              repo:   { type: "string", required: true },
              run_id: { type: "string", required: true }
            }
          }
        }
      end

      protected

      def call(params)
        credential = find_gitea_credential
        return { success: false, error: "No active Gitea credential found for this account" } unless credential

        client = Devops::Git::ApiClient.for(credential)
        unless client.is_a?(::Devops::Git::GiteaApiClient)
          return { success: false, error: "Gitea action tool requires a Gitea-typed credential (got #{client.class.name.demodulize})" }
        end

        case params[:action].to_s
        when "set_gitea_action_secret"     then set_secret(client, params)
        when "list_gitea_action_secrets"   then list_secrets(client, params)
        when "delete_gitea_action_secret"  then delete_secret(client, params)
        when "dispatch_gitea_workflow"     then dispatch_workflow(client, params)
        when "list_gitea_workflow_runs"    then list_runs(client, params)
        when "get_gitea_workflow_run"      then get_run(client, params)
        else
          { success: false, error: "Unknown action: #{params[:action].inspect} (supported: #{ACTIONS.join(', ')})" }
        end
      end

      private

      def set_secret(client, params)
        owner, repo = require_owner_repo(params)
        return owner if owner.is_a?(Hash) # error tuple

        result = client.create_or_update_action_secret(owner, repo, params[:secret_name].to_s, params[:secret_value].to_s)
        return { success: false, error: result[:error] || "set failed" } unless result[:success]

        { success: true, owner: owner, repo: repo, secret_name: params[:secret_name].to_s, message: "Secret stored. Plaintext is not retrievable; rotate to replace." }
      end

      def list_secrets(client, params)
        owner, repo = require_owner_repo(params)
        return owner if owner.is_a?(Hash)

        secrets = client.list_action_secrets(owner, repo)
        { success: true, owner: owner, repo: repo, count: secrets.length, secrets: secrets }
      end

      def delete_secret(client, params)
        owner, repo = require_owner_repo(params)
        return owner if owner.is_a?(Hash)

        result = client.delete_action_secret(owner, repo, params[:secret_name].to_s)
        return { success: false, error: result[:error] || "delete failed" } unless result[:success]

        { success: true, owner: owner, repo: repo, secret_name: params[:secret_name].to_s, message: "Secret deleted" }
      end

      def dispatch_workflow(client, params)
        owner, repo = require_owner_repo(params)
        return owner if owner.is_a?(Hash)

        workflow_file = params[:workflow_file].to_s
        ref           = params[:ref].to_s
        inputs        = params[:inputs] || {}
        return { success: false, error: "workflow_file required" } if workflow_file.blank?
        return { success: false, error: "ref required" } if ref.blank?

        result = client.trigger_workflow(owner, repo, workflow_file, ref, inputs)
        return { success: false, error: result[:error] || "dispatch failed" } unless result[:success]

        { success: true, owner: owner, repo: repo, workflow_file: workflow_file, ref: ref,
          message: "Workflow dispatched. Use list_gitea_workflow_runs to track the run." }
      end

      def list_runs(client, params)
        owner, repo = require_owner_repo(params)
        return owner if owner.is_a?(Hash)

        opts = {}
        opts[:workflow_file] = params[:workflow_file] if params[:workflow_file].present?
        opts[:limit]         = (params[:limit] || 20).to_i

        runs = client.list_workflow_runs(owner, repo, opts)
        { success: true, owner: owner, repo: repo, count: runs.length, runs: runs }
      end

      def get_run(client, params)
        owner, repo = require_owner_repo(params)
        return owner if owner.is_a?(Hash)

        run_id = params[:run_id].to_s
        return { success: false, error: "run_id required" } if run_id.blank?

        run  = client.get_workflow_run(owner, repo, run_id)
        jobs = client.get_workflow_run_jobs(owner, repo, run_id) rescue []

        { success: true, owner: owner, repo: repo, run: run, jobs: jobs }
      end

      def require_owner_repo(params)
        owner = params[:owner].to_s
        repo  = params[:repo].to_s
        return { success: false, error: "owner required" } if owner.blank?
        return { success: false, error: "repo required" } if repo.blank?

        [owner, repo]
      end

      def find_gitea_credential
        gitea_provider = ::Devops::GitProvider.find_by(provider_type: "gitea")
        return nil unless gitea_provider

        account.git_provider_credentials
               .where(git_provider_id: gitea_provider.id, is_active: true)
               .order(is_default: :desc, created_at: :desc)
               .first
      end
    end
  end
end
