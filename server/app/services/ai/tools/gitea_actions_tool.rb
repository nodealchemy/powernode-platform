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
        set_gitea_action_secrets_bulk
        list_gitea_action_secrets
        delete_gitea_action_secret
        dispatch_gitea_workflow
        list_gitea_workflows
        list_gitea_workflow_runs
        get_gitea_workflow_run
        get_gitea_job_logs
        cancel_gitea_workflow_run
        rerun_gitea_workflow
        create_gitea_user_token
        list_gitea_user_tokens
        delete_gitea_user_token
      ].freeze

      def self.definition
        {
          name: "gitea_actions",
          description: "Gitea Actions secrets management + workflow_dispatch + run monitoring",
          parameters: {
            action: { type: "string", required: true, description: "One of: #{ACTIONS.join(', ')}" },
            # owner/repo are required for repo-scoped actions but NOT for the
            # 3 user-scoped PAT actions (create/list/delete_gitea_user_token).
            # Action-level guards (require_owner_repo) enforce them where needed.
            owner:  { type: "string", required: false, description: "Repository owner (required for repo-scoped actions)" },
            repo:   { type: "string", required: false, description: "Repository name (required for repo-scoped actions)" },
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
          },
          "set_gitea_action_secrets_bulk" => {
            description: "Set multiple per-repo Actions secrets in one call (efficiency wrapper). Replaces existing values; missing keys are unchanged.",
            parameters: {
              owner:   { type: "string", required: true },
              repo:    { type: "string", required: true },
              secrets: { type: "object", required: true, description: "Hash of {SECRET_NAME: 'plaintext value', ...}. Names beginning with GITEA_ or GITHUB_ are reserved by Gitea — use a different prefix (e.g. PLATFORM_READ_TOKEN)." }
            }
          },
          "list_gitea_workflows" => {
            description: "List all workflows defined in a repo (returns name + state for each .gitea/workflows/*.yaml file)",
            parameters: {
              owner: { type: "string", required: true },
              repo:  { type: "string", required: true }
            }
          },
          "get_gitea_job_logs" => {
            description: "Fetch the raw log text for a workflow job. Useful for diagnosing failed runs without leaving the chat.",
            parameters: {
              owner:  { type: "string", required: true },
              repo:   { type: "string", required: true },
              job_id: { type: "string", required: true, description: "Job ID from get_gitea_workflow_run.jobs[].id" },
              tail:   { type: "integer", required: false, description: "Return only the last N lines (default: full log)" },
              grep:   { type: "string", required: false, description: "Filter to lines matching this regex (case-insensitive)" }
            }
          },
          "cancel_gitea_workflow_run" => {
            description: "Cancel a queued or in-progress workflow run",
            parameters: {
              owner:  { type: "string", required: true },
              repo:   { type: "string", required: true },
              run_id: { type: "string", required: true }
            }
          },
          "rerun_gitea_workflow" => {
            description: "Re-run a completed workflow run (useful for retrying transient failures)",
            parameters: {
              owner:  { type: "string", required: true },
              repo:   { type: "string", required: true },
              run_id: { type: "string", required: true }
            }
          },
          "create_gitea_user_token" => {
            description: "Create a personal access token for the authenticated Gitea user. Returns plaintext EXACTLY ONCE — caller must capture. Use to mint scoped read tokens for CI workflows without leaving the chat.",
            parameters: {
              token_name:        { type: "string",  required: true,  description: "Human-readable name for the token (e.g. 'platform-ci-readonly')" },
              scopes:            { type: "array",   required: false, description: "Gitea scope strings (default: ['read:repository']). Common: read:repository, write:repository, read:user, write:user, write:package" },
              set_as_secret:     { type: "object",  required: false, description: "Optional: immediately set the new token as a Gitea Actions secret. Hash: {owner, repo, secret_name}. Combines mint + paste in one call." }
            }
          },
          "list_gitea_user_tokens" => {
            description: "List the authenticated user's personal access tokens (names + scopes only — plaintext is never returned by Gitea after creation)",
            parameters: {}
          },
          "delete_gitea_user_token" => {
            description: "Delete a personal access token by name or numeric ID. Used for rotation or cleanup.",
            parameters: {
              name_or_id: { type: "string", required: true, description: "Token name or numeric ID (from list_gitea_user_tokens)" }
            }
          }
        }
      end

      protected

      def call(params)
        credential = find_gitea_credential
        return { success: false, error: "No active Gitea credential found for this account" } unless credential

        client = Devops::Git::ApiClient.for(credential)
        # Trust ApiClient.for to return the right class — it's a factory
        # that branches on credential.provider.provider_type. A defensive
        # is_a? check here only triggers if .for has a bug, which is the
        # wrong place to catch it. (Also incompatible with RSpec instance
        # doubles which don't fake is_a? to the doubled class.)

        case params[:action].to_s
        when "set_gitea_action_secret"        then set_secret(client, params)
        when "set_gitea_action_secrets_bulk"  then set_secrets_bulk(client, params)
        when "list_gitea_action_secrets"      then list_secrets(client, params)
        when "delete_gitea_action_secret"     then delete_secret(client, params)
        when "dispatch_gitea_workflow"        then dispatch_workflow(client, params)
        when "list_gitea_workflows"           then list_workflows(client, params)
        when "list_gitea_workflow_runs"       then list_runs(client, params)
        when "get_gitea_workflow_run"         then get_run(client, params)
        when "get_gitea_job_logs"             then get_job_logs(client, params)
        when "cancel_gitea_workflow_run"      then cancel_run(client, params)
        when "rerun_gitea_workflow"           then rerun_run(client, params)
        when "create_gitea_user_token"        then create_user_token(client, params)
        when "list_gitea_user_tokens"         then list_user_tokens(client)
        when "delete_gitea_user_token"        then delete_user_token(client, params)
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

      def set_secrets_bulk(client, params)
        owner, repo = require_owner_repo(params)
        return owner if owner.is_a?(Hash)

        secrets = params[:secrets]
        return { success: false, error: "secrets hash required" } unless secrets.is_a?(Hash) && secrets.any?

        results = secrets.map do |name, value|
          name = name.to_s
          result = client.create_or_update_action_secret(owner, repo, name, value.to_s)
          { secret_name: name, success: !!result[:success], error: result[:error] }
        end

        failures = results.reject { |r| r[:success] }
        {
          success: failures.empty?,
          owner: owner, repo: repo,
          set_count: results.length - failures.length,
          failed_count: failures.length,
          results: results,
          message: failures.empty? ? "All secrets stored." : "Some secrets failed — check :results."
        }
      end

      def list_workflows(client, params)
        owner, repo = require_owner_repo(params)
        return owner if owner.is_a?(Hash)

        workflows = client.list_workflows(owner, repo)
        normalized = Array(workflows).map do |w|
          if w.is_a?(Hash)
            { name: w["name"] || w["filename"], path: w["path"] || w["filename"], state: w["state"] }.compact
          else
            { name: w.to_s }
          end
        end
        { success: true, owner: owner, repo: repo, count: normalized.length, workflows: normalized }
      end

      def get_job_logs(client, params)
        owner, repo = require_owner_repo(params)
        return owner if owner.is_a?(Hash)

        job_id = params[:job_id].to_s
        return { success: false, error: "job_id required" } if job_id.blank?

        logs = client.get_job_logs(owner, repo, job_id)
        return { success: false, error: "no logs returned for job #{job_id}" } unless logs.is_a?(String)

        # Server-side filter to keep responses small. tail and grep can be combined.
        if (regex = params[:grep]).present?
          re = ::Regexp.new(regex.to_s, ::Regexp::IGNORECASE)
          logs = logs.lines.select { |l| l.match?(re) }.join
        end
        if (tail_n = params[:tail]).present? && tail_n.to_i.positive?
          logs = logs.lines.last(tail_n.to_i).join
        end

        { success: true, owner: owner, repo: repo, job_id: job_id, log_size_bytes: logs.bytesize, logs: logs }
      end

      def cancel_run(client, params)
        owner, repo = require_owner_repo(params)
        return owner if owner.is_a?(Hash)

        run_id = params[:run_id].to_s
        return { success: false, error: "run_id required" } if run_id.blank?

        result = client.cancel_workflow_run(owner, repo, run_id)
        return { success: false, error: result[:error] || "cancel failed" } unless result[:success]

        { success: true, owner: owner, repo: repo, run_id: run_id, message: "Workflow run cancelled" }
      end

      def rerun_run(client, params)
        owner, repo = require_owner_repo(params)
        return owner if owner.is_a?(Hash)

        run_id = params[:run_id].to_s
        return { success: false, error: "run_id required" } if run_id.blank?

        result = client.rerun_workflow(owner, repo, run_id)
        return { success: false, error: result[:error] || "rerun failed" } unless result[:success]

        { success: true, owner: owner, repo: repo, run_id: run_id, message: "Workflow run re-queued" }
      end

      # Mint a Gitea PAT for the authenticated user. Optionally pipe it
      # straight into a repo's Actions secret in a single call — collapses
      # 3 manual web UI steps (generate token → copy → paste into secret)
      # into one MCP invocation.
      def create_user_token(client, params)
        token_name = params[:token_name].to_s
        return { success: false, error: "token_name required" } if token_name.blank?

        scopes = Array(params[:scopes]).map(&:to_s)
        scopes = %w[read:repository] if scopes.empty?

        result = client.create_user_token(token_name, scopes: scopes)
        return { success: false, error: result[:error] || "create failed" } unless result[:success]

        response = {
          success:    true,
          token_id:   result[:token_id],
          token_name: result[:name],
          scopes:     result[:scopes],
          plaintext:  result[:token],
          note:       "Plaintext token shown ONCE. Save it now — Gitea cannot retrieve it again."
        }

        # Optional: pipe straight into a repo's Actions secret.
        sas = params[:set_as_secret]
        if sas.is_a?(Hash) && sas[:owner].present? && sas[:repo].present? && sas[:secret_name].present?
          # NOTE: Gitea reserves GITEA_* and GITHUB_* secret names.
          # Caller must pick a non-reserved name (e.g. PLATFORM_READ_TOKEN).
          set_result = client.create_or_update_action_secret(
            sas[:owner].to_s, sas[:repo].to_s, sas[:secret_name].to_s, result[:token]
          )
          response[:set_as_secret] = if set_result[:success]
                                       { ok: true, owner: sas[:owner], repo: sas[:repo], secret_name: sas[:secret_name] }
                                     else
                                       { ok: false, error: set_result[:error] }
                                     end
        end

        response
      end

      def list_user_tokens(client)
        tokens = client.list_user_tokens
        { success: true, count: tokens.length, tokens: tokens }
      end

      def delete_user_token(client, params)
        name_or_id = params[:name_or_id].to_s
        return { success: false, error: "name_or_id required" } if name_or_id.blank?

        result = client.delete_user_token(name_or_id)
        return { success: false, error: result[:error] || "delete failed" } unless result[:success]

        { success: true, name_or_id: name_or_id, message: "User token deleted" }
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
