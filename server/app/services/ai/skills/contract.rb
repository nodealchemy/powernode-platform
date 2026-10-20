# frozen_string_literal: true

module Ai
  module Skills
    # The authoring contract for a CAPABILITY skill — the one selectable skill
    # kind. A capability skill names its verbs (tools) in `manifest.verbs`; there
    # is no separate verb kind. Everything the contract governs lives in the
    # skill's `metadata` jsonb (no dedicated columns), so the deploy image stays
    # migration-free:
    #
    #   domain, capability, owner_repo,
    #   triggers { use_when[], not_for[], keywords[], applies_to[], stages[] },
    #   manifest { verbs[], knowledge_tags[], gate_category, read_only },
    #   hints    { min_tier, effort, long_context, tool_heavy, safety_critical },
    #   relations{ requires[], composes[], refines[] },
    #   evals    [ { task, expect_selected, project_kind? } ] (at least MIN_EVALS
    #            positives; project_kind is the facet the selecting agent would
    #            pass for that task, when the task belongs to a known project)
    #
    # plus the column-level limits: description <= MAX_DESCRIPTION chars starting
    # "Use when", system_prompt <= MAX_PROMPT_TOKENS (procedure/checklists only,
    # no ids). The contract applies to every row whose metadata declares a
    # `capability` (Ai::Skill validates it at save) and to every seeded batch
    # (Ai::Skills::SeedGate). Legacy rows that declare no capability are outside
    # it until they are retired.
    #
    # Pure: no database or extension knowledge. Extension domains are registered
    # by the extension's engine at boot (register_domains), the same seam shape as
    # Ai::Skill.register_categories, so core never names them.
    module Contract
      CORE_OWNER = "core"
      EXTENSION_OWNER_PATTERN = %r{\Aextensions/[a-z0-9][a-z0-9_-]*\z}

      # Core's taxonomy. Generic domains serve any project the platform builds or
      # runs; `powernode-platform-dev` holds the conventions of this repository
      # only. websites/web-apps/mobile-apps are project-type domains reserved for
      # skills not all authored yet.
      CORE_DOMAINS = %w[
        front-door external-agent-session knowledge review
        software-engineering powernode-platform-dev
        websites web-apps mobile-apps
      ].freeze
      PLATFORM_DEV_DOMAIN = "powernode-platform-dev"

      # Project facet: which kind of work a skill applies to. `powernode-platform`
      # is the platform's own repository; a skill that does not list it must not
      # carry this repo's paths or conventions (see #repo_marker_errors).
      PROJECT_KINDS = %w[any powernode-platform software website web-app mobile-app infrastructure].freeze
      PLATFORM_PROJECT_KIND = "powernode-platform"

      # Lifecycle facet: the stage of a project's life the skill serves, so
      # selection can pick per step and hand off between build and deploy.
      STAGES = %w[plan build test release provision deploy expose network operate].freeze

      GATE_CATEGORIES = %w[read propose mutate destructive].freeze
      RELATION_TYPES = %w[requires composes refines].freeze
      HINT_BOOLEANS = %w[long_context tool_heavy safety_critical].freeze

      MAX_DESCRIPTION = 200
      DESCRIPTION_PREFIX = "Use when"
      MAX_PROMPT_TOKENS = 1_200
      MIN_EVALS = 2
      SLUG_PATTERN = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

      # Ids never belong in a skill prompt: they are deployment- or moment-local
      # and rot. UUIDs, improvement ids, IPv4 addresses and commit-sha-shaped hex.
      ID_PATTERNS = {
        "a UUID" => /\b\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\b/,
        "an improvement id" => /\bIMP-\h{6,}\b/i,
        "an IPv4 address" => /\b(?:\d{1,3}\.){3}\d{1,3}\b/,
        "a commit sha" => /\b(?=[0-9a-f]*\d)(?=[0-9a-f]*[a-f])[0-9a-f]{12,40}\b/
      }.freeze

      # Paths and conventions of THIS repository. A skill that does not apply to
      # the powernode-platform project kind is generic and must not carry them.
      REPO_MARKERS = %r{
        (?:\A|[\s`'"(])(?:server|frontend|worker|extensions|scripts|docs)/ |
        \.claude/ | CLAUDE\.md | rails_helper | \bwt\.sh\b | validate\.sh | pattern-validation |
        parallel-rspec\.sh | prepare-worktree\.sh | test-pg-tmpfs\.sh | test-redis\.sh
      }x

      # Verbs a gate_category-read skill may name although their declaration is
      # `mutating: true`. Explicit and short on purpose: the self-report verb every
      # agent ends a run with records history and acts on nothing. An extension
      # adds its own approval-parking, read-only probes through
      # register_read_probe_verbs (core never names them).
      READ_SKILL_MUTATING_VERBS = %w[record_agent_execution].freeze

      @registered_domains = {}
      @read_probe_verbs = {}
      @registry_mutex = Mutex.new

      class << self
        # Extension engines call this at boot with their owner id
        # ("extensions/<slug>") and their capability domains. Idempotent.
        def register_domains(owner:, domains:)
          @registry_mutex.synchronize do
            @registered_domains[owner.to_s] = (Array(@registered_domains[owner.to_s]) | Array(domains).map(&:to_s)).freeze
          end
        end

        # Extension engines register the read-only, approval-parking probe verbs a
        # `read` skill of theirs may name. Idempotent; an empty list clears the owner.
        def register_read_probe_verbs(owner:, verbs:)
          @registry_mutex.synchronize do
            @read_probe_verbs[owner.to_s] = Array(verbs).map(&:to_s).freeze
          end
        end

        # @return [Array<String>] every verb a read skill may name despite `mutating: true`
        def read_probe_verbs
          @registry_mutex.synchronize { @read_probe_verbs.values.flatten.uniq + READ_SKILL_MUTATING_VERBS }
        end

        def domains_for(owner)
          return CORE_DOMAINS if owner.to_s == CORE_OWNER

          @registry_mutex.synchronize { Array(@registered_domains[owner.to_s]).dup }
        end

        def registered_owners
          @registry_mutex.synchronize { @registered_domains.keys.dup }
        end

        def owner_of_domain(domain)
          return CORE_OWNER if CORE_DOMAINS.include?(domain.to_s)

          @registry_mutex.synchronize { @registered_domains.find { |_, list| list.include?(domain.to_s) }&.first }
        end

        def core_owner?(owner)
          owner.to_s == CORE_OWNER
        end

        # Same estimate the skill traversal uses for its token budget.
        def estimate_tokens(text)
          (text.to_s.length / 4.0).ceil
        end

        # A row is under the contract when its metadata declares a capability.
        def applies_to?(metadata)
          metadata.is_a?(Hash) && metadata.key?("capability")
        end

        # Errors (strings) for one skill. `attrs` carries slug, name, description,
        # system_prompt and metadata (string keys). Empty when conforming.
        #
        # lenient_unregistered_owner: true skips the domain check when the
        # owner is an extension that registered NO domains — it is disabled on
        # this install, so its rows must stay saveable (the model's save path);
        # the seed gate is always strict.
        def validate(attrs, lenient_unregistered_owner: false)
          attrs = attrs.to_h.transform_keys(&:to_s)
          meta = attrs["metadata"].is_a?(Hash) ? attrs["metadata"] : {}
          slug = attrs["slug"].to_s
          errors = []

          errors << "slug #{slug.inspect} must be kebab-case" unless slug.match?(SLUG_PATTERN)
          errors.concat(description_errors(attrs["description"]))
          errors.concat(prompt_errors(attrs["system_prompt"]))
          errors.concat(identity_errors(meta, lenient_unregistered_owner))
          errors.concat(trigger_errors(meta["triggers"]))
          errors.concat(manifest_errors(meta["manifest"]))
          errors.concat(hint_errors(meta["hints"]))
          errors.concat(relation_errors(meta["relations"], slug))
          errors.concat(eval_errors(meta["evals"]))
          errors.concat(facet_consistency_errors(meta, attrs))
          errors.map { |e| "#{slug.presence || '(no slug)'}: #{e}" }
        end

        # The text a skill is judged by for purity and repo-marker checks.
        def authored_text(attrs)
          attrs = attrs.to_h.transform_keys(&:to_s)
          triggers = (attrs.dig("metadata", "triggers") || {})
          [
            attrs["name"], attrs["description"], attrs["system_prompt"],
            *Array(triggers["use_when"]), *Array(triggers["not_for"]), *Array(triggers["keywords"])
          ].compact.join("\n")
        end

        private

        def description_errors(description)
          text = description.to_s
          errors = []
          errors << "description is required" if text.strip.empty?
          errors << "description is #{text.length} chars (max #{MAX_DESCRIPTION})" if text.length > MAX_DESCRIPTION
          errors << "description must start with \"#{DESCRIPTION_PREFIX}\"" unless text.start_with?(DESCRIPTION_PREFIX)
          errors
        end

        def prompt_errors(prompt)
          text = prompt.to_s
          return [ "system_prompt is required" ] if text.strip.empty?

          errors = []
          tokens = estimate_tokens(text)
          errors << "system_prompt is ~#{tokens} tokens (max #{MAX_PROMPT_TOKENS})" if tokens > MAX_PROMPT_TOKENS
          # Procedure/checklist shape: at least one numbered step or bullet.
          errors << "system_prompt must be a procedure or checklist (numbered steps or bullets)" unless text.match?(/^\s*(?:\d+[.)]|[-*])\s+\S/)
          ID_PATTERNS.each { |label, pattern| errors << "system_prompt contains #{label}" if text.match?(pattern) }
          errors
        end

        def identity_errors(meta, lenient_unregistered_owner = false)
          errors = []
          owner = meta["owner_repo"].to_s
          domain = meta["domain"].to_s
          capability = meta["capability"].to_s

          errors << "capability must be kebab-case" unless capability.match?(SLUG_PATTERN)
          extension_owner = owner.match?(EXTENSION_OWNER_PATTERN)
          # A disabled extension's domains are unknown here, not wrong.
          domain_unknowable = extension_owner && lenient_unregistered_owner && !registered_owners.include?(owner)
          if owner == CORE_OWNER || extension_owner
            allowed = domains_for(owner)
            unless domain_unknowable || allowed.include?(domain)
              errors << "domain #{domain.inspect} is not a #{owner} domain (#{allowed.join(', ').presence || 'none registered'})"
            end
          else
            errors << "owner_repo #{owner.inspect} must be \"core\" or \"extensions/<slug>\""
          end
          errors
        end

        def trigger_errors(triggers)
          return [ "triggers must be an object" ] unless triggers.is_a?(Hash)

          errors = []
          %w[use_when keywords].each do |key|
            errors << "triggers.#{key} must be a non-empty list of strings" unless string_list?(triggers[key], allow_empty: false)
          end
          errors << "triggers.not_for must be a list of strings" unless string_list?(triggers["not_for"])
          errors.concat(enum_list_errors(triggers, "applies_to", PROJECT_KINDS, required: true))
          errors.concat(enum_list_errors(triggers, "stages", STAGES, required: false))
          unknown = triggers.keys - %w[use_when not_for keywords applies_to stages]
          errors << "triggers has unknown keys #{unknown.join(', ')}" if unknown.any?
          errors
        end

        def manifest_errors(manifest)
          return [ "manifest must be an object" ] unless manifest.is_a?(Hash)

          errors = []
          errors << "manifest.verbs must be a list of verb names" unless string_list?(manifest["verbs"]) &&
                                                                       Array(manifest["verbs"]).all? { |v| v.match?(/\A[a-z][a-z0-9_]*\z/) }
          errors << "manifest.knowledge_tags must be a list of strings" unless string_list?(manifest["knowledge_tags"])
          unless GATE_CATEGORIES.include?(manifest["gate_category"])
            errors << "manifest.gate_category must be one of #{GATE_CATEGORIES.join(', ')}"
          end
          if [ true, false ].include?(manifest["read_only"])
            if manifest["read_only"] != (manifest["gate_category"] == "read")
              errors << "manifest.read_only must be true exactly when gate_category is read"
            end
          else
            errors << "manifest.read_only must be a boolean"
          end
          errors
        end

        def hint_errors(hints)
          return [ "hints must be an object" ] unless hints.is_a?(Hash)

          errors = []
          tiers = ::Ai::ModelTiers::ORDER.map(&:to_s)
          errors << "hints.min_tier must be one of #{tiers.join(', ')}" unless tiers.include?(hints["min_tier"])
          efforts = ::Ai::Routing::EffortMapper::VALID_EFFORTS
          errors << "hints.effort must be one of #{efforts.join(', ')}" unless efforts.include?(hints["effort"])
          HINT_BOOLEANS.each do |key|
            errors << "hints.#{key} must be a boolean" unless [ true, false ].include?(hints[key])
          end
          errors
        end

        def relation_errors(relations, slug)
          return [] if relations.nil?
          return [ "relations must be an object" ] unless relations.is_a?(Hash)

          errors = []
          unknown = relations.keys - RELATION_TYPES
          errors << "relations has unsupported types #{unknown.join(', ')} (allowed: #{RELATION_TYPES.join(', ')})" if unknown.any?
          RELATION_TYPES.each do |type|
            next if relations[type].nil?

            unless string_list?(relations[type]) && relations[type].all? { |t| t.match?(SLUG_PATTERN) }
              errors << "relations.#{type} must be a list of skill slugs"
              next
            end
            errors << "relations.#{type} must not name the skill itself" if relations[type].include?(slug)
          end
          errors << "a skill refines at most one parent" if Array(relations["refines"]).size > 1
          errors
        end

        def eval_errors(evals)
          return [ "evals must be a list of at least #{MIN_EVALS}" ] unless evals.is_a?(Array) && evals.size >= MIN_EVALS

          errors = []
          evals.each_with_index do |ev, idx|
            unless ev.is_a?(Hash) && ev["task"].is_a?(String) && ev["task"].strip.present? && [ true, false ].include?(ev["expect_selected"])
              errors << "evals[#{idx}] must be { task: String, expect_selected: Boolean }"
            end
            if ev.is_a?(Hash) && ev.key?("project_kind") && !PROJECT_KINDS.include?(ev["project_kind"])
              errors << "evals[#{idx}].project_kind must be one of #{PROJECT_KINDS.join(', ')}"
            end
          end
          positives = evals.count { |ev| ev.is_a?(Hash) && ev["expect_selected"] == true }
          errors << "evals need at least #{MIN_EVALS} tasks with expect_selected: true" if positives < MIN_EVALS
          errors
        end

        def facet_consistency_errors(meta, attrs)
          applies = Array(meta.dig("triggers", "applies_to"))
          errors = []
          if meta["domain"] == PLATFORM_DEV_DOMAIN && applies != [ PLATFORM_PROJECT_KIND ]
            errors << "a #{PLATFORM_DEV_DOMAIN} skill must apply to exactly [#{PLATFORM_PROJECT_KIND}]"
          end
          if applies.include?(PLATFORM_PROJECT_KIND) && meta["domain"] != PLATFORM_DEV_DOMAIN
            errors << "only #{PLATFORM_DEV_DOMAIN} skills may apply to #{PLATFORM_PROJECT_KIND}"
          end
          errors.concat(repo_marker_errors(attrs)) unless applies.include?(PLATFORM_PROJECT_KIND)
          errors
        end

        def repo_marker_errors(attrs)
          hits = authored_text(attrs).scan(REPO_MARKERS).map { |m| m.to_s.strip }.uniq
          return [] if hits.empty?

          [ "a generic skill must not carry this repository's paths or conventions (found #{hits.first(3).join(', ')})" ]
        end

        def enum_list_errors(hash, key, allowed, required:)
          value = hash[key]
          return (required ? [ "triggers.#{key} is required (one or more of #{allowed.join(', ')})" ] : []) if value.nil?
          return [ "triggers.#{key} must be a non-empty list of #{allowed.join(', ')}" ] unless string_list?(value, allow_empty: false)

          bad = value - allowed
          bad.any? ? [ "triggers.#{key} has unknown values #{bad.join(', ')}" ] : []
        end

        def string_list?(value, allow_empty: true)
          value.is_a?(Array) && (allow_empty || value.any?) && value.all? { |v| v.is_a?(String) && v.strip.present? }
        end
      end
    end
  end
end
