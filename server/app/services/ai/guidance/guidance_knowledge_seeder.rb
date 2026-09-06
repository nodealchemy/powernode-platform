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
    #
    # The same seeder ingests DEPLOYMENT-LOCAL operator docs (the gitignored
    # docs/operations/local/*.md) as `deployment-<slug>` entries — see
    # Ai::Guidance::GuidanceKnowledgeSeeder.for_deployment and
    # docs/contributing/conventions/deployment-knowledge.md. Those differ in three
    # ways, all parameters here: tag prefix, provenance path, and gate #9 is OFF
    # (the source is gitignored and the entry account-scoped, so a private-extension
    # name there is local operator detail, not a public leak).
    class GuidanceKnowledgeSeeder
      EXCLUDE = %w[MANIFEST.md adherence-baseline.md README.md].freeze
      DEPLOYMENT_DIR = %w[docs operations local].freeze

      Result = Struct.new(:created, :updated, :unchanged, :refused, keyword_init: true) do
        def summary
          "created=#{created} updated=#{updated} unchanged=#{unchanged} refused=#{refused}"
        end
      end

      # Deployment-local variant: reads the gitignored docs/operations/local/ tree,
      # tags entries `deployment` / `deployment-<slug>`, never refuses on gate #9.
      def self.for_deployment(account:, repository: "powernode-platform", dir: nil, private_names: nil)
        new(
          account: account, repository: repository, private_names: private_names,
          dir: dir || Rails.root.parent.join(*DEPLOYMENT_DIR),
          tag_prefix: "deployment", source_dir_label: DEPLOYMENT_DIR.join("/"),
          refuse_private_references: false
        )
      end

      def initialize(account:, repository: "powernode-platform", dir: nil, private_names: nil,
                     tag_prefix: "guidance", source_dir_label: "docs/contributing/conventions",
                     refuse_private_references: true)
        @account = account
        @repository = repository
        @dir = Pathname.new(dir || default_dir)
        @private_names = private_names || derive_private_names
        @tag_prefix = tag_prefix
        @source_dir_label = source_dir_label
        @refuse_private_references = refuse_private_references
      end

      def call
        result = Result.new(created: 0, updated: 0, unchanged: 0, refused: 0)
        return result unless @dir.exist?

        Dir.glob(@dir.join("*.md")).sort.each do |path|
          next if EXCLUDE.include?(File.basename(path))

          filename = File.basename(path)
          slug = File.basename(filename, ".md")
          content = File.read(path)
          outcome = upsert_guidance(
            key: "#{tag_prefix}:#{slug}",
            slug: slug,
            title: title_from(content, filename),
            content: content,
            provenance: { "source_path" => "#{source_dir_label}/#{filename}", "source_type" => "import" },
            source_type: "import"
          )
          tally(result, outcome)
        end
        result
      end

      # Idempotently upsert ONE guidance knowledge entry, keyed by
      # provenance->>'guidance_key'. Reused by #call (docs) and by
      # Ai::Learning::GuidancePromotionService (durable loop/operator learnings) so
      # both paths share the key-anchored upsert AND the gate #9 refusal. Returns
      # :created / :updated / :unchanged / :refused. `extra_tags` are merged after
      # the canonical guidance / guidance-<slug> / repository tags.
      def upsert_guidance(key:, slug:, title:, content:, provenance: {}, extra_tags: [], source_type: "import")
        if refuse_private_references && (ext = private_extension_in(content))
          Rails.logger.warn("[GuidanceSeeder] Refused #{key}: names private extension '#{ext}' (gate #9)")
          return :refused
        end

        record = Ai::SharedKnowledge
                 .where(account: account)
                 .where("provenance->>'guidance_key' = ?", key)
                 .first_or_initialize
        hash = Digest::SHA256.hexdigest(content)

        return :unchanged if record.persisted? && record.integrity_hash == hash

        was_new = record.new_record?
        record.assign_attributes(
          account: account,
          title: title,
          content: content,
          content_type: "reference",
          access_level: "account",
          source_type: source_type,
          usage_count: record.usage_count || 0,
          tags: ([tag_prefix, "#{tag_prefix}-#{slug}", "repository:#{repository}"] + Array(extra_tags)).map { |t| t.to_s }.uniq,
          integrity_hash: hash,
          embedding: best_effort_embedding(content),
          provenance: provenance.merge("guidance_key" => key)
        )
        record.save!

        was_new ? :created : :updated
      end

      private

      attr_reader :account, :repository, :dir, :private_names, :tag_prefix, :source_dir_label,
                  :refuse_private_references

      def default_dir
        Rails.root.parent.join("docs", "contributing", "conventions")
      end

      def derive_private_names
        Dir.glob(Rails.root.parent.join("extensions", "private", "*"))
           .select { |p| File.directory?(p) }
           .map { |p| File.basename(p) }
      end

      def tally(result, outcome)
        case outcome
        when :created then result.created += 1
        when :updated then result.updated += 1
        when :unchanged then result.unchanged += 1
        when :refused then result.refused += 1
        end
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
