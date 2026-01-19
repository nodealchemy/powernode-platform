# frozen_string_literal: true

module CiCd
  class PipelineRepositorySerializer
    def initialize(pipeline_repository, options = {})
      @pipeline_repository = pipeline_repository
      @options = options
    end

    def as_json
      {
        id: @pipeline_repository.id,
        overrides: @pipeline_repository.overrides,
        pipeline_name: @pipeline_repository.pipeline.name,
        pipeline_slug: @pipeline_repository.pipeline.slug,
        repository_name: @pipeline_repository.repository.name,
        repository_full_name: @pipeline_repository.repository.full_name,
        created_at: @pipeline_repository.created_at,
        updated_at: @pipeline_repository.updated_at
      }
    end

    def serializable_hash
      { data: { attributes: as_json } }
    end

    def self.serialize(pipeline_repository, options = {})
      new(pipeline_repository, options).as_json
    end

    def self.serialize_collection(pipeline_repositories, options = {})
      pipeline_repositories.map { |pr| serialize(pr, options) }
    end
  end
end
