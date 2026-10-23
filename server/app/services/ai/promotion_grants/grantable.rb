# frozen_string_literal: true

module Ai
  module PromotionGrants
    # WHICH gated categories a promotion grant may name: the operator's list
    # (SiteSetting SETTING_KEY, a protected key: only the human-only
    # site_setting_set_protected verb writes it), less the HARD exclusions
    # below, which no setting can lift. With the setting unset, or not a list
    # of strings, the list is DEFAULT_CATEGORIES (fail closed: never "none
    # excluded", never "everything").
    #
    # A category on the list is still only issuable when an installed
    # extension's catalog answers for it (Ai::PromotionGrants::Catalog); this
    # module decides what MAY be granted, the catalog what CAN be.
    #
    # The hard exclusions are the reasons a request needs a person that a
    # grant must never answer:
    #   * a destructive category (Ai::Approvals::HumanSessionPolicy::
    #     DESTRUCTIVE_CATEGORY_PATTERNS);
    #   * the category of any declared tool action that is human_only or
    #     destructive, read from the declarations themselves, so an
    #     extension's verbs are covered without core naming them;
    #   * key and secret operations (rotation, reveal), the kill switch,
    #     site-setting writes (the protected ones above all: this very list is
    #     one), intervention-policy writes, and promotion grants themselves.
    module Grantable
      SETTING_KEY = "ai_promotion_grant_categories"
      DEFAULT_CATEGORIES = %w[release.promote].freeze

      HARD_EXCLUDED_PATTERNS = [
        *::Ai::Approvals::HumanSessionPolicy::DESTRUCTIVE_CATEGORY_PATTERNS,
        # key material
        "*key*rotate*", "*rotate*key*", "*reveal*", "*secret*", "*credential*",
        # the kill switch
        "*kill_switch*", "*emergency_halt*", "*emergency_resume*",
        # the control plane's authority over itself
        "platform.site_setting.*", "*site_setting*", "ai.intervention_policy.*", "*promotion_grant*",
        "ai.delegation_policy.*"
      ].freeze

      module_function

      # The categories a grant may name right now, in the operator's order.
      def categories
        configured.reject { |category| hard_excluded?(category) }
      end

      def grantable?(category)
        category = category.to_s
        return false if category.blank?

        configured.include?(category) && !hard_excluded?(category)
      end

      # True whatever the setting says.
      def hard_excluded?(category)
        category = category.to_s
        return true if category.blank?
        return true if HARD_EXCLUDED_PATTERNS.any? { |pattern| File.fnmatch?(pattern, category) }

        declared_person_only_categories.include?(category)
      end

      def configured
        value = ::SiteSetting.get(SETTING_KEY)
        return value.map(&:to_s).uniq if value.is_a?(Array) && value.all?(String)

        DEFAULT_CATEGORIES
      end

      # Every action_category a registered tool declares human_only or
      # destructive. Not memoized: an extension engine can register a tool
      # after boot, and the answer must follow it.
      def declared_person_only_categories
        ::Ai::Tools::PlatformApiToolRegistry.all_tools.values.uniq.each_with_object(Set.new) do |class_name, found|
          klass = class_name.to_s.safe_constantize
          next unless klass.respond_to?(:declared_actions)

          klass.declared_actions.each_value do |declaration|
            next unless declaration[:human_only] || declaration[:destructive]

            found << declaration[:action_category].to_s if declaration[:action_category].present?
          end
        end
      end
    end
  end
end
