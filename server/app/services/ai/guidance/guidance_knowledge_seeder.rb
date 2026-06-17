# frozen_string_literal: true

module Ai
  module Guidance
    # Idempotently ingests the committed development-guidance conventions
    # (docs/contributing/conventions/*.md) into platform shared knowledge so the
    # rules are recallable MCP-first by Claude Code AND by platform agents.
    #
    # Idempotency is key-anchored (provenance->>'guidance_key') with integrity-hash
    # change detection — NOT the cosine-similarity dedup of SharedKnowledgeService,
    # which duplicates on edits and silently drops near-neighbours. Re-running is
    # safe: unchanged docs are skipped, edited docs update in place.
    #
    # Gate #9: a doc that names a private extension is refused (never globalized) —
    # such guidance belongs in the extension's own docs / CLAUDE.local.md.
    class GuidanceKnowledgeSeeder
      EXCLUDE = %w[MANIFEST.md adherence-baseline.md README.md].freeze

      Result = Struct.new(:created, :updated, :unchanged, :refused, keyword_init: true) do
        def summary
          "created=#{created} updated=#{updated} unchanged=#{unchanged} refused=#{refused}"
        end
      end

      def initialize(account:, repository: "powernode-platform", dir: nil, private_names: nil)
        @account = account
        @repository = repository
        @dir = Pathname.new(dir || default_dir)
        @private_names = private_names || derive_private_names
      end

      def call
        result = Result.new(created: 0, updated: 0, unchanged: 0, refused: 0)
        return result unless @dir.exist?

        Dir.glob(@dir.join("*.md")).sort.each do |path|
          next if EXCLUDE.include?(File.basename(path))

          content = File.read(path)
          if (ext = private_extension_in(content))
            Rails.logger.warn("[GuidanceSeeder] Refused #{File.basename(path)}: names private extension '#{ext}' (gate #9)")
            result.refused += 1
            next
          end

          upsert(File.basename(path), content, result)
        end
        result
      end

      private

      attr_reader :account, :repository, :dir, :private_names

      def default_dir
        Rails.root.parent.join("docs", "contributing", "conventions")
      end

      def derive_private_names
        Dir.glob(Rails.root.parent.join("extensions", "private", "*"))
           .select { |p| File.directory?(p) }
           .map { |p| File.basename(p) }
      end

      def upsert(filename, content, result)
        key = "guidance:#{File.basename(filename, '.md')}"
        record = Ai::SharedKnowledge
                 .where(account: account)
                 .where("provenance->>'guidance_key' = ?", key)
                 .first_or_initialize
        hash = Digest::SHA256.hexdigest(content)

        if record.persisted? && record.integrity_hash == hash
          result.unchanged += 1
          return record
        end

        was_new = record.new_record?
        record.assign_attributes(
          account: account,
          title: title_from(content, filename),
          content: content,
          content_type: "reference",
          access_level: "account",
          source_type: "import",
          usage_count: record.usage_count || 0,
          tags: ["guidance", "guidance-#{File.basename(filename, '.md')}", "repository:#{repository}"],
          integrity_hash: hash,
          embedding: best_effort_embedding(content),
          provenance: {
            "guidance_key" => key,
            "source_path" => "docs/contributing/conventions/#{filename}",
            "source_type" => "import"
          }
        )
        record.save!

        was_new ? result.created += 1 : result.updated += 1
        record
      end

      def title_from(content, filename)
        heading = content[/^#\s+(.+)$/, 1]
        (heading || File.basename(filename, ".md").tr("-", " ")).strip
      end

      # Structural private-extension reference only (namespace ::, path, import alias),
      # mirroring the core-purity hook. Bare words are not a leak.
      def private_extension_in(content)
        private_names.each do |name|
          cap = name[0].to_s.upcase + name[1..].to_s
          pattern = /\b#{Regexp.escape(cap)}::|@#{Regexp.escape(name)}\/|@ext\/#{Regexp.escape(name)}\/|extensions\/private\/#{Regexp.escape(name)}\b/
          return name if content.match?(pattern)
        end
        nil
      end

      # Tag recall works without embeddings; semantic search benefits from them.
      # Best-effort so a missing/unconfigured provider never breaks seeding.
      def best_effort_embedding(content)
        Ai::Memory::EmbeddingService.new(account: account).generate(content)
      rescue StandardError => e
        Rails.logger.warn("[GuidanceSeeder] Embedding skipped: #{e.message}")
        nil
      end
    end
  end
end
