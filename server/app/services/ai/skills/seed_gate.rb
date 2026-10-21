# frozen_string_literal: true

module Ai
  module Skills
    # The gate every capability-skill seed batch passes before a row is written.
    # A batch that fails writes NOTHING (the seeder checks the whole batch first)
    # and raises GateError listing every violation. #violations and
    # #similarity_report are read-only (apart from what must be embedded) and
    # back the dry-run task `rails skills:gate:check`.
    #
    # Checks, in order:
    #   1. Contract  — each entry conforms to Ai::Skills::Contract.
    #   2. Identity  — slugs and capabilities are unique in the batch; no OTHER
    #                  active capability skill owns a capability; a slug is not
    #                  taken by a legacy or other-owner GLOBAL row. Account rows
    #                  never block (see #warnings).
    #   3. Verbs     — every manifest verb is a registered platform tool, and a
    #                  skill that attests gate_category read names no verb whose
    #                  declaration is `mutating: true` (except the explicit
    #                  Contract allowlist: the self-report verb and the
    #                  read-only probes an extension registers).
    #   4. Relations — targets exist (batch or seeded), and cross only where
    #                  isolation allows (core → core; extension → core or itself);
    #                  a target an operator retired is skipped with a warning.
    #   5. Purity    — core seeds name no extension verb, path or skill;
    #                  extension seeds name no OTHER extension's verbs.
    #   6. Similarity— reuses ConflictDetectionService's bands within a domain:
    #                  a duplicate fails; an overlap requires each side being
    #                  seeded to name the sibling in triggers.not_for.
    #
    # Extension identity is derived dynamically (the extension registry plus the
    # extensions directory), never named here.
    class SeedGate
      class GateError < StandardError; end

      REPORT_FLOOR = 0.6
      SLUG_BOUNDARY = "(?<![a-z0-9-])%s(?![a-z0-9-])"

      attr_reader :owner_repo, :embedder

      # @param owner_repo [String] "core" or "extensions/<slug>" — who is seeding
      # @param embedder [Symbol, String, #call] :provider, :lexical or :auto (see
      #   Ai::Skills::SkillEmbedder), or a callable text → vector
      # @param account [Account, nil] whose embedding provider is used
      # @param pending [Array<Hash>] DRY RUN only: other owners' normalized
      #   entries that would be seeded first (core, for an extension batch),
      #   accepted as relation targets as if already seeded
      def initialize(owner_repo:, embedder: :auto, account: nil, pending: [])
        @owner_repo = owner_repo.to_s
        @embedder = SkillEmbedder.new(embedder, account: account)
        @pending = normalize_keys(pending).index_by { |e| e["slug"] }
      end

      # The embedding space the last similarity check used ("provider",
      # "lexical", "lexical (provider unavailable)", "custom").
      def embedder_mode_used
        embedder.mode_used
      end

      # @param entries [Array<Hash>] normalized attributes (string keys: slug,
      #   name, description, category, tags, system_prompt, metadata)
      # @raise [GateError] when any check fails
      def check!(entries)
        errors = violations(entries)
        raise GateError, "capability skill seed gate (#{owner_repo}) rejected the batch:\n  - #{errors.join("\n  - ")}" if errors.any?

        true
      end

      def violations(entries)
        entries = normalize_keys(entries)
        errors = []
        entries.each do |entry|
          errors.concat(Contract.validate(entry))
          owner = entry.dig("metadata", "owner_repo").to_s
          errors << "#{entry['slug']}: owner_repo #{owner.inspect} does not match the seeding repo #{owner_repo.inspect}" if owner != owner_repo
        end
        errors.concat(identity_errors(entries))
        errors.concat(collision_errors(entries))
        errors.concat(verb_errors(entries))
        errors.concat(read_skill_errors(entries))
        errors.concat(relation_errors(entries))
        errors.concat(purity_errors(entries))
        errors.concat(similarity_errors(entries))
        errors
      end

      # Non-fatal findings the seed summary reports: tenant rows shadowing a
      # seeded slug, and relations skipped because their target was retired.
      def warnings(entries)
        entries = normalize_keys(entries)
        shadowing_warnings(entries) + retired_relation_warnings(entries)
      end

      # Every same-domain pair at or above REPORT_FLOOR, most similar first:
      # [{ a:, b:, domain:, similarity:, band:, margin:, named: }]. `margin` is
      # the distance to the next band boundary up (overlap at 0.7, duplicate at
      # 0.92); `named` is whether each side's not_for names the other.
      def similarity_report(entries)
        pairs(normalize_keys(entries)).select { |p| p[:similarity] >= REPORT_FLOOR }
                                      .sort_by { |p| -p[:similarity] }
      end

      private

      def normalize_keys(entries)
        entries.map { |e| e.to_h.transform_keys(&:to_s) }
      end

      # ---- identity -------------------------------------------------------

      def identity_errors(entries)
        errors = []
        dupes(entries.map { |e| e["slug"] }).each { |s| errors << "slug #{s} appears more than once in the batch" }
        dupes(entries.map { |e| e.dig("metadata", "capability") }).each { |c| errors << "capability #{c} has more than one owner in the batch" }

        slugs = entries.map { |e| e["slug"] }
        entries.each do |entry|
          capability = entry.dig("metadata", "capability")
          next if capability.blank?

          owner = seeded_skills.find { |s| s.metadata["capability"] == capability && !slugs.include?(s.slug) }
          errors << "#{entry['slug']}: capability #{capability} is already owned by #{owner.slug}" if owner
        end
        errors
      end

      # A seed only ever writes GLOBAL rows it owns. A slug held by a legacy
      # global row or by another owner's global row is a collision that fails
      # the batch; account-scoped rows never do (see #shadowing_warnings).
      def collision_errors(entries)
        slugs = entries.map { |e| e["slug"] }
        globals = ::Ai::Skill.global.where(slug: slugs).index_by(&:slug)

        entries.flat_map do |entry|
          slug = entry["slug"]
          errors = []
          if (row = globals[slug])
            meta = row.metadata.is_a?(Hash) ? row.metadata : {}
            if !Contract.applies_to?(meta)
              errors << "#{slug}: slug is taken by a legacy global skill (no capability); choose another slug"
            elsif meta["owner_repo"].to_s != owner_repo
              errors << "#{slug}: slug is owned by #{meta['owner_repo'].inspect}, not #{owner_repo}"
            end
          end
          errors
        end
      end

      # Account rows are never written by a seed (it writes GLOBAL rows only, and
      # slugs are unique per account), so they cannot block it. An account's
      # override of the global skill (cloned_from_id = the global row) is the
      # expected clone-on-evolve shape and says nothing. A tenant row that only
      # SHARES the slug, with no global origin, is reported: Ai::Skill.resolve_for
      # prefers it, so it shadows the global capability in that account.
      def shadowing_warnings(entries)
        slugs = entries.map { |e| e["slug"] }
        global_ids = ::Ai::Skill.global.where(slug: slugs).pluck(:slug, :id).to_h
        ::Ai::Skill.where(slug: slugs).where.not(account_id: nil).pluck(:slug, :cloned_from_id)
                   .reject { |slug, origin| origin.present? && origin == global_ids[slug] }
                   .group_by(&:first)
                   .map { |slug, rows| "#{slug}: #{rows.size} account-scoped row(s) share this slug with no global origin and shadow it in their account(s)" }
      end

      # ---- verbs ----------------------------------------------------------

      def verb_errors(entries)
        registered = ::Ai::Tools::PlatformApiToolRegistry.all_tools
        entries.flat_map do |entry|
          Array(entry.dig("metadata", "manifest", "verbs")).reject { |v| registered.key?(v.to_s) }
                                                           .map { |v| "#{entry['slug']}: manifest verb #{v} is not a registered platform tool" }
        end
      end

      # A `read` skill (read_only true, tied by the contract) is what a read-only
      # agent may be assembled with and what verb risk treats as calm, so it must
      # not name a verb that writes. Allowed despite `mutating: true`: the
      # contract's self-report verb and the probes THIS owner registered. A verb
      # with no declared action cannot be shown read-only, so it fails too; a
      # verb the registry does not know at all is left to verb_errors.
      def read_skill_errors(entries)
        entries.flat_map do |entry|
          ReadOnlyVerbs.errors(slug: entry["slug"], manifest: entry.dig("metadata", "manifest"), owner: owner_repo)
        end
      end

      # ---- relations ------------------------------------------------------

      def relation_errors(entries)
        batch = entries.index_by { |e| e["slug"] }
        seeded = seeded_skills.index_by(&:slug)
        errors = []
        entries.each do |entry|
          (entry.dig("metadata", "relations") || {}).each do |type, targets|
            Array(targets).each do |target|
              retired = retired_targets.key?(target) && !batch.key?(target)
              target_owner = retired ? retired_targets[target][:owner_repo] : relation_owner(target, batch, seeded)
              # Isolation first: a retired target is skipped only when the
              # relation would be allowed — otherwise re-activating it would
              # create a forbidden (e.g. core → extension) edge.
              if target_owner.nil?
                errors << "#{entry['slug']}: relations.#{type} target #{target} is not a seeded capability skill"
              elsif !relation_allowed?(target_owner)
                errors << "#{entry['slug']}: relations.#{type} target #{target} belongs to #{target_owner}, which #{owner_repo} may not reference"
              end
            end
          end
        end
        errors
      end

      # A relation to a capability skill an operator took out of service
      # (archived, inactive, draft) is skipped, not fatal: the seed must not
      # fail because a sibling was retired. The seeder creates no edge for it.
      def retired_relation_warnings(entries)
        batch = entries.map { |e| e["slug"] }
        entries.flat_map do |entry|
          (entry.dig("metadata", "relations") || {}).flat_map do |type, targets|
            Array(targets).select { |t| retired_targets.key?(t) && !batch.include?(t) && relation_allowed?(retired_targets[t][:owner_repo]) }
                          .map { |t| "#{entry['slug']}: #{type} #{t} skipped: target is #{retired_targets[t][:status]}" }
          end
        end
      end

      # slug => { status:, owner_repo: } of global capability rows that are not active.
      def retired_targets
        @retired_targets ||= ::Ai::Skill.global.where.not(status: "active").where("ai_skills.metadata ? 'capability'")
                                        .pluck(:slug, :status, Arel.sql("ai_skills.metadata->>'owner_repo'"))
                                        .to_h { |slug, status, owner| [ slug, { status: status, owner_repo: owner.to_s } ] }
      end

      def relation_owner(target, batch, seeded)
        return owner_repo if batch.key?(target)
        return seeded[target].metadata["owner_repo"].to_s if seeded.key?(target)
        return @pending[target].dig("metadata", "owner_repo").to_s if @pending.key?(target)

        nil
      end

      def relation_allowed?(target_owner)
        return Contract.core_owner?(target_owner) if Contract.core_owner?(owner_repo)

        Contract.core_owner?(target_owner) || target_owner == owner_repo
      end

      # ---- purity ---------------------------------------------------------

      def purity_errors(entries)
        own_slug = Contract.core_owner?(owner_repo) ? nil : owner_repo.delete_prefix("extensions/")
        foreign = extension_slugs - [ own_slug ]
        return [] if foreign.empty?

        prefixes = foreign.map { |s| "#{s.tr('-', '_')}_" }
        foreign_verbs = ::Ai::Tools::PlatformApiToolRegistry.all_tools.keys.select { |k| k.start_with?(*prefixes) }
        foreign_skills = seeded_skills.reject { |s| [ Contract::CORE_OWNER, owner_repo ].include?(s.metadata["owner_repo"].to_s) }.map(&:slug)

        entries.flat_map { |entry| entry_purity_errors(entry, prefixes, foreign, foreign_verbs, foreign_skills) }
      end

      def entry_purity_errors(entry, prefixes, foreign, foreign_verbs, foreign_skills)
        slug = entry["slug"]
        verbs = Array(entry.dig("metadata", "manifest", "verbs"))
        errors = verbs.select { |v| v.start_with?(*prefixes) }.map { |v| "#{slug}: names another owner's verb #{v} (purity)" }

        text = Contract.authored_text(entry)
        words = text.scan(/[a-z0-9_]+/).to_set
        (foreign_verbs.select { |v| words.include?(v) } - verbs).each { |v| errors << "#{slug}: text names another owner's verb #{v} (purity)" }
        foreign.each { |ext| errors << "#{slug}: text names the path extensions/#{ext} (purity)" if text.include?("extensions/#{ext}") }
        foreign_skills.each do |other|
          errors << "#{slug}: text names another owner's skill #{other} (purity)" if text.match?(slug_pattern(other))
        end
        errors
      end

      # Every extension this install knows of, loaded or merely present on disk —
      # so a core seed is checked even when an extension is disabled.
      def extension_slugs
        @extension_slugs ||= (Array(::Powernode::ExtensionRegistry.slugs).map(&:to_s) | extension_dirs).reject(&:blank?).uniq
      end

      def extension_dirs
        root = Rails.root.join("..", "extensions")
        return [] unless root.directory?

        root.children.select(&:directory?).flat_map do |dir|
          next [ dir.basename.to_s ] unless dir.basename.to_s == "private"

          dir.children.select(&:directory?).map { |d| d.basename.to_s }
        end
      end

      # ---- similarity -----------------------------------------------------

      def similarity_errors(entries)
        batch_slugs = entries.map { |e| e["slug"] }
        errors = []
        pairs(entries).each do |pair|
          case pair[:band]
          when "duplicate"
            errors << "#{pair[:a]}: duplicates #{pair[:b]} (similarity #{pair[:similarity].round(3)})"
          when "overlapping"
            [ [ pair[:a], pair[:b], pair[:a_names_b] ], [ pair[:b], pair[:a], pair[:b_names_a] ] ].each do |slug, other, named|
              next if named || !batch_slugs.include?(slug)

              errors << "#{slug}: overlaps #{other} (similarity #{pair[:similarity].round(3)}); triggers.not_for must name #{other}"
            end
          end
        end
        errors
      end

      # Each unordered same-domain pair once, where at least one side is in the
      # batch. Already-seeded siblings (not in the batch) are compared against.
      def pairs(entries)
        batch_slugs = entries.map { |e| e["slug"] }
        siblings = seeded_skills.reject { |s| batch_slugs.include?(s.slug) }
        pool = entries.map { |e| { slug: e["slug"], domain: e.dig("metadata", "domain"), text: embedding_text(e), not_for: not_for_of(e["metadata"]) } } +
               siblings.map { |s| { slug: s.slug, domain: s.metadata["domain"], text: ::Ai::SkillGraph::BridgeService.embedding_text_for(s), not_for: not_for_of(s.metadata) } }
        vectors = embedder.embed_all(pool.to_h { |p| [ p[:slug], p[:text] ] })

        result = []
        pool.each_with_index do |a, i|
          pool[(i + 1)..].each do |b|
            next unless a[:domain] == b[:domain]
            next unless batch_slugs.include?(a[:slug]) || batch_slugs.include?(b[:slug])

            similarity = LexicalEmbedder.cosine(vectors[a[:slug]], vectors[b[:slug]])
            band = ::Ai::SkillGraph::ConflictDetectionService.classify_similarity(similarity)
            result << {
              a: a[:slug], b: b[:slug], domain: a[:domain], similarity: similarity, band: band,
              margin: margin_for(similarity),
              a_names_b: a[:not_for].match?(slug_pattern(b[:slug])), b_names_a: b[:not_for].match?(slug_pattern(a[:slug]))
            }
          end
        end
        result
      end

      def margin_for(similarity)
        dup = ::Ai::SkillGraph::ConflictDetectionService::DUPLICATE_THRESHOLD
        overlap = ::Ai::SkillGraph::ConflictDetectionService::OVERLAP_THRESHOLD_LOW
        boundary = similarity >= overlap ? dup : overlap
        (boundary - similarity).round(4)
      end

      def not_for_of(metadata)
        Array(metadata.is_a?(Hash) ? metadata.dig("triggers", "not_for") : nil).join("\n")
      end

      def slug_pattern(slug)
        Regexp.new(format(SLUG_BOUNDARY, Regexp.escape(slug)))
      end

      def embedding_text(entry)
        ::Ai::SkillGraph::BridgeService.embedding_text_for(::Ai::Skill.new(entry.slice("name", "description", "category", "tags", "metadata")))
      end

      # Active global capability skills already seeded (any owner).
      def seeded_skills
        @seeded_skills ||= ::Ai::Skill.global.active.where("ai_skills.metadata ? 'capability'").to_a
      end

      def dupes(list)
        list.compact.tally.select { |_, n| n > 1 }.keys
      end
    end
  end
end
