# frozen_string_literal: true

module Ai
  module Skills
    # Embeds a set of texts in ONE vector space for the capability seed gate and
    # the discovery eval runner. Modes:
    #
    #   :provider — the account's embedding provider only. Raises
    #               EmbeddingUnavailable if any text cannot be embedded, so a
    #               check that must reflect production similarity never silently
    #               degrades to a different scale.
    #   :lexical  — Ai::Skills::LexicalEmbedder only (deterministic, offline).
    #   :auto     — the provider when it embeds every text, else lexical for all
    #               of them (cosines across two spaces are meaningless). The
    #               first failure decides: no further provider call is made.
    #
    # A callable may be passed instead of a mode (specs); it is used as-is.
    # After #embed_all, #mode_used says which space was actually used.
    class SkillEmbedder
      class EmbeddingUnavailable < StandardError; end

      MODES = %i[provider lexical auto].freeze

      attr_reader :mode, :mode_used

      def self.mode_from(value)
        return value if value.respond_to?(:call)

        mode = value.to_s.strip.presence&.to_sym || :auto
        raise ArgumentError, "embedder must be one of #{MODES.join(', ')}" unless MODES.include?(mode)

        mode
      end

      def initialize(mode = :auto, account: nil)
        @mode = self.class.mode_from(mode)
        @account = account
      end

      # @param texts [Hash{Object => String}] key → text
      # @return [Hash{Object => Array<Float>}] key → vector
      def embed_all(texts)
        if @mode.respond_to?(:call)
          @mode_used = "custom"
          vectors = texts.transform_values { |text| @mode.call(text) }
          return vectors if vectors.values.all?(&:present?)

          @mode_used = "custom+lexical"
          return lexical(texts)
        end

        case @mode
        when :lexical
          @mode_used = "lexical"
          lexical(texts)
        when :provider
          vectors = provider(texts)
          missing = vectors.select { |_, v| v.blank? }.keys
          raise EmbeddingUnavailable, "provider could not embed the set (stopped at the first failure, #{missing.size} of #{texts.size} texts unembedded; account #{account&.id || 'none'})" if missing.any?

          @mode_used = "provider"
          vectors
        else
          vectors = provider(texts)
          if vectors.values.all?(&:present?)
            @mode_used = "provider"
            vectors
          else
            Rails.logger.warn("[Ai::Skills::SkillEmbedder] provider embedding unavailable; using lexical for the whole set")
            @mode_used = "lexical (provider unavailable)"
            lexical(texts)
          end
        end
      end

      def account
        @account ||= Account.first
      end

      private

      def lexical(texts)
        texts.transform_values { |text| LexicalEmbedder.embed(text) }
      end

      # Stops at the FIRST text the provider cannot embed (nil or error): each
      # failed call can wait out the provider timeout, and this runs inside
      # first-boot db:seed under a start timeout. Unattempted texts stay nil.
      def provider(texts)
        vectors = texts.transform_values { nil }
        return vectors unless account

        service = ::Ai::Memory::EmbeddingService.new(account: account)
        texts.each do |key, text|
          vector = begin
            service.generate_or_nil(text, context: "capability skills")
          rescue StandardError => e
            Rails.logger.warn("[Ai::Skills::SkillEmbedder] provider embedding failed (#{e.class})")
            nil
          end
          break if vector.blank?

          vectors[key] = vector
        end
        vectors
      end
    end
  end
end
