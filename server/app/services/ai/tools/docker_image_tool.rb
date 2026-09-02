# frozen_string_literal: true

module Ai
  module Tools
    class DockerImageTool < BaseTool
      include Concerns::DockerContextResolvable

      # SECURITY (IMP-48abfa2f9e74): this floor used to be "docker.images.read", a
      # name that appears ZERO times in config/permissions.rb. User#has_permission?
      # is an exact match on a role_permissions row plus a system.admin
      # short-circuit, so no row can ever exist for an undeclared name: every action
      # on this class was super-admin-only while tools/list advertised the whole
      # surface to everyone. b7598df74 created the devops.* family and moved the
      # REST twin onto it (Api::V1::Devops::Docker::ImagesController); this class was
      # missed by that sweep. Retargeted onto the same declared family, at the same
      # read/manage split the twin uses action for action.
      REQUIRED_PERMISSION = "devops.docker.read"

      # The floor retarget ALONE would be an escalation: pointing it at a read
      # permission newly grants every read holder the write/exec actions sitting
      # behind it. ACTION_PERMISSIONS raises each of those to the manage tier,
      # enforced against the action that RUNS — never against the invoked name,
      # since a user principal is not pinned to it
      # (McpPlatformToolRegistrar#action_pinned_to_name?) and can supply a sibling
      # :action. Actions ABSENT from this map sit at the floor deliberately:
      #
      #   docker_list_images is a plain DB read; the twin gates index/show on
      #     devops.docker.read. pull / delete / tag all mutate the daemon's
      #     image store, and the twin gates pull, destroy and tag on
      #     devops.docker.manage.
      ACTION_PERMISSIONS = {
        "docker_pull_image" => "devops.docker.manage",
        "docker_delete_image" => "devops.docker.manage",
        "docker_tag_image" => "devops.docker.manage"
      }.freeze

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "docker_delete_image", mutating: true
      declare_action "docker_list_images", mutating: false
      declare_action "docker_pull_image", mutating: true
      declare_action "docker_tag_image", mutating: true

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
              image: { type: "string", required: true, description: "Image name (e.g. 'nginx', 'registry.example.com/myorg/myimage')" },
              tag: { type: "string", required: false, description: "Image tag (default: latest)" },
              credential_id: { type: "string", required: false, description: "Registry credential ID for authenticated pulls" }
            }
          },
          "docker_delete_image" => {
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
        action = params[:action].to_s

        unless action_permitted?(action)
          Rails.logger.warn(
            "[DockerImageTool] Refused action for insufficient permission: " \
            "action=#{action} requires=#{required_perm_for(action)} user=#{user&.id}"
          )
          return error_result("permission denied: #{required_perm_for(action)} required")
        end

        case params[:action]
        when "docker_list_images" then list_images(params)
        when "docker_pull_image" then pull_image(params)
        when "docker_delete_image" then remove_image(params)
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

      # Falls back to the class floor for the read actions, which the registrar has
      # already enforced by the time this runs.
      def required_perm_for(action)
        ACTION_PERMISSIONS[action] || REQUIRED_PERMISSION
      end

      # Two explicit bypasses, matching the sibling tools' ladder (MemoryTool,
      # AgentAutonomyTool, SharedKnowledgeTool): in-process callers that opted in
      # with `internal: true`, and an mTLS node principal whose specific tool name
      # already cleared Mcp::Principal#may_invoke? and whose action the registrar
      # pinned to that same name. Never inferred from a nil user.
      def action_permitted?(action)
        return true if internal?
        return true if instance_authorized?
        return false unless user.respond_to?(:has_permission?)

        # Compared against true rather than used for truthiness: nothing on the MCP
        # path coerces a permission answer, and a truthy non-boolean must not read
        # as a grant.
        user.has_permission?(required_perm_for(action)) == true
      end

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
