# frozen_string_literal: true

module Ai
  module Skills
    # Real provider embeddings for the capability-skill eval corpus, recorded
    # once (`rails skills:eval:record_embeddings`) and replayed by the discovery
    # specs, which cannot reach a provider (the test-mode embedding service
    # returns a random mock). Like a VCR cassette: vectors only, keyed by a hash
    # of the text, no secrets.
    #
    # Compact on purpose: text-embedding-3 vectors keep their quality when
    # truncated to a prefix and re-normalised, so each vector is stored as its
    # first DIMENSIONS components, quantised to int8. Replayed cosines track
    # the full-dimension ones closely, not exactly — the provider-backed runner
    # (`rails skills:eval:discovery`) stays the authority on production numbers.
    #
    # Per owner: each owner records its own corpus — its skills' embedding
    # texts and eval tasks plus the extra task lines its specs use — into
    # <owner root>/spec/fixtures/skill_embeddings/vectors.json, so core's
    # fixtures never carry an extension's texts.
    module RecordedEmbeddings
      DIMENSIONS = 1024
      FORMAT = "int8-peak-prefix-#{DIMENSIONS}"

      class Missing < StandardError; end

      module_function

      def key(text)
        Digest::SHA256.hexdigest(text.to_s.strip.gsub(/\s+/, " "))[0, 24]
      end

      # An owner's eval fixtures live beside its own specs.
      def fixture_dir(root)
        Pathname(root).join("spec", "fixtures", "skill_embeddings")
      end

      def extra_tasks(root)
        file = fixture_dir(root).join("extra_tasks.txt")
        return [] unless file.exist?

        file.readlines.map(&:strip).reject { |line| line.empty? || line.start_with?("#") }
      end

      # Every text one owner's specs will ask to embed: its skills' embedding
      # texts and eval tasks, plus its extra task lines.
      # @return [Array<String>]
      def corpus_for(owner, root)
        dir = CapabilitySeeder.data_sources.to_h.fetch(owner)
        texts = CapabilitySeeder.load_entries(dir).flat_map do |raw|
          entry = CapabilitySeeder.normalize(raw, owner)
          skill = ::Ai::Skill.new(entry.slice("name", "description", "category", "tags", "metadata"))
          [ ::Ai::SkillGraph::BridgeService.embedding_text_for(skill), *Array(entry.dig("metadata", "evals")).map { |ev| ev["task"] } ]
        end
        (texts + extra_tasks(root)).map { |t| t.to_s.strip }.reject(&:empty?).uniq
      end

      # Every loaded owner's recorded vectors, merged. Deterministic: a text two
      # owners both recorded keeps the vector of the owner whose own batch
      # contains it (its skill text or eval task), else core's, else the first
      # owner's in registry order — and a collision with DIFFERING vectors is
      # logged, since it means one owner's fixture is stale.
      def combined_fixture
        owners = CapabilitySeeder.owner_roots.filter_map do |owner, root|
          file = fixture_dir(root).join("vectors.json")
          next unless file.exist?

          data = JSON.parse(file.read)
          raise ArgumentError, "#{file}: unexpected fixture format #{data['format'].inspect}" unless data["format"] == FORMAT

          [ owner, data["vectors"] ]
        end
        { "format" => FORMAT, "vectors" => merge_owned(owners) }
      end

      # @param owners [Array<[String, Hash]>] owner → vectors, in registry order
      def merge_owned(owners)
        merged = {}
        chosen = {}
        owners.each do |owner, vectors|
          native = native_keys(owner)
          vectors.each do |key, blob|
            if !merged.key?(key)
              merged[key] = blob
              chosen[key] = owner
              next
            end
            next if merged[key] == blob

            Rails.logger.warn("[Ai::Skills::RecordedEmbeddings] #{key} recorded differently by #{chosen[key]} and #{owner}; one fixture is stale")
            if native.include?(key) && !native_keys(chosen[key]).include?(key)
              merged[key] = blob
              chosen[key] = owner
            end
          end
        end
        merged
      end

      # Keys of the texts an owner's own batch contains (skill texts and evals).
      def native_keys(owner)
        @native_keys ||= {}
        @native_keys[owner] ||= begin
          dir = CapabilitySeeder.data_sources.to_h[owner]
          return Set.new unless dir

          CapabilitySeeder.load_entries(dir).flat_map do |raw|
            entry = CapabilitySeeder.normalize(raw, owner)
            skill = ::Ai::Skill.new(entry.slice("name", "description", "category", "tags", "metadata"))
            [ ::Ai::SkillGraph::BridgeService.embedding_text_for(skill), *Array(entry.dig("metadata", "evals")).map { |ev| ev["task"] } ]
          end.to_set { |text| key(text) }
        end
      end

      # Scaled by the largest component before quantising (direction is all a
      # cosine needs; #decode re-normalises), so int8 keeps ~7 bits per value.
      def encode(vector)
        prefix = vector.first(DIMENSIONS)
        peak = prefix.map(&:abs).max.to_f
        peak = 1.0 if peak.zero?
        Base64.strict_encode64(prefix.map { |x| (x / peak * 127).round.clamp(-127, 127) }.pack("c*"))
      end

      def decode(blob)
        normalise(Base64.strict_decode64(blob).unpack("c*").map { |c| c / 127.0 })
      end

      def normalise(vector)
        norm = Math.sqrt(vector.sum { |x| x * x })
        norm.zero? ? vector : vector.map { |x| x / norm }
      end

      # Builds a fixture hash from the account's provider (raises if any text
      # cannot be embedded).
      def record(texts, account:)
        vectors = SkillEmbedder.new(:provider, account: account).embed_all(texts.index_by { |t| key(t) })
        { "format" => FORMAT, "vectors" => vectors.sort.to_h.transform_values { |v| encode(v) } }
      end

      # A text → vector lookup over a recorded fixture; raises Missing (with the
      # re-record command) for a text that was not recorded.
      def lookup(fixture)
        raise ArgumentError, "unexpected fixture format #{fixture['format'].inspect}" unless fixture["format"] == FORMAT

        vectors = fixture["vectors"]
        lambda do |text|
          blob = vectors[key(text)] ||
                 raise(Missing, "no recorded embedding for #{text.to_s.truncate(80).inspect}; re-record with " \
                                "rails skills:eval:record_embeddings (needs a provider)")
          # Zero-padded to the column width; padding leaves cosines unchanged.
          vector = decode(blob)
          vector + Array.new([ ::Ai::Memory::EmbeddingService::EMBEDDING_DIMENSION - vector.size, 0 ].max, 0.0)
        end
      end
    end
  end
end
