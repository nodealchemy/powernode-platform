# frozen_string_literal: true

module Ai
  module Skills
    # Deterministic bag-of-words embedding (feature hashing into the platform's
    # embedding dimension, unit-normalised). It stands in for the provider
    # embedding when that is unavailable — the seed gate must still be able to
    # compare a batch at seed time with the worker down — and gives specs a
    # lexical proxy whose similarities follow shared words, which the test-mode
    # mock embedding (random per text) cannot.
    #
    # Similarities on this scale are lexical, not semantic: lower than a neural
    # embedding's for paraphrases, so a gate running on it errs toward passing.
    module LexicalEmbedder
      DIMENSION = ::Ai::Memory::EmbeddingService::EMBEDDING_DIMENSION

      STOPWORDS = %w[
        a an and are as at be by for from has have in into is it its of on or that the
        this to was were will with use when not you your our we i me my do does can
        what which who how all any each one only via per than then them they there
        should must may might also just more most other over under up out off so such
        category tags
      ].to_set.freeze

      SUFFIXES = %w[ations ation ings ing ments ment ers er ies es ed ly s].freeze

      module_function

      def embed(text)
        vector = Array.new(DIMENSION, 0.0)
        tokens(text).tally.each do |token, count|
          vector[Zlib.crc32(token) % DIMENSION] += Math.sqrt(count)
        end
        norm = Math.sqrt(vector.sum { |x| x * x })
        return nil if norm.zero?

        vector.map { |x| x / norm }
      end

      def tokens(text)
        text.to_s.downcase.scan(/[a-z0-9]+/).filter_map do |word|
          next if word.length < 2 || STOPWORDS.include?(word)

          stem(word)
        end
      end

      def stem(word)
        return word if word.length <= 4

        suffix = SUFFIXES.find { |s| word.end_with?(s) && word.length - s.length >= 3 }
        suffix ? word.delete_suffix(suffix) : word
      end

      def cosine(a, b)
        return 0.0 if a.blank? || b.blank?

        dot = 0.0
        na = 0.0
        nb = 0.0
        a.each_with_index do |x, i|
          y = b[i].to_f
          dot += x * y
          na += x * x
          nb += y * y
        end
        return 0.0 if na.zero? || nb.zero?

        dot / (Math.sqrt(na) * Math.sqrt(nb))
      end
    end
  end
end
