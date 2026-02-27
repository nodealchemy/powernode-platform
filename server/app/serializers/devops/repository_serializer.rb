# frozen_string_literal: true

module Devops
  class RepositorySerializer
    def initialize(repository, options = {})
      @repository = repository
      @options = options
    end

    def as_json
      result = {
        id: @repository.id,
        name: @repository.name,
        full_name: @repository.full_name,
        default_branch: @repository.default_branch,
        external_id: @repository.external_id,
        is_active: @repository.is_active,
        origin: @repository.origin,
        last_synced_at: @repository.last_synced_at,
        owner: @repository.owner,
        provider_type: @repository.provider_type,
        pipeline_count: @repository.devops_pipelines.count,
        created_at: @repository.created_at,
        updated_at: @repository.updated_at
      }

      if @repository.origin == "devops"
        result[:settings] = @repository.metadata || {}
        result[:clone_url] = @repository.clone_url_for_devops
        result[:web_url] = @repository.web_url_for_devops
        result[:repo_name] = @repository.full_name&.split("/")&.last
      else
        result[:settings] = {}
        result[:clone_url] = @repository.clone_url
        result[:web_url] = @repository.web_url
        result[:repo_name] = @repository.name
      end

      result
    end

    def serializable_hash
      { data: { attributes: as_json } }
    end

    def self.serialize(repository, options = {})
      new(repository, options).as_json
    end

    def self.serialize_collection(repositories, options = {})
      repositories.map { |repository| serialize(repository, options) }
    end
  end
end
