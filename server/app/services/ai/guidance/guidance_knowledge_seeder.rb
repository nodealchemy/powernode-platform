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
      # Provenance source_path label for auto-memory entries. Never the real
      # directory: an absolute path under a home directory is a local fact.
      MEMORY_DIR_LABEL = "memory"

      # Conventions docs whose file was renamed: old slug => new slug. The key is
      # derived from the filename, so without this a rename would seed a SECOND
      # entry and leave the old one recallable under its old tag. #call moves the
      # old entry onto the new key before seeding (keeping its id, usage and
      # provenance), or archives it when an entry under the new key already
      # exists. Acts only when the new doc is present in the seeded directory.
      RENAMED = {
        "fable5-compliance" => "frontier-model-compliance"
      }.freeze

      Result = Struct.new(:created, :updated, :unchanged, :refused, :renamed, keyword_init: true) do
        def summary
          "created=#{created} updated=#{updated} unchanged=#{unchanged} refused=#{refused} renamed=#{renamed}"
        end
      end

      # Deployment-local variant: reads the gitignored docs/operations/local/ tree,
      # tags entries `deployment` / `deployment-<slug>`, never refuses on gate #9.
      def self.for_deployment(account:, repository: "powernode-platform", dir: nil, private_names: nil)
        new(
          account: account, repository: repository, private_names: private_names,
          dir: dir || Rails.root.parent.join(*DEPLOYMENT_DIR),
          tag_prefix: "deployment", source_dir_label: DEPLOYMENT_DIR.join("/"),
          refuse_private_references: false, renamed: {}
        )
      end

      # Auto-memory variant: reads frontmatter-bearing memory notes (see
      # Ai::Guidance::AutoMemoryFile), tags `memory` / `memory-<type>` /
      # `memory-<slug>`, never refuses on gate #9 (the source is a local,
      # gitignored directory and the entry is account-scoped — access_level is
      # "account" here as in every path through #upsert_guidance, never "global").
      # It reuses #upsert_guidance rather than adding a second upsert. #call seeds
      # A memory-mode seeder has NO bulk #call (it raises): the triage/gating a
      # migration needs lives in Ai::Guidance::AutoMemoryMigrator, which is the
      # only caller of the per-note primitive #seed_memory_file.
      def self.for_memory(account:, dir:, repository: "powernode-platform")
        new(
          account: account, repository: repository, private_names: [], dir: dir,
          tag_prefix: "memory", source_dir_label: MEMORY_DIR_LABEL,
          refuse_private_references: false, renamed: {}, memory: true
        )
      end

      def initialize(account:, repository: "powernode-platform", dir: nil, private_names: nil,
                     tag_prefix: "guidance", source_dir_label: "docs/contributing/conventions",
                     refuse_private_references: true, renamed: RENAMED, memory: false)
        @account = account
        @repository = repository
        @dir = Pathname.new(dir || default_dir)
        @private_names = private_names || derive_private_names
        @tag_prefix = tag_prefix
        @source_dir_label = source_dir_label
        @refuse_private_references = refuse_private_references
        @renamed = renamed
        @memory = memory
      end

      def call
        raise ArgumentError, "a for_memory seeder has no bulk #call; use Ai::Guidance::AutoMemoryMigrator" if memory

        result = Result.new(created: 0, updated: 0, unchanged: 0, refused: 0, renamed: 0)
        return result unless @dir.exist?

        renamed.each do |old_slug, new_slug|
          result.renamed += 1 if retire_renamed(old_slug, new_slug)
        end

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

      # Seed ONE parsed auto-memory note (Ai::Guidance::AutoMemoryFile) through the
      # shared key-anchored upsert. Returns :created / :updated / :unchanged.
      def seed_memory_file(memory_file)
        upsert_guidance(
          key: "#{tag_prefix}:#{memory_file.slug}",
          slug: memory_file.slug,
          title: memory_file.title,
          content: memory_file.content,
          extra_tags: memory_file.memory_type ? [ "#{tag_prefix}-#{memory_file.memory_type}" ] : [],
          provenance: {
            "slug" => memory_file.slug,
            "memory_type" => memory_file.memory_type,
            "origin_session_id" => memory_file.origin_session_id,
            "links" => memory_file.links,
            "source_path" => "#{source_dir_label}/#{memory_file.filename}"
          },
          source_type: "import",
          content_type: "reference"
        )
      end

      # Idempotently upsert ONE guidance knowledge entry, keyed by
      # provenance->>'guidance_key'. Reused by #call (docs) and by
      # Ai::Learning::GuidancePromotionService (durable loop/operator learnings) so
      # both paths share the key-anchored upsert AND the gate #9 refusal. Returns
      # :created / :updated / :unchanged / :refused. `extra_tags` are merged after
      # the canonical guidance / guidance-<slug> / repository tags.
      #
      # `content_type` is a parameter (default "reference") because the MCP
      # keyed-create path (Ai::Memory::SharedKnowledgeService#upsert) lets a
      # caller write markdown/procedure entries through this same upsert rather
      # than adding a second one — see IMP-a7734de23fc7.
      def upsert_guidance(key:, slug:, title:, content:, provenance: {}, extra_tags: [], source_type: "import",
                          content_type: "reference")
        if refuse_private_references && (ext = private_extension_in(content))
          Rails.logger.warn("[GuidanceSeeder] Refused #{key}: names private extension '#{ext}' (gate #9)")
          return :refused
        end

        record = Ai::SharedKnowledge
                 .where(account: account)
                 .where("provenance->>'guidance_key' = ?", key)
                 .first_or_initialize
        hash = Digest::SHA256.hexdigest(content)
        stored = record.provenance || {}

        # An archived row is still found by key (archiving is a provenance flag,
        # not a delete), so a re-write of unchanged content would otherwise
        # report success while the entry stayed invisible to search. Writing the
        # key again is an assertion that the entry should exist, so it revives:
        # the archive flags are cleared and the outcome is :updated even when the
        # body is byte-identical, never a silent :unchanged on a hidden row.
        archived = stored["archived"] == true

        return :unchanged if record.persisted? && record.integrity_hash == hash && !archived

        was_new = record.new_record?
        record.assign_attributes(
          account: account,
          title: title,
          content: content,
          content_type: content_type,
          access_level: "account",
          source_type: source_type,
          usage_count: record.usage_count || 0,
          # Tags and provenance MERGE with what is stored. A caller that edits an
          # entry without repeating its tags must not lose them, and provenance
          # written by another producer (e.g. GuidancePromotionService's
          # source_learning_id, which rating propagation reads) must survive a
          # later write through a different path.
          tags: (Array(record.tags) + [ tag_prefix, "#{tag_prefix}-#{slug}", "repository:#{repository}" ] +
                 Array(extra_tags)).map { |t| t.to_s }.uniq,
          integrity_hash: hash,
          embedding: best_effort_embedding(content),
          provenance: stored.merge(provenance).merge("guidance_key" => key)
                            .except("archived", "archived_at", "archived_by")
        )
        record.save!

        was_new ? :created : :updated
      end

      private

      attr_reader :account, :repository, :dir, :private_names, :tag_prefix, :source_dir_label,
                  :refuse_private_references, :renamed, :memory

      def find_by_key(key)
        Ai::SharedKnowledge.where(account: account).where("provenance->>'guidance_key' = ?", key).first
      end

      # Move the entry seeded from a renamed doc onto the new key, dropping its
      # old guidance-<slug> tag (tags merge on upsert, so the old tag would
      # otherwise survive the rename). If an entry under the new key already
      # exists, the old one is archived instead so the two never both surface.
      # Returns true when it changed a row.
      def retire_renamed(old_slug, new_slug)
        return false unless dir.join("#{new_slug}.md").exist?

        old_record = find_by_key("#{tag_prefix}:#{old_slug}")
        return false unless old_record

        stored = old_record.provenance || {}
        if find_by_key("#{tag_prefix}:#{new_slug}")
          return false if stored["archived"] == true

          old_record.update!(provenance: stored.merge(
            "archived" => true,
            "archived_at" => Time.current.iso8601,
            "archived_by" => "guidance-seeder:renamed-to:#{new_slug}"
          ))
        else
          old_record.update!(
            tags: Array(old_record.tags).map { |t| t == "#{tag_prefix}-#{old_slug}" ? "#{tag_prefix}-#{new_slug}" : t }.uniq,
            provenance: stored.merge("guidance_key" => "#{tag_prefix}:#{new_slug}", "renamed_from" => "#{tag_prefix}:#{old_slug}")
          )
        end
        Rails.logger.info("[GuidanceSeeder] Retired #{tag_prefix}:#{old_slug} in favour of #{tag_prefix}:#{new_slug}")
        true
      end

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
