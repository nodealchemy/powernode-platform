# frozen_string_literal: true

module Devops
  module Docker
    class ImageManager
      def initialize(host:, user: nil)
        @host = host
        @user = user
        @client = ApiClient.new(host)
      end

      def pull_image(image:, tag: "latest", credential_id: nil)
        activity = create_activity("pull", params: { image: image, tag: tag })

        begin
          activity.start!

          auth_config = nil
          if credential_id.present?
            credential = @host.account.git_provider_credentials.find(credential_id)
            registry_service = RegistryService.new
            auth_config = registry_service.docker_auth_config(credential)
          end

          result = @client.image_pull(image, tag, auth_config: auth_config)
          activity.complete!(result.is_a?(Hash) ? result : {})

          sync_images
          result
        rescue ApiClient::ApiError => e
          activity.fail!(error: e.message)
          raise
        end
      end

      def remove_image(image, force: false)
        activity = create_activity("image_remove", image: image, params: { force: force })

        begin
          activity.start!
          result = @client.image_remove(image.docker_image_id, force: force)
          activity.complete!(result.is_a?(Hash) ? result : {})
          image.destroy!
          result
        rescue ApiClient::ApiError => e
          activity.fail!(error: e.message)
          raise
        end
      end

      def tag_image(image, repo:, tag:)
        activity = create_activity("image_tag", image: image, params: { repo: repo, tag: tag })

        begin
          activity.start!
          @client.image_tag(image.docker_image_id, repo, tag)
          activity.complete!({})

          refresh_image(image)
        rescue ApiClient::ApiError => e
          activity.fail!(error: e.message)
          raise
        end
      end

      private

      def create_activity(type, image: nil, params: {})
        @host.docker_activities.create!(
          activity_type: type,
          status: "pending",
          image: image,
          triggered_by: @user,
          trigger_source: "api",
          params: params
        )
      end

      def sync_images
        images = @client.image_list
        remote_ids = images.map { |i| i["Id"] }

        @host.docker_images.where.not(docker_image_id: remote_ids).destroy_all

        images.each do |di|
          img = @host.docker_images.find_or_initialize_by(docker_image_id: di["Id"])
          img.assign_attributes(
            repo_tags: di["RepoTags"] || [],
            repo_digests: di["RepoDigests"] || [],
            size_bytes: di["Size"],
            virtual_size: di["VirtualSize"],
            container_count: di["Containers"] || 0,
            labels: di["Labels"] || {},
            docker_created_at: di["Created"] ? Time.at(di["Created"]) : nil,
            last_seen_at: Time.current
          )
          img.save!
        end

        @host.update!(image_count: @host.docker_images.count)
      end

      def refresh_image(image)
        data = @client.image_inspect(image.docker_image_id)
        image.update!(
          repo_tags: data["RepoTags"] || image.repo_tags,
          repo_digests: data["RepoDigests"] || image.repo_digests,
          size_bytes: data["Size"] || image.size_bytes,
          architecture: data["Architecture"],
          os: data["Os"],
          last_seen_at: Time.current
        )
        image
      rescue ApiClient::NotFoundError
        image
      end
    end
  end
end
