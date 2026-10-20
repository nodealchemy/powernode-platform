# frozen_string_literal: true

module Ai
  module Skills
    # Seeds one owner's batch of capability skills from YAML data files:
    # gate the whole batch (Ai::Skills::SeedGate), then write the GLOBAL rows in
    # one transaction, then record compositions and project the rows into every
    # account's knowledge graph (nodes + requires/composes/refines edges).
    #
    # A seed never fights the operator or the evolution loop:
    #   - status, is_enabled and version are CREATE-ONLY;
    #   - a row that is no longer active (archived, draft, inactive) is skipped;
    #   - seed-owned content (name, description, category, tags, system_prompt,
    #     metadata) is rewritten only while the row is still SEED-PRISTINE: its
    #     current content digest equals metadata["seed_digest"], the digest of
    #     what the seed last wrote. An operator edit or a prompt fold-in breaks
    #     the match and the row is left alone ("operator-modified, skipped").
    #   - only GLOBAL rows are looked up and written; account-scoped rows (an
    #     account's override, or a tenant row sharing the slug) are never
    #     adopted — the gate reports a non-override one as a warning.
    #
    # Idempotent: a re-run writes nothing new. Core and each extension call this
    # from their own seed file; nothing here names an extension.
    class CapabilitySeeder
      ENTRY_KEYS = %w[slug name category description tags domain capability triggers manifest hints relations evals system_prompt].freeze
      DIGEST_KEY = "seed_digest"

      # `updated` rows keep their version; the model itself bumps the minor
      # version when a routing field (metadata.domain) changes — an audit bump,
      # not a seed write (Ai::Skill#bump_version_on_routing_change).
      Result = Struct.new(:skills, :created, :updated, :unchanged, :skipped_modified, :skipped_inactive,
                          :graph_failures, :warnings, :embedder_mode, keyword_init: true) do
        def summary
          parts = [ "#{skills.size} seeded", "#{created.size} created", "#{updated.size} updated", "#{unchanged.size} unchanged" ]
          parts << "#{skipped_modified.size} operator-modified skipped" if skipped_modified.any?
          parts << "#{skipped_inactive.size} inactive skipped" if skipped_inactive.any?
          parts << "#{warnings.size} warning(s)" if warnings.any?
          parts << "gate embedder: #{embedder_mode}"
          parts.join(", ")
        end
      end

      # Process-wide record of capability seed batches that FAILED, so the seed
      # orchestrator can end the run with a clearly marked error instead of a
      # warning lost mid-log (see .report_failures!).
      @failures = []

      class << self
        attr_reader :failures

        def record_failure!(owner_repo, error)
          @failures << { owner_repo: owner_repo.to_s, error: "#{error.class}: #{error.message}" }
          Rails.logger.error("[Ai::Skills::CapabilitySeeder] CAPABILITY SKILL SEED FAILED for #{owner_repo}: #{error.class}: #{error.message}")
        end

        def reset_failures!
          @failures = []
        end

        # Prints the failure banner (once per run) and returns the failures.
        def report_failures!(io: $stdout)
          return [] if @failures.empty?

          io.puts "\n❌❌ CAPABILITY SKILL SEED FAILED (#{@failures.size} batch(es)) — skills were NOT seeded ❌❌"
          @failures.each { |f| io.puts "   ❌ #{f[:owner_repo]}: #{f[:error].lines.first(12).join.strip}" }
          io.puts "   Dry-run the gate: rails \"skills:gate:check[<owner>,<embedder>]\"\n"
          @failures.dup
        end

        # Each owner's root: core's Rails.root plus each LOADED extension's
        # engine root that ships capability data (none in core mode). Owners
        # keep their data under <root>/db/seeds/capability_skills and their eval
        # fixtures under <root>/spec/fixtures/skill_embeddings.
        # @return [Array<[String, Pathname]>] [owner_repo, root]
        def owner_roots
          roots = [ [ Contract::CORE_OWNER, Rails.root ] ]
          ::Powernode::ExtensionRegistry.each do |slug, ext|
            root = ext[:engine].root
            roots << [ "extensions/#{slug}", root ] if root.join("db", "seeds", "capability_skills").directory?
          end
          roots
        end

        # @return [Array<[String, Pathname]>] [owner_repo, capability data dir]
        def data_sources
          owner_roots.map { |owner, root| [ owner, root.join("db", "seeds", "capability_skills") ] }
        end

        def data_dir_for(owner_repo)
          data_sources.find { |owner, _| owner == owner_repo.to_s }&.last ||
            raise(ArgumentError, "no capability skill data for #{owner_repo.inspect} (known: #{data_sources.map(&:first).join(', ')})")
        end

        # @return [Array<Hash>] raw entries from every *.yml under dir, by file name
        def load_entries(dir)
          Dir[File.join(dir.to_s, "*.yml")].sort.flat_map do |path|
            data = YAML.safe_load_file(path, permitted_classes: [], aliases: false)
            raise ArgumentError, "#{path} must contain a list of skills" unless data.is_a?(Array)

            data
          end
        end

        # Raw YAML entry → attribute hash the gate and the write both read.
        def normalize(raw, owner_repo)
          raw = raw.to_h.transform_keys(&:to_s)
          unknown = raw.keys - ENTRY_KEYS
          raise ArgumentError, "#{raw['slug']}: unknown keys #{unknown.join(', ')}" if unknown.any?

          {
            "slug" => raw["slug"].to_s,
            "name" => raw["name"].to_s,
            "category" => raw["category"].to_s,
            "description" => raw["description"].to_s.strip,
            "tags" => Array(raw["tags"]).map(&:to_s),
            "system_prompt" => raw["system_prompt"].to_s.strip,
            "metadata" => {
              "author" => "system",
              "owner_repo" => owner_repo.to_s,
              "domain" => raw["domain"],
              "capability" => raw["capability"],
              "triggers" => raw["triggers"],
              "manifest" => raw["manifest"],
              "hints" => raw["hints"],
              "relations" => compact_relations(raw["relations"]),
              "evals" => raw["evals"]
            }.compact
          }
        end

        def compact_relations(relations)
          return nil unless relations.is_a?(Hash)

          relations.transform_keys(&:to_s).reject { |_, v| Array(v).empty? }.presence
        end

        # Canonical digest of the seed-owned content of a row or entry.
        def content_digest(name:, description:, category:, tags:, system_prompt:, metadata:)
          meta = (metadata.is_a?(Hash) ? metadata : {}).except(DIGEST_KEY)
          payload = { name: name.to_s, description: description.to_s, category: category.to_s,
                      tags: Array(tags).map(&:to_s), system_prompt: system_prompt.to_s, metadata: deep_sort(meta) }
          Digest::SHA256.hexdigest(JSON.generate(payload))
        end

        def deep_sort(value)
          case value
          when Hash then value.to_h { |k, v| [ k.to_s, deep_sort(v) ] }.sort.to_h
          when Array then value.map { |v| deep_sort(v) }
          else value
          end
        end
      end

      # @param embedder see Ai::Skills::SeedGate (ignored when gate: is given)
      def initialize(owner_repo:, gate: nil, embedder: :auto, account: nil)
        @owner_repo = owner_repo.to_s
        @gate = gate || SeedGate.new(owner_repo: @owner_repo, embedder: embedder, account: account)
      end

      # @return [Result]
      # @raise [SeedGate::GateError] when the batch fails the gate (no row written)
      def seed!(raw_entries)
        entries = raw_entries.map { |raw| normalize(raw) }
        @gate.check!(entries)

        result = Result.new(skills: [], created: [], updated: [], unchanged: [], skipped_modified: [], skipped_inactive: [],
                            graph_failures: [], warnings: @gate.warnings(entries), embedder_mode: @gate.embedder_mode_used)
        ::Ai::Skill.transaction { entries.each { |entry| write(entry, result) } }

        live = result.skills.select { |s| s.status == "active" }
        guard(result, "compositions") { sync_compositions(live) }
        Account.find_each { |account| guard(result, "account #{account.id}") { sync_graph(account, live, result) } }
        result
      end

      # Raw YAML entry → attribute hash the gate and the write both read.
      def normalize(raw)
        self.class.normalize(raw, @owner_repo)
      end

      private

      def write(entry, result)
        skill = ::Ai::Skill.global.find_by(slug: entry["slug"])
        return create(entry, result) if skill.nil?

        result.skills << skill
        if skill.status != "active"
          result.skipped_inactive << skill.slug
          Rails.logger.info("[Ai::Skills::CapabilitySeeder] #{skill.slug}: #{skill.status}, skipped")
          return
        end

        seeded = digest_of(entry)
        stored = skill.metadata.is_a?(Hash) ? skill.metadata[DIGEST_KEY] : nil
        current = digest_of_row(skill)
        if stored.blank? || current != stored
          result.skipped_modified << skill.slug
          Rails.logger.info("[Ai::Skills::CapabilitySeeder] #{skill.slug}: operator-modified, skipped")
        elsif seeded == stored
          result.unchanged << skill.slug
        else
          skill.assign_attributes(content_attributes(entry, seeded))
          skill.save!
          result.updated << skill.slug
        end
      end

      def create(entry, result)
        skill = ::Ai::Skill.new(content_attributes(entry, digest_of(entry)).merge(
          slug: entry["slug"], source_key: entry["slug"], account_id: nil, is_system: true,
          status: "active", is_enabled: true, version: "1.0.0"
        ))
        skill.save!
        result.skills << skill
        result.created << skill.slug
      end

      def content_attributes(entry, digest)
        {
          name: entry["name"], description: entry["description"], category: entry["category"], tags: entry["tags"],
          system_prompt: entry["system_prompt"], metadata: entry["metadata"].merge(DIGEST_KEY => digest),
          is_composite: Array(entry.dig("metadata", "relations", "composes")).any?
        }
      end

      def digest_of(entry)
        self.class.content_digest(name: entry["name"], description: entry["description"], category: entry["category"],
                                  tags: entry["tags"], system_prompt: entry["system_prompt"], metadata: entry["metadata"])
      end

      def digest_of_row(skill)
        self.class.content_digest(name: skill.name, description: skill.description, category: skill.category,
                                  tags: skill.tags, system_prompt: skill.system_prompt, metadata: skill.metadata)
      end

      # Runs one post-write step; a failure is counted and reported, never lost.
      def guard(result, scope)
        yield
      rescue StandardError => e
        result.graph_failures << "#{scope}: #{e.class}: #{e.message}"
        Rails.logger.error("[Ai::Skills::CapabilitySeeder] #{scope} failed: #{e.class}: #{e.message}")
      end

      # A composite's components, in declared order, in the existing composition
      # table. Created when absent; an existing row's order is left alone. A
      # component an operator retired is skipped (the gate reported it).
      def sync_compositions(skills)
        skills.each do |skill|
          Array(skill.metadata.dig("relations", "composes")).each_with_index do |slug, idx|
            component = ::Ai::Skill.global.find_by(slug: slug)
            raise ArgumentError, "#{skill.slug}: composes #{slug}, which is not seeded" unless component
            next unless component.status == "active"
            next if ::Ai::SkillComposition.exists?(composite_skill_id: skill.id, component_skill_id: component.id)

            order = (::Ai::SkillComposition.where(composite_skill_id: skill.id).maximum(:execution_order) || -1) + 1
            ::Ai::SkillComposition.create!(composite_skill: skill, component_skill: component,
                                           composition_type: "sequential", execution_order: [ order, idx ].max)
          end
        end
      end

      # Global rows never fire the per-account KG hook, so each account gets its
      # node copies and relation edges here (the same path
      # BridgeService#sync_all_skills takes for an account created later).
      # Embeddings are generated per account (each account may embed with a
      # different provider, so vectors are not shared): the cost is accounts ×
      # skills embedding calls, cached per account+text.
      def sync_graph(account, skills, result)
        bridge = ::Ai::SkillGraph::BridgeService.new(account)
        skills.each do |skill|
          result.graph_failures << "account #{account.id}: #{skill.slug} node sync failed" unless bridge.sync_skill(skill)
        end
        bridge.sync_capability_relations(skills).each { |failure| result.graph_failures << "account #{account.id}: #{failure}" }
      end
    end
  end
end
