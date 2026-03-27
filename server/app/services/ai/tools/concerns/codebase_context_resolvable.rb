# frozen_string_literal: true

module Ai
  module Tools
    module Concerns
      module CodebaseContextResolvable
        extend ActiveSupport::Concern

        # Maximum number of files to index in a single run
        MAX_INDEX_FILES = 5000

        # Allowed base directories for filesystem access
        ALLOWED_ROOTS = %w[/home /opt /var /srv /tmp].freeze

        private

        # Resolve a git repository by UUID, name, or full_name.
        def resolve_repository(identifier)
          return nil if identifier.blank?

          scope = account.git_repositories
          scope.find_by(id: identifier) ||
            scope.find_by(name: identifier) ||
            scope.find_by(full_name: identifier) ||
            raise_not_found("repository", identifier)
        end

        # Find or create a knowledge base scoped to a repository.
        # Returns the KB associated with the repository, creating one if needed.
        def resolve_project_knowledge_base(repository: nil, base_path: nil)
          if repository
            kb = account.ai_knowledge_bases.find_by(git_repository_id: repository.id)
            return kb if kb

            account.ai_knowledge_bases.create!(
              name: "Codebase: #{repository.full_name || repository.name}",
              status: "active",
              embedding_model: "text-embedding-3-small",
              embedding_provider: "openai",
              chunking_strategy: "recursive",
              git_repository_id: repository.id
            )
          elsif base_path
            slug = File.basename(base_path)
            kb = account.ai_knowledge_bases.find_by(name: "Codebase: #{slug}")
            return kb if kb

            account.ai_knowledge_bases.create!(
              name: "Codebase: #{slug}",
              status: "active",
              embedding_model: "text-embedding-3-small",
              embedding_provider: "openai",
              chunking_strategy: "recursive",
              settings: { "base_path" => base_path }
            )
          else
            raise ArgumentError, "Either repository_id or base_path is required"
          end
        end

        # Resolve the filesystem base path for a project.
        # Accepts explicit base_path or resolves from repository metadata.
        def resolve_base_path(params)
          if params[:base_path].present?
            path = File.expand_path(params[:base_path])
            validate_path!(path)
            path
          elsif params[:repository_id].present?
            repo = resolve_repository(params[:repository_id])
            path = repo.metadata&.dig("local_path")
            raise ArgumentError, "Repository '#{repo.name}' has no local_path in metadata. Set it or provide base_path." unless path.present?
            validate_path!(path)
            path
          else
            raise ArgumentError, "Either repository_id or base_path is required"
          end
        end

        # Resolve both repository (optional) and knowledge base for a project.
        # Returns [repository_or_nil, knowledge_base]
        def resolve_project_context(params)
          repository = params[:repository_id].present? ? resolve_repository(params[:repository_id]) : nil
          base_path = resolve_base_path(params)
          kb = resolve_project_knowledge_base(repository: repository, base_path: base_path)
          [repository, kb, base_path]
        end

        # Validate that a filesystem path is safe to access.
        def validate_path!(path)
          expanded = File.expand_path(path)

          unless ALLOWED_ROOTS.any? { |root| expanded.start_with?(root) }
            raise ArgumentError, "Path '#{path}' is outside allowed directories"
          end

          unless File.directory?(expanded)
            raise ArgumentError, "Path '#{path}' is not a directory or does not exist"
          end
        end

        def raise_not_found(resource_type, identifier, message = nil)
          msg = message || "#{resource_type} not found: #{identifier}"
          raise ActiveRecord::RecordNotFound, msg
        end
      end
    end
  end
end
