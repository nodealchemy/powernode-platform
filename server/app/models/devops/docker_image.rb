# frozen_string_literal: true

module Devops
  class DockerImage < ApplicationRecord
    self.table_name = "devops_docker_images"

    include Auditable

    belongs_to :docker_host, class_name: "Devops::DockerHost"
    has_many :docker_activities, class_name: "Devops::DockerActivity", foreign_key: "image_id", dependent: :nullify

    validates :docker_image_id, presence: true
    validates :docker_image_id, uniqueness: { scope: :docker_host_id }

    scope :recent, -> { order(created_at: :desc) }
    scope :dangling, -> { where("repo_tags = '[]'::jsonb OR repo_tags = '[\"\"]'::jsonb") }
    scope :tagged, -> { where.not("repo_tags = '[]'::jsonb OR repo_tags = '[\"\"]'::jsonb") }

    def primary_tag
      tags = repo_tags || []
      tags.reject { |t| t.blank? || t == "<none>:<none>" }.first || "<none>"
    end

    def size_mb
      return nil unless size_bytes

      (size_bytes / 1_048_576.0).round(1)
    end

    def dangling?
      tags = repo_tags || []
      tags.empty? || tags.all? { |t| t.blank? || t == "<none>:<none>" }
    end

    def image_summary
      {
        id: id,
        docker_image_id: docker_image_id,
        primary_tag: primary_tag,
        repo_tags: repo_tags,
        size_bytes: size_bytes,
        size_mb: size_mb,
        container_count: container_count,
        docker_created_at: docker_created_at,
        created_at: created_at
      }
    end

    def image_details
      image_summary.merge(
        repo_digests: repo_digests,
        virtual_size: virtual_size,
        architecture: architecture,
        os: os,
        labels: labels,
        last_seen_at: last_seen_at,
        docker_host_id: docker_host_id,
        updated_at: updated_at
      )
    end
  end
end
