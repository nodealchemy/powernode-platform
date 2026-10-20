# frozen_string_literal: true

module Ai
  module Skills
    # Selection rules over capability-skill metadata, shared by discovery
    # (Ai::SkillGraph::TraversalService) and the eval runner so both rank alike.
    module SelectionFacets
      # A project kind also satisfies skills written for its broader kind: the
      # platform's own repository is software, so generic software skills apply
      # to it as well as its powernode-platform refinements.
      BROADER_KINDS = { "powernode-platform" => %w[software] }.freeze

      module_function

      def metadata_of(skill_or_meta)
        meta = skill_or_meta.respond_to?(:metadata) ? skill_or_meta.metadata : skill_or_meta
        meta.is_a?(Hash) ? meta : {}
      end

      # Does a skill apply to the project kind? Legacy rows (no contract) and a
      # nil kind always pass.
      def applies?(skill_or_meta, project_kind)
        meta = metadata_of(skill_or_meta)
        return true if project_kind.nil? || !Contract.applies_to?(meta)

        applies = Array(meta.dig("triggers", "applies_to"))
        applies.include?("any") || ([ project_kind, *BROADER_KINDS[project_kind] ] & applies).any?
      end

      # True when the skill names the project kind itself (not via "any" or a
      # broader kind) — the specific skill for that project.
      def specific_to?(skill_or_meta, project_kind)
        project_kind.present? && Array(metadata_of(skill_or_meta).dig("triggers", "applies_to")).include?(project_kind)
      end

      def refines(skill_or_meta)
        Array(metadata_of(skill_or_meta).dig("relations", "refines"))
      end

      # "refines: the child wins when its trigger matches" — a parent and its
      # refining child never both stand in one result. When the caller names a
      # project kind the child is specific to, the child replaces the parent;
      # otherwise whichever ranks higher stays and the other is dropped.
      #
      # @param ranked [Array] items in rank order
      # @yieldparam item → [slug, metadata]
      # @return [Array] ranked items with the losing side of each pair removed
      def resolve_refinements(ranked, project_kind)
        slugs = ranked.map { |item| yield(item).first }
        drop = Set.new
        ranked.each_with_index do |item, child_rank|
          slug, meta = yield(item)
          refines(meta).each do |parent|
            parent_rank = slugs.index(parent)
            next if parent_rank.nil?

            if specific_to?(meta, project_kind) || child_rank < parent_rank
              drop << parent
            else
              drop << slug
            end
          end
        end
        ranked.reject { |item| drop.include?(yield(item).first) }
      end
    end
  end
end
