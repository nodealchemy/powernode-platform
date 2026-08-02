# frozen_string_literal: true

class Api::V1::Internal::CodebaseController < Api::V1::Internal::InternalBaseController
  # POST /api/v1/internal/codebase/index
  # Triggers codebase indexing for a given path and account.
  def index_codebase
    account = Account.find(params[:account_id])
    base_path = params[:base_path]
    incremental = params.fetch(:incremental, true)

    unless base_path.present? && File.directory?(base_path)
      render_error("Invalid base_path: #{base_path}", status: :unprocessable_content)
      return
    end

    repository, repo_error = resolve_indexing_repository(account)
    if repo_error
      render_error(repo_error, status: :unprocessable_content)
      return
    end

    kb = resolve_knowledge_base(account, base_path, repository)

    service = Ai::Codebase::IndexingService.new(
      account: account,
      knowledge_base: kb,
      base_path: base_path
    )

    result = service.index(path: params[:path], incremental: incremental)

    if result[:success]
      render_success(result)
    else
      render_error(result[:error], status: :unprocessable_content)
    end
  rescue ActiveRecord::RecordNotFound => e
    render_error(e.message, status: :not_found)
  rescue => e
    Rails.logger.error "[CodebaseController] Indexing error: #{e.message}"
    render_error(e.message, status: :internal_server_error)
  end

  # POST /api/v1/internal/codebase/analyze
  # Runs a long-running codebase analysis (prune_stale) driven by
  # AiCodeAnalysisJob. Writes the result to the account's "default"
  # shared-memory pool under result_key (when given) and returns it.
  def analyze
    account = Account.find(params[:account_id])
    base_path = params[:base_path]
    operation = params[:operation].to_s

    unless base_path.present? && File.directory?(base_path)
      render_error("Invalid base_path: #{base_path}", status: :unprocessable_content)
      return
    end

    opts = analysis_options
    repository, repo_error = resolve_indexing_repository(account)
    if repo_error
      render_error(repo_error, status: :unprocessable_content)
      return
    end

    kb = resolve_knowledge_base(account, base_path, repository)

    result =
      case operation
      when "prune_stale"
        Ai::Codebase::StalePruneService
          .new(account: account, knowledge_base: kb, base_path: base_path)
          .prune(dry_run: opts.fetch("dry_run", true))
      when "dead_code"
        Ai::Codebase::DeadCodeAnalysisService
          .new(account: account, base_path: base_path)
          .detect(
            languages: opts["languages"].presence || %w[typescript ruby],
            triage: opts.fetch("triage", true),
            model: opts["model"]
          )
      when "find_duplicates"
        Ai::Codebase::DuplicateAnalysisService
          .new(account: account, base_path: base_path)
          .detect(
            scope_paths: opts["scope_paths"],
            min_tokens: (opts["min_tokens"] || 50).to_i,
            triage: opts.fetch("triage", true),
            model: opts["model"]
          )
      else
        render_error("Unknown operation: #{operation.presence || '(blank)'}", status: :unprocessable_content)
        return
      end

    store_result(account, params[:result_key], result) if params[:result_key].present?

    render_success(result.merge(result_key: params[:result_key]))
  rescue ActiveRecord::RecordNotFound => e
    render_error(e.message, status: :not_found)
  rescue => e
    Rails.logger.error "[CodebaseController] Analyze error (#{params[:operation]}): #{e.message}"
    render_error(e.message, status: :internal_server_error)
  end

  private

  # Normalize the nested :options param into a string-keyed hash.
  def analysis_options
    raw = params[:options]
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    (raw || {}).with_indifferent_access
  end

  # Resolve (or create) the codebase knowledge base for this account, keyed by
  # git repository when provided, else by base_path basename. Shared by
  # index_codebase and analyze so both target the same KB.
  # Resolve an explicitly-supplied repository_id by id, name OR full_name —
  # the same three-way lookup CodebaseContextResolvable#resolve_repository uses
  # on the READ side. Keeping only find_by(id:) here is what made indexing and
  # searching key their knowledge bases differently: a caller passing
  # "powernode/powernode-platform" resolved to nil, fell through to the
  # base_path branch, and wrote thousands of nodes into "Codebase: <basename>"
  # that no repository-scoped search could ever reach — silently.
  #
  # Returns [repository_or_nil, error_or_nil]. A blank repository_id is fine
  # (base_path keying is a legitimate mode). A PRESENT but unresolvable one is
  # an error: indexing somewhere other than where the caller asked is worse
  # than refusing.
  def resolve_indexing_repository(account)
    raw = params[:repository_id]
    return [ nil, nil ] if raw.blank?

    scope = account.git_repositories
    repository = scope.find_by(id: raw) || scope.find_by(name: raw) || scope.find_by(full_name: raw)
    return [ nil, "repository not found: #{raw}" ] if repository.nil?

    [ repository, nil ]
  end

  def resolve_knowledge_base(account, base_path, repository = nil)
    if repository
      account.ai_knowledge_bases.find_or_create_by!(git_repository_id: repository.id) do |k|
        k.name = "Codebase: #{repository.full_name || repository.name}"
        k.status = "active"
        k.embedding_model = "text-embedding-3-small"
        k.embedding_provider = "openai"
        k.chunking_strategy = "recursive"
      end
    else
      slug = File.basename(base_path)
      account.ai_knowledge_bases.find_or_create_by!(name: "Codebase: #{slug}") do |k|
        k.status = "active"
        k.embedding_model = "text-embedding-3-small"
        k.embedding_provider = "openai"
        k.chunking_strategy = "recursive"
        k.settings = { "base_path" => base_path }
      end
    end
  end

  # Persist an analysis result to the account's "default" shared-memory pool.
  # Non-fatal: a storage hiccup must not fail the analysis itself.
  def store_result(account, key, result)
    pool = account.ai_memory_pools.find_by(pool_id: "default")
    unless pool
      Rails.logger.warn "[CodebaseController] No 'default' memory pool for account #{account.id}; result #{key} not stored"
      return
    end
    pool.write_data(key, result, agent_id: nil)
  rescue => e
    Rails.logger.warn "[CodebaseController] Could not store analysis result under #{key}: #{e.message}"
  end
end
