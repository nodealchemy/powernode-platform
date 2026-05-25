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

    # Resolve or create knowledge base
    repository = nil
    if params[:repository_id].present?
      repository = account.git_repositories.find_by(id: params[:repository_id])
    end

    kb = if repository
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
end
