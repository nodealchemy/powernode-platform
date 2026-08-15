# frozen_string_literal: true

module Ai
  class InterventionPolicy < ApplicationRecord
    self.table_name = "ai_intervention_policies"

    SCOPES = %w[global agent action_type].freeze
    POLICIES = %w[auto_approve notify_and_proceed require_approval silent block].freeze

    # Static categories owned by core. Extensions append at boot via
    # `Ai::InterventionPolicy.register_category!("ext.action_name")` from
    # their Engine#after_initialize. The registry is thread-safe at boot
    # (single-threaded init); reads are lock-free at request time.
    STATIC_CATEGORIES = %w[
      approval proposal escalation status_update issue_alert
      feedback
      project.adapt project.cost_control project.scale_horizontal project.relocate project.schema_change project.security_change
      dev.pull_task dev.complete_task dev.commit_to_branch
      dev.multi_file_change dev.merge
      *
    ].freeze

    @category_registry = Set.new(STATIC_CATEGORIES)
    @category_registry_mutex = Mutex.new

    class << self
      # Register an action category at boot. Called from extension Engines'
      # `after_initialize` blocks. Idempotent — calling twice with the same
      # name is a no-op. Returns the category name.
      def register_category!(name)
        return name unless name.is_a?(String) && !name.strip.empty?

        @category_registry_mutex.synchronize { @category_registry << name }
        name
      end

      def register_categories!(names)
        names.each { |n| register_category!(n) }
      end

      def category_registered?(name)
        @category_registry.include?(name)
      end

      def registered_categories
        @category_registry.to_a.sort
      end
    end

    # Associations
    belongs_to :account
    belongs_to :user, optional: true
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id", optional: true
    belongs_to :approval_chain, class_name: "Ai::ApprovalChain", optional: true

    # Validations
    validates :scope, presence: true, inclusion: { in: SCOPES }
    validates :action_category, presence: true
    validates :policy, presence: true, inclusion: { in: POLICIES }
    validates :priority, presence: true, numericality: { only_integer: true }

    # JSON columns
    attribute :conditions, :json, default: -> { {} }
    attribute :preferred_channels, :json, default: -> { [] }

    # Scopes
    scope :active, -> { where(is_active: true) }
    scope :for_account, ->(account_id) { where(account_id: account_id) }
    scope :for_user, ->(user_id) { where(user_id: user_id) }
    scope :for_agent, ->(agent_id) { where(ai_agent_id: agent_id) }
    scope :for_category, ->(category) { where(action_category: [category, "*"]) }
    scope :by_specificity, -> { order(priority: :desc) }

    # Instance methods
    def matches?(action_category:, agent: nil, user: nil)
      return false unless is_active?
      return false unless action_category_matches?(action_category)
      return false unless agent_matches?(agent)
      return false unless user_matches?(user)
      return false unless conditions_met?(agent)
      true
    end

    # Lexicographic precedence key — the sole decider in
    # Ai::InterventionPolicyService#resolve. Arrays compare element by element,
    # so no element can EVER be outweighed by a larger value in a later one:
    #
    #   [0] user_id present            — 1/0
    #   [1] ai_agent_id present        — 1/0
    #   [2] action_category is not "*" — 1/0
    #   [3] priority                   — operator's tie-break WITHIN a tier
    #
    # Elements 0-1 are the tier order #resolve documents — user+agent > user >
    # agent > global. Element 2 prefers a row naming the category over a
    # wildcard. Only element 3 is operator-settable, and it ranks rows that are
    # otherwise equal.
    #
    # These four were once WEIGHTS summed into one integer (+10/+5/+2, then
    # `+ priority`). Because `priority` is unbounded and additive it outranked
    # the hierarchy rather than breaking ties inside it: a scope-"global"
    # `auto_approve` at priority 10 scored 12 and beat an agent's own explicit
    # `require_approval` at priority 0, which scored 7 — the operator's gate on
    # that specific agent silently discarded, and a laxer verb winning because
    # its number was bigger (IMP-6430e3a8c4a1).
    #
    # Do NOT restore this as weights "large enough" to outrank a plausible
    # priority. That is the same defect with a bigger constant and it fails the
    # first time an operator sets a priority above the constant. `priority`
    # belongs in the LAST element, where no value it can take reaches a tier
    # above it.
    def specificity_key
      [
        user_id.present? ? 1 : 0,
        ai_agent_id.present? ? 1 : 0,
        action_category == "*" ? 0 : 1,
        priority
      ]
    end

    private

    def action_category_matches?(category)
      action_category == "*" || action_category == category
    end

    # A nil-agent row matches ANY caller here — agent dispatches included.
    # Audience separation is enforced one level up, and it is keyed on `scope`,
    # not on ai_agent_id nil-ness (IMP-cb36021d4094, superseding
    # IMP-bfbf8052e179): Ai::InterventionPolicyService#resolve admits, for an
    # agent caller, that agent's own rows plus scope-"global" rows, and drops
    # the scope-"action_type" operator path. So a nil-agent row reaches an agent
    # when its scope is "global" and never when its scope is "action_type".
    # Do not rely on this method alone to keep an operator-intent row away from
    # agents, and do not infer the audience from ai_agent_id here.
    def agent_matches?(agent_record)
      return true if ai_agent_id.nil?
      agent_record && ai_agent_id == agent_record.id
    end

    def user_matches?(user_record)
      return true if user_id.nil?
      user_record && user_id == user_record.id
    end

    def conditions_met?(agent_record)
      return true if conditions.blank?

      # Check trust tier minimum
      if conditions["trust_tier_minimum"].present? && agent_record
        tier_order = %w[supervised monitored trusted autonomous]
        trust_score = Ai::AgentTrustScore.find_by(agent_id: agent_record.id)
        agent_tier = trust_score&.tier || "supervised"
        min_tier = conditions["trust_tier_minimum"]
        return false if tier_order.index(agent_tier).to_i < tier_order.index(min_tier).to_i
      end

      # Check severity minimum
      # (evaluated at lookup time by InterventionPolicyService)

      # Check quiet hours
      if conditions["quiet_hours"].present?
        quiet = conditions["quiet_hours"]
        current_hour = Time.current.hour
        return false if quiet["start"].to_i <= current_hour && current_hour < quiet["end"].to_i
      end

      true
    end
  end
end
