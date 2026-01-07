# frozen_string_literal: true

module CiCd
  class RepositorySerializer
    def initialize(repository, options = {})
      @repository = repository
      @options = options
    end

    def as_json
      {
        id: @repository.id,
        name: @repository.name,
        full_name: @repository.full_name,
        default_branch: @repository.default_branch,
        external_id: @repository.external_id,
        settings: @repository.settings,
        is_active: @repository.is_active,
        last_synced_at: @repository.last_synced_at,
        clone_url: @repository.clone_url,
        web_url: @repository.web_url,
        owner: @repository.owner,
        repo_name: @repository.repo_name,
        provider_type: @repository.provider.provider_type,
        pipeline_count: @repository.pipelines.count,
        created_at: @repository.created_at,
        updated_at: @repository.updated_at
      }
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
