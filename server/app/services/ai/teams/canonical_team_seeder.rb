# frozen_string_literal: true

module Ai
  module Teams
    # Writes a CANONICAL team template (HIER-P4): a global, is_system,
    # source_key-managed Ai::TeamTemplate whose role_definitions name canonical
    # agents by slug — the NODES and ROLES of a team graph. The EDGES are the
    # delegation policies and lineage edges the hierarchy seeds write through
    # Ai::Agents::HierarchyWriter; the RUN is an Ai::TeamExecution driven by
    # Ai::TeamStrategies::HierarchicalStrategy (the proposal's Phase 4 wording
    # says "DagExecution", but nothing on the team path creates one — the only
    # writer of Ai::DagExecution is Ai::A2a::DagExecutor). No new model
    # (operator ruling: a graph = TeamTemplate + delegation policies + the
    # execution row its strategy writes).
    #
    # ONE writer for the template shape, called by the core seed
    # (db/seeds/ai_canonical_teams_seed.rb — "Platform Engineering") and by the
    # system extension's seed ("System Operations"), so both templates carry the
    # same definition keys and Ai::Teams::CanonicalTeamReconciler reads one
    # vocabulary. Idempotent: a re-run with the same members changes nothing.
    #
    # The canonical rule for templates mirrors ruling 5 for agents: a seed never
    # adopts an ACCOUNT-scoped template as the canonical. TeamTemplate#slug is
    # unique across accounts, so a stray with this slug is a hard conflict —
    # raised, never silently converted.
    class CanonicalTeamSeeder
      class CanonicalTemplateConflict < StandardError; end

      TOPOLOGY = "hierarchical"
      DEFAULT_CONFIG = {
        "team_type"             => "hierarchical",
        "coordination_strategy" => "manager_led",
        "communication_pattern" => "hub_spoke"
      }.freeze

      # One structure, three views — recorded on the template so a reader of
      # the row (the Teams page, the Platform Architect designing a graph) is
      # told where each view lives.
      WORKFLOW_PATTERN = {
        "strategy" => "manager_led",
        "nodes"    => "role_definitions (agent_slug → canonical agent)",
        "edges"    => "Ai::DelegationPolicy of the manager + Ai::AgentLineage manager→member",
        "run"      => "Ai::TeamExecution via Ai::TeamStrategies::HierarchicalStrategy"
      }.freeze

      # WHERE a template is materialised (APO app-5). "account" is the original
      # and the default: Ai::Teams::CanonicalTeamReconciler.reconcile_all! walks
      # every canonical template and gives the account one team per template.
      # "per_project" says the opposite — this template is materialised once per
      # Ai::Project, by Ai::Projects::TeamProvisioner, and the account-level
      # walk must SKIP it.
      #
      # Without the marker a per-project template would be swept up by the boot
      # reconcile: every reconcilable account would silently acquire a team and
      # a clone per seat that nothing asked for, and `drift` would report its
      # absent account-level team as drift forever — a permanent false signal
      # that no reconcile could ever clear.
      MATERIALISATION_KEY     = "materialisation"
      MATERIALISATION_ACCOUNT = "account"
      MATERIALISATION_PROJECT = "per_project"
      MATERIALISATIONS = [ MATERIALISATION_ACCOUNT, MATERIALISATION_PROJECT ].freeze

      # members: [{ slug:, name:, role:, lead: true|false, description:, capabilities: [] }, ...]
      # exactly one entry is the lead and it carries role "manager".
      def self.seed!(slug:, name:, description:, members:, category: "platform", tags: [],
                     materialisation: MATERIALISATION_ACCOUNT)
        new(slug: slug, name: name, description: description, members: members,
            category: category, tags: tags, materialisation: materialisation).seed!
      end

      def initialize(slug:, name:, description:, members:, category:, tags:,
                     materialisation: MATERIALISATION_ACCOUNT)
        @slug = slug.to_s
        @name = name
        @description = description
        @members = Array(members).map { |m| m.to_h.symbolize_keys }
        @category = category
        @tags = Array(tags)
        @materialisation = materialisation.to_s
        unless MATERIALISATIONS.include?(@materialisation)
          raise ArgumentError, "materialisation #{materialisation.inspect} is not one of #{MATERIALISATIONS.join(', ')}"
        end

        validate_members!
      end

      def seed!
        refuse_stray!
        template = ::Ai::TeamTemplate.find_or_initialize_global(slug: @slug, source_key: @slug)
        template.assign_attributes(
          name: @name,
          description: @description,
          category: @category,
          tags: @tags,
          team_topology: TOPOLOGY,
          role_definitions: role_definitions,
          default_config: (template.default_config || {})
                            .merge(DEFAULT_CONFIG)
                            .merge(MATERIALISATION_KEY => @materialisation),
          workflow_pattern: WORKFLOW_PATTERN,
          is_public: true
        )
        template.published_at ||= Time.current
        template.save! if template.new_record? || template.changed?
        template
      end

      private

      def validate_members!
        raise ArgumentError, "a canonical team needs members" if @members.empty?

        leads = @members.select { |m| m[:lead] == true }
        raise ArgumentError, "a canonical team needs exactly one lead (got #{leads.size})" unless leads.size == 1
        raise ArgumentError, "the lead must carry role \"manager\"" unless leads.first[:role].to_s == "manager"

        @members.each do |m|
          raise ArgumentError, "member #{m.inspect} needs a slug" if m[:slug].blank?
          raise ArgumentError, "member #{m[:slug]} needs a name" if m[:name].blank?
          unless ::Ai::AgentTeamMember::ROLES.include?(m[:role].to_s)
            raise ArgumentError, "member #{m[:slug]}: role #{m[:role].inspect} is not one of " \
                                 "#{::Ai::AgentTeamMember::ROLES.join(', ')}"
          end
        end

        slugs = @members.map { |m| m[:slug].to_s }
        raise ArgumentError, "duplicate member slugs: #{slugs.tally.select { |_, n| n > 1 }.keys.join(', ')}" if slugs.uniq.size != slugs.size
      end

      def refuse_stray!
        stray = ::Ai::TeamTemplate.account_scoped.find_by(slug: @slug)
        return unless stray

        raise CanonicalTemplateConflict,
              "refusing to seed canonical team template #{@slug.inspect}: an ACCOUNT-scoped template with " \
              "that slug already exists — id=#{stray.id} account_id=#{stray.account_id}. Seeds never adopt " \
              "an account template as the canonical; rename or remove that row, then re-run the seed."
      end

      # The shape TeamTemplate#create_team! (the clone-to-customise path) reads
      # — name / type / description / capabilities / priority / can_delegate —
      # plus the canonical binding the reconciler reads: agent_slug,
      # member_role, is_lead.
      def role_definitions
        @members.each_with_index.map do |m, index|
          role = m[:role].to_s
          lead = m[:lead] == true
          {
            "name"         => m[:name],
            "type"         => ::Ai::AgentTeamMember.role_type_for(role),
            "agent_slug"   => m[:slug].to_s,
            "member_role"  => role,
            "is_lead"      => lead,
            "priority"     => index,
            "description"  => m[:description],
            "capabilities" => Array(m[:capabilities]),
            "can_delegate" => lead,
            "can_escalate" => true
          }
        end
      end
    end
  end
end
