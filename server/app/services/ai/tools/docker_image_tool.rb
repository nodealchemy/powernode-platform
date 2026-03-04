# frozen_string_literal: true

module Ai
  module Tools
    class DockerImageTool < BaseTool
      include Concerns::DockerContextResolvable

      REQUIRED_PERMISSION = "docker.images.read"

      def self.definition
        {
          name: "docker_image_management",
          description: "Manage Docker images: list, pull, remove, and tag",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            host_id: { type: "string", required: false, description: "Docker host ID, slug, or name" },
            image_id: { type: "string", required: false, description: "Image UUID or docker_image_id" },
            image: { type: "string", required: false, description: "Image name (for pull)" },
            tag: { type: "string", required: false, description: "Image tag (default: latest)" },
            repo: { type: "string", required: false, description: "Repository name (for tag)" },
            force: { type: "boolean", required: false, description: "Force removal" },
            credential_id: { type: "string", required: false, description: "Registry credential ID (for authenticated pulls)" }
          }
        }
      end

      def self.action_definitions
        {
          "docker_list_images" => {
            description: "List all Docker images on a host with tags, size, and creation time",
            parameters: {
              host_id: { type: "string", required: false, description: "Docker host ID, slug, or name (auto-selects if only one)" }
            }
          },
          "docker_pull_image" => {
            description: "Pull a Docker image from a registry to a host",
            parameters: {
              host_id: { type: "string", required: false, description: "Docker host ID, slug, or name" },
              image: { type: "string", required: true, description: "Image name (e.g. 'nginx', 'git.ipnode.org/powernode/backend')" },
              tag: { type: "string", required: false, description: "Image tag (default: latest)" },
              credential_id: { type: "string", required: false, description: "Registry credential ID for authenticated pulls" }
            }
          },
          "docker_remove_image" => {
            description: "Remove a Docker image from a host",
            parameters: {
              host_id: { type: "string", required: false, description: "Docker host ID, slug, or name" },
              image_id: { type: "string", required: true, description: "Image UUID or docker_image_id" },
              force: { type: "boolean", required: false, description: "Force removal even if in use" }
            }
          },
          "docker_tag_image" => {
            description: "Tag a Docker image with a new repository and tag",
            parameters: {
              host_id: { type: "string", required: false, description: "Docker host ID, slug, or name" },
              image_id: { type: "string", required: true, description: "Image UUID or docker_image_id" },
              repo: { type: "string", required: true, description: "New repository name" },
              tag: { type: "string", required: true, description: "New tag" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "docker_list_images" then list_images(params)
        when "docker_pull_image" then pull_image(params)
        when "docker_remove_image" then remove_image(params)
        when "docker_tag_image" then tag_image(params)
        else { success: false, error: "Unknown action: #{params[:action]}" }
        end
      rescue ActiveRecord::RecordNotFound => e
        { success: false, error: e.message }
      rescue ArgumentError => e
        { success: false, error: e.message }
      rescue Devops::Docker::ApiClient::ApiError => e
        { success: false, error: "Docker API error: #{e.message}" }
      end

      private

      def list_images(params)
        host = resolve_host(params[:host_id])
        images = host.docker_images.order(:repo_tags)

        {
          success: true,
          host: { id: host.id, name: host.name },
          images: images.map do |img|
            {
              id: img.id,
              docker_image_id: img.docker_image_id&.first(12),
              repo_tags: img.repo_tags,
              size_bytes: img.size_bytes,
              size_mb: img.size_bytes ? (img.size_bytes / 1_048_576.0).round(1) : nil,
              container_count: img.container_count,
              created_at: img.docker_created_at,
              last_seen_at: img.last_seen_at
            }
          end,
          count: images.size
        }
      end

      def pull_image(params)
        host = resolve_host(params[:host_id])
        manager = Devops::Docker::ImageManager.new(host: host, user: user)

        tag = params[:tag] || "latest"
        manager.pull_image(image: params[:image], tag: tag, credential_id: params[:credential_id])

        { success: true, image: "#{params[:image]}:#{tag}", message: "Image pulled successfully" }
      end

      def remove_image(params)
        host = resolve_host(params[:host_id])
        image = host.docker_images.find_by(id: params[:image_id]) ||
                host.docker_images.find_by(docker_image_id: params[:image_id]) ||
                raise_not_found("image", params[:image_id])

        manager = Devops::Docker::ImageManager.new(host: host, user: user)
        force = params[:force] == true
        image_tags = image.repo_tags

        manager.remove_image(image, force: force)
        { success: true, image: image_tags, message: "Image removed" }
      end

      def tag_image(params)
        host = resolve_host(params[:host_id])
        image = host.docker_images.find_by(id: params[:image_id]) ||
                host.docker_images.find_by(docker_image_id: params[:image_id]) ||
                raise_not_found("image", params[:image_id])

        manager = Devops::Docker::ImageManager.new(host: host, user: user)
        manager.tag_image(image, repo: params[:repo], tag: params[:tag])

        { success: true, image: image.repo_tags, new_tag: "#{params[:repo]}:#{params[:tag]}", message: "Image tagged" }
      end
    end
  end
end
