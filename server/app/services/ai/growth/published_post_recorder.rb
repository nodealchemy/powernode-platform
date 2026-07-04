# frozen_string_literal: true

module Ai
  module Growth
    # Captures provenance for a successful write dispatch against an endpoint
    # that opts in via metadata["captures_published_post"] (mirrors the
    # existing metadata["side_effecting"] opt-in the write-endpoint gate
    # already reads — see Ai::DataSources::TemplateLibrary#x_com_template's
    # "Create post" endpoint). Called from
    # Ai::Tools::DataSourceTool#guarded_fetch — the single choke point every
    # agent/user write dispatch already passes through — so a new provider
    # only needs the metadata flag on its own create-post-shaped endpoint,
    # zero code change here.
    #
    # Idempotent on [data_source, external_id]: a retried/replayed publish (or
    # the same write observed again via data_source_reconcile/contract) never
    # creates a second Ai::PublishedPost row.
    class PublishedPostRecorder
      # Common id keys across provider write responses: X.com/Mastodon use
      # "id"; Reddit's submit-post response (after records_path "json.data")
      # carries the fullname under "name" (e.g. "t3_abc123"). LinkedIn's
      # created-post URN lives in a response HEADER, outside this JSON-body
      # envelope, so it is not capturable here — LinkedIn's template does not
      # set captures_published_post.
      ID_KEYS = %w[id name].freeze
      CONTENT_KEYS = %w[text title].freeze

      def initialize(account:, agent: nil)
        @account = account
        @agent = agent
      end

      # @return [Ai::PublishedPost, nil] nil when there is nothing to capture
      #   (unsuccessful envelope, no account context, or no recognizable id).
      def record(data_source, endpoint, envelope)
        return nil unless @account
        return nil unless envelope.is_a?(Hash) && envelope[:success] == true

        record_hash = Array(envelope[:data]).first
        return nil unless record_hash.is_a?(Hash)

        external_id = extract(record_hash, ID_KEYS)
        return nil if external_id.blank?

        Ai::PublishedPost.find_or_create_by!(
          ai_data_source_id: data_source.id,
          external_id: external_id.to_s
        ) do |post|
          post.account = @account
          post.endpoint = endpoint
          post.requesting_agent_id = @agent&.id
          post.source_type = data_source.source_type
          post.content = extract(record_hash, CONTENT_KEYS)
          post.published_at = Time.current
        end
      rescue StandardError => e
        Rails.logger.warn("[Growth::PublishedPostRecorder] capture failed for #{data_source&.slug}: #{e.class}: #{e.message}")
        nil
      end

      private

      def extract(record, keys)
        keys.each do |key|
          value = record[key] || record[key.to_sym]
          return value if value.present?
        end
        nil
      end
    end
  end
end
