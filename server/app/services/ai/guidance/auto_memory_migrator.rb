# frozen_string_literal: true

module Ai
  module Guidance
    # Plans (dry-run, the default) or applies the migration of auto-memory notes
    # into account-scoped platform knowledge, through
    # Ai::Guidance::GuidanceKnowledgeSeeder.for_memory. Tooling only: what is
    # actually migrated is decided by the operator at apply time.
    #
    # Every note is triaged into four sets, and the report names ONLY slugs and
    # sets — never the text that matched (a report that echoed the match would be
    # the leak the triage exists to prevent):
    #
    #   identifiers    (a) content matching the deployment-identifiers list
    #   sensitive      (b) break-glass / security-gap content (SENSITIVE_PATTERNS)
    #   private_names  (c) a private-extension name, derived at runtime
    #   oversize       (d) content the embedding step would truncate
    #
    # APPLY behaviour per set:
    #   (a) SKIPPED, always. Deployment identifiers are the exact content that must
    #       not become generally recallable; there is no flag that overrides it —
    #       edit the note, or file it as deployment-<slug> knowledge instead.
    #   (b) SKIPPED unless include_sensitive (INCLUDE_SENSITIVE=1). The operator's
    #       gate. Access level is "account" either way: SharedKnowledge `private`
    #       is a label, not an ACL (search scopes by account only), so it is not
    #       used for protection.
    #   (c) SKIPPED, always, for the same reason as (a): a private-extension name
    #       must not leave its extension's own docs.
    #   (d) APPLIED. The full text is stored and keyword/tag recall covers all of
    #       it; only the embedding sees the first EMBEDDING_LIMIT characters. That
    #       is a recall-quality note, not a disclosure, so it is reported only.
    # A note in several sets is skipped if ANY skipping rule fires.
    #
    # APPLY never deletes or archives: a note that was applied earlier and is
    # skipped now leaves its earlier entry in place.
    class AutoMemoryMigrator
      class Error < StandardError; end

      SETS = %i[identifiers sensitive private_names oversize].freeze
      ALWAYS_SKIPPED = %i[identifiers private_names].freeze
      # Ai::Memory::EmbeddingService#normalize_text truncates at this many characters.
      EMBEDDING_LIMIT = 8000
      DEFAULT_IDENTIFIERS_PATH = %w[.claude hooks deployment-identifiers.local.txt].freeze
      MANIFEST_DIR = %w[docs operations local].freeze
      MANIFEST_FILE = "memory-migration-manifest.json"
      DRY_RUN_MANIFEST_FILE = "memory-migration-manifest.dry-run.json"

      # Set (b). Deliberately small and explicit: each entry is a label plus a
      # pattern, matched case-insensitively against the whole file. Over-matching
      # is the safe direction (it only holds a note back behind INCLUDE_SENSITIVE).
      SENSITIVE_PATTERNS = {
        "break_glass" => /break[\s_-]?glass/i,
        "security_gap" => /security[\s_-]?(?:gap|hole|weakness)|unmitigated|vulnerab(?:le|ility|ilities)/i,
        "unauthenticated" => /unauthenticated|unauthorized[\s_-]access/i,
        "bypass" => /(?:auth(?:entication|orization)?|permission|guard|gate|policy)[\s_-]?bypass|bypass(?:es|ed)?\s+(?:the\s+)?(?:auth|permission|guard|gate|policy)/i,
        "exploit" => /\bexploit(?:s|ed|able)?\b/i,
        "credential_material" => /\b(?:private[\s_-]?key|secret[\s_-]?key|api[\s_-]?key|bearer\s+token|password|passphrase|seed\s+phrase)\b/i,
        "cve" => /\bCVE-\d{4}-\d{4,}\b/i,
        "privilege_escalation" => /privilege[\s_-]?escalation|self[\s_-]?regrant/i
      }.freeze

      Entry = Struct.new(:slug, :sets, :action, :knowledge_id, keyword_init: true) do
        def skipped?
          action == :skipped
        end
      end

      Report = Struct.new(:mode, :entries, :without_frontmatter, :edges_created, :edges_existing,
                          :identifier_patterns, :manifest_path, keyword_init: true) do
        def by_set(set)
          entries.select { |e| e.sets.include?(set) }.map(&:slug)
        end

        def counts
          entries.group_by(&:action).transform_values(&:size)
        end

        # Slugs and set names only — never the matched text.
        def lines
          out = [ "[ai:migrate_auto_memory] mode=#{mode} notes=#{entries.size} without_frontmatter=#{without_frontmatter.size}" ]
          out << "  identifier patterns loaded: #{identifier_patterns}#{' (set (a) NOT evaluated)' if identifier_patterns.zero?}"
          { identifiers: "(a) identifiers", sensitive: "(b) sensitive", private_names: "(c) private names",
            oversize: "(d) oversize" }.each do |set, label|
            slugs = by_set(set)
            out << "  #{label}: #{slugs.size}#{" -> #{slugs.join(', ')}" if slugs.any?}"
          end
          out << "  #{counts.sort.map { |a, n| "#{a}=#{n}" }.join(' ')}"
          out << "  edges created=#{edges_created} existing=#{edges_existing}" if mode == :apply
          out << "  manifest: #{manifest_path}" if manifest_path
          out
        end
      end

      def initialize(dir:, account: nil, apply: false, include_sensitive: false, identifiers_path: nil,
                     require_identifiers: true, private_names: nil, manifest_dir: nil, graph_service: nil)
        raise Error, "APPLY requires an account" if apply && account.nil?

        @dir = Pathname.new(dir)
        @account = account
        @apply = apply
        @include_sensitive = include_sensitive
        @identifier_patterns = load_identifier_patterns(identifiers_path)
        @require_identifiers = require_identifiers
        @private_patterns = (private_names || derive_private_names).map { |n| /\b#{Regexp.escape(n)}\b/i }
        @manifest_dir = Pathname.new(manifest_dir || Rails.root.parent.join(*MANIFEST_DIR))
        @graph_service = graph_service
      end

      def call
        raise Error, "#{@dir} is not a directory" unless @dir.directory?
        if @apply && @identifier_patterns.empty? && @require_identifiers
          raise Error, "APPLY refused: the deployment-identifiers list is missing or empty, so set (a) cannot be " \
                       "evaluated (set ALLOW_NO_IDENTIFIERS=1 if this deployment has none)"
        end

        loaded = AutoMemoryFile.load_dir(@dir)
        entries = loaded.files.map { |file| [ file, plan(file) ] }
        applied = @apply ? apply_entries(entries) : []
        edges = @apply ? link_entries(entries.select { |_f, e| applied.include?(e.slug) }) : { created: 0, existing: 0 }

        report = Report.new(
          mode: @apply ? :apply : :dry_run, entries: entries.map(&:last), without_frontmatter: loaded.without_frontmatter,
          edges_created: edges[:created], edges_existing: edges[:existing],
          identifier_patterns: @identifier_patterns.size
        )
        report.manifest_path = write_manifest(report).to_s
        report
      end

      private

      attr_reader :account, :dir

      def plan(file)
        sets = []
        sets << :identifiers if @identifier_patterns.any? { |re| file.raw.match?(re) }
        sets << :sensitive if SENSITIVE_PATTERNS.values.any? { |re| file.raw.match?(re) }
        sets << :private_names if @private_patterns.any? { |re| file.raw.match?(re) }
        sets << :oversize if file.content.length > EMBEDDING_LIMIT
        Entry.new(slug: file.slug, sets: sets, action: skip?(sets) ? :skipped : :planned)
      end

      def skip?(sets)
        sets.intersect?(ALWAYS_SKIPPED) || (sets.include?(:sensitive) && !@include_sensitive)
      end

      # Seeds every non-skipped note; returns the slugs written or left unchanged.
      def apply_entries(entries)
        seeder = GuidanceKnowledgeSeeder.for_memory(account: account, dir: dir)
        entries.filter_map do |file, entry|
          next if entry.skipped?

          entry.action = seeder.seed_memory_file(file)
          entry.knowledge_id = Ai::SharedKnowledge.where(account: account)
                                                  .where("provenance->>'guidance_key' = ?", "memory:#{file.slug}")
                                                  .pick(:id)
          entry.slug
        end
      end

      # related_to edges from [[slug]] links. Both ends must be notes applied in
      # THIS run, so an edge never names (and so never reveals) a skipped note.
      def link_entries(applied_pairs)
        counts = { created: 0, existing: 0 }
        by_slug = applied_pairs.to_h { |file, entry| [ file.slug, [ file, entry ] ] }
        applied_pairs.each do |file, entry|
          file.links.each do |target_slug|
            target = by_slug[target_slug] or next
            source_node = memory_node(file, entry)
            target_node = memory_node(*target)
            if edge_exists?(source_node, target_node)
              counts[:existing] += 1
            else
              graph_service.create_edge(source: source_node, target: target_node, relation_type: "related_to",
                                        label: "memory link", metadata: { "source" => "auto_memory" })
              counts[:created] += 1
            end
          end
        end
        counts
      end

      # One content node per note, named after its key so the (account, name,
      # node_type) uniqueness makes a re-run find rather than duplicate it.
      def memory_node(file, entry)
        name = "memory:#{file.slug}"
        node = account.ai_knowledge_graph_nodes.active.find_by(name: name, node_type: "content")
        return node if node

        graph_service.create_node(
          name: name, node_type: "content", entity_type: "custom", description: file.description,
          metadata: { "source" => "auto_memory", "shared_knowledge_id" => entry.knowledge_id, "guidance_key" => name }
        )
      end

      def edge_exists?(source, target)
        account.ai_knowledge_graph_edges.active
               .exists?(source_node_id: source.id, target_node_id: target.id, relation_type: "related_to")
      end

      def graph_service
        @graph_service ||= KnowledgeGraph::GraphService.new(account)
      end

      # Dry run and apply write DIFFERENT files, so a dry run can never clobber
      # the manifest an apply produced. A dry-run entry is `planned` with no id.
      def write_manifest(report)
        FileUtils.mkdir_p(@manifest_dir)
        path = @manifest_dir.join(@apply ? MANIFEST_FILE : DRY_RUN_MANIFEST_FILE)
        entries = report.entries.to_h do |e|
          [ e.slug, { "status" => e.action.to_s, "knowledge_id" => e.knowledge_id, "sets" => e.sets.map(&:to_s) } ]
        end
        payload = { "mode" => report.mode.to_s, "generated_at" => Time.current.iso8601,
                    "account_id" => (account&.id if @apply), "entries" => entries }
        File.write(path, JSON.pretty_generate(payload))
        path
      end

      # One POSIX-ERE-style pattern per line, blanks and # comments ignored — the
      # same list scripts/checks/deployment-identifier-check.sh reads. A line Ruby
      # cannot compile is matched literally rather than dropped (fail closed).
      def load_identifier_patterns(path)
        path = Pathname.new(path || Rails.root.parent.join(*DEFAULT_IDENTIFIERS_PATH))
        return [] unless path.file?

        path.readlines(chomp: true).map(&:strip).reject { |l| l.empty? || l.start_with?("#") }.map do |line|
          Regexp.new(line, Regexp::IGNORECASE)
        rescue RegexpError
          Regexp.new(Regexp.escape(line), Regexp::IGNORECASE)
        end
      end

      def derive_private_names
        Dir.glob(Rails.root.parent.join("extensions", "private", "*"))
           .select { |p| File.directory?(p) }.map { |p| File.basename(p) }
      end
    end
  end
end
