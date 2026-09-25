# frozen_string_literal: true

module Ai
  module Agents
    # Carries seeded text (description, system prompt) to a GLOBAL canonical
    # agent that already exists, without overwriting what an operator edited.
    #
    # Most canonical seeds are create-only (find_or_create_global), so a wording
    # change in a seed never reached a row created earlier; the utility seed did
    # the opposite and rewrote its text on every run, erasing operator edits.
    # Both follow CoreSeeds::CanonicalToolAccess's precedent now (the seed writes
    # on every run), with a guard per field:
    #   - each field's seeded value is stamped as a SHA-256 digest in
    #     mcp_metadata["seeded_content"][field];
    #   - a later value is written only when the row still holds what was last
    #     seeded (its current digest equals the stamp), is blank, or matches one
    #     of the `previous` values a seed lists for rows stamped before this
    #     mechanism existed;
    #   - anything else is an operator edit: the field is left alone and reported.
    # The value a write replaces is kept beside the stamp so #revert! can restore
    # it (a data migration's down).
    #
    # Seeds run only on first boot of an install, so a deployed install reaches
    # new text through a data migration that calls this same service.
    class CanonicalContentRefresh
      STAMP_KEY = "seeded_content"
      FIELDS = %w[description system_prompt].freeze

      Outcome = Struct.new(:slug, :written, :unchanged, :skipped, keyword_init: true) do
        def skipped? = skipped.any?
      end

      def self.digest(value) = Digest::SHA256.hexdigest(value.to_s)

      # @param fields [Hash{String,Symbol => String}] field => seeded value
      # @param previous [Hash{String,Symbol => Array<String>}] field => values an
      #   earlier seed wrote, accepted as "untouched" on an unstamped row
      # @return [Outcome]
      def self.apply!(agent, fields, previous: {})
        new(agent).apply!(fields.transform_keys(&:to_s), previous.transform_keys(&:to_s))
      end

      # Restores the value each field held before the last write, for fields that
      # still hold what that write put there. Used by a data migration's down.
      def self.revert!(agent, fields)
        new(agent).revert!(fields.transform_keys(&:to_s))
      end

      def initialize(agent)
        @agent = agent
        @metadata = (agent.mcp_metadata || {}).deep_dup
        @stamps = @metadata[STAMP_KEY].is_a?(Hash) ? @metadata[STAMP_KEY] : {}
      end

      def apply!(fields, previous)
        outcome = Outcome.new(slug: @agent.slug, written: [], unchanged: [], skipped: [])
        fields.each do |field, value|
          raise ArgumentError, "unknown canonical field #{field.inspect}" unless FIELDS.include?(field)

          current = read(field)
          if current.to_s == value.to_s
            stamp(field, value) unless stamp_for(field) == self.class.digest(value)
            outcome.unchanged << field
          elsif untouched?(field, current, previous[field])
            write(field, value)
            stamp(field, value, replaced: current)
            outcome.written << field
          else
            outcome.skipped << field
          end
        end
        save!
        outcome
      end

      def revert!(fields)
        fields.each do |field, value|
          entry = @stamps[field]
          next unless entry.is_a?(Hash) && entry.key?("replaced") && read(field).to_s == value.to_s

          write(field, entry["replaced"])
          stamp(field, entry["replaced"])
        end
        save!
      end

      private

      def untouched?(field, current, previous)
        return true if current.blank?

        stamped = stamp_for(field)
        return stamped == self.class.digest(current) if stamped

        Array(previous).any? { |value| value.to_s == current.to_s }
      end

      def stamp_for(field) = @stamps.dig(field, "digest")

      def stamp(field, value, replaced: nil)
        entry = { "digest" => self.class.digest(value) }
        entry["replaced"] = replaced unless replaced.nil?
        @stamps[field] = entry
      end

      def read(field)
        field == "description" ? @agent.description : @metadata["system_prompt"]
      end

      def write(field, value)
        if field == "description"
          @agent.description = value
        else
          @metadata["system_prompt"] = value
        end
      end

      def save!
        @metadata[STAMP_KEY] = @stamps
        @agent.mcp_metadata = @metadata
        @agent.save! if @agent.changed?
      end
    end
  end
end
