# frozen_string_literal: true

module Ai
  # An ENVIRONMENT: which plane a piece of infrastructure belongs to — dev, ci,
  # staging, ops (the control plane itself), prod — and therefore how much an
  # agent may decide there on its own, how far one action may reach
  # (`max_blast_radius`, read by Ai::EnvironmentPolicyOverlay), and what gate a
  # version crosses to get in (`auto_promote_on_publish`: a FOLLOWING plane
  # serves a module's current version as soon as it is published; a PINNED
  # plane serves only what was promoted into it, one ladder rung at a time —
  # increment 4).
  #
  # Operator ruling 2026-09-08 (Environment campaign): infrastructure agents
  # are TRUSTED for reversible actions and need APPROVAL for destructive ones
  # and for anything touching a control-plane node or prod. That ruling has to
  # attach to something; before this model the fleet was one undifferentiated
  # set and the control plane looked like a CI builder to every sensor.
  #
  # CORE PURITY: the rows that CARRY an environment (node templates, nodes,
  # instances, pools, federation peers) live in the system extension and point
  # here. Core never names them; it only owns the noun. Projects, policies and
  # the autonomy gate read this model directly.
  #
  # Per-account, like everything else that varies by tenant. Every account
  # gets DEFAULTS (Account#ensure_default_environments for new accounts, a data
  # migration for the installed base) and may add more.
  class Environment < ApplicationRecord
    self.table_name = "ai_environments"

    include Auditable

    DECISION_AUTHORITIES = %w[supervised monitored trusted autonomous].freeze
    SLUG_FORMAT = /\A[a-z][a-z0-9-]{0,31}\z/

    # slug => attributes. The single source of truth for what a fresh account
    # gets; the backfill migration mirrors it as SQL.
    DEFAULTS = {
      "dev"     => { name: "Development", tier: 0, default_decision_authority: "trusted",    is_protected: false, is_default: true,  position: 10, auto_promote_on_publish: true },
      "ci"      => { name: "CI",          tier: 0, default_decision_authority: "trusted",    is_protected: false, is_default: false, position: 20, auto_promote_on_publish: true },
      "staging" => { name: "Staging",     tier: 1, default_decision_authority: "trusted",    is_protected: false, is_default: false, position: 30, auto_promote_on_publish: false },
      # Operator ruling 2026-09-08: the control plane keeps following
      # publishes for now (flippable per environment through environment_update).
      "ops"     => { name: "Operations",  tier: 2, default_decision_authority: "monitored",  is_protected: true,  is_default: false, position: 40, auto_promote_on_publish: true },
      "prod"    => { name: "Production",  tier: 3, default_decision_authority: "supervised", is_protected: true,  is_default: false, position: 50, auto_promote_on_publish: false }
    }.freeze

    belongs_to :account

    after_update_commit :notify_promotion_mode_listener, if: :saved_change_to_auto_promote_on_publish?
    has_many :projects, class_name: "Ai::Project", foreign_key: :environment_id,
                        dependent: :restrict_with_error, inverse_of: :environment

    validates :slug, presence: true, format: { with: SLUG_FORMAT, message: "must be lowercase alphanumeric with hyphens" },
                     uniqueness: { scope: :account_id }
    validates :name, presence: true, length: { maximum: 255 }
    validates :tier, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :default_decision_authority, inclusion: { in: DECISION_AUTHORITIES }
    validates :max_blast_radius, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validate  :approval_required_categories_are_strings
    validate  :single_default_per_account

    scope :ordered,   -> { order(:position, :tier, :slug) }
    # `protected` itself is a Ruby keyword-method, so the column is is_protected
    # and the scope is spelled out.
    scope :protected_only, -> { where(is_protected: true) }
    scope :by_tier,   -> { order(:tier) }

    # The environment a new template lands in when nobody says otherwise.
    # `dev` by default; an account may move the flag.
    def self.default_for(account)
      where(account: account).find_by(is_default: true) || where(account: account).ordered.first
    end

    # Resolve a slug or id inside ONE account (the guessable-handle rule from
    # Ai::Project.find_for_account applies here too).
    def self.find_for_account(account_id, identifier)
      key = identifier.to_s.strip
      return nil if key.empty?

      scope = where(account_id: account_id)
      scope.find_by(id: key) || scope.find_by(slug: key.downcase)
    rescue ActiveRecord::StatementInvalid
      where(account_id: account_id).find_by(slug: key.downcase)
    end

    # Create every missing default for an account. Idempotent by slug: a row
    # the operator has renamed or reconfigured is left alone.
    def self.ensure_defaults_for!(account)
      scope = where(account: account)
      existing = scope.pluck(:slug)
      # An operator may have moved the default flag (or deleted `dev`); never
      # re-create a second default.
      has_default = scope.exists?(is_default: true)
      DEFAULTS.each do |slug, attrs|
        next if existing.include?(slug)

        row = attrs.merge(account: account, slug: slug)
        row[:is_default] = false if has_default
        create!(row)
        has_default ||= row[:is_default]
      end
      scope.ordered
    end

    def protected?
      is_protected == true
    end

    # A FOLLOWING plane: its nodes serve a module's current version the moment
    # it is published. A pinned plane (false) serves only what was promoted
    # into it.
    def follows_publish?
      auto_promote_on_publish == true
    end

    # The promotion ladder for an account: environments by tier, then
    # position. A version climbs it one rung at a time.
    def self.ladder_for(account)
      where(account: account).order(:tier, :position, :slug).to_a
    end

    # The rung a version must already be on before it may be promoted into
    # THIS environment: the highest-tier PINNED environment strictly below
    # this one's tier (ties on tier are siblings, not predecessors; following
    # environments are not rungs — they run whatever is published). nil when
    # no pinned environment sits below: the version then enters the ladder
    # from the current version, i.e. by being published.
    def ladder_predecessor
      self.class.where(account_id: account_id, auto_promote_on_publish: false).where("tier < ?", tier)
          .order(tier: :desc, position: :desc, slug: :desc).first
    end

    # Flipping between following and pinned changes what every module serves
    # here; the fleet extension (seam :environment_promotion_mode_listener)
    # freezes or drops the environment's pins accordingly. Core mode has no
    # listener and nothing to freeze.
    def notify_promotion_mode_listener
      Powernode::ExtensionRegistry.provider(:environment_promotion_mode_listener)&.call(environment: self)
    end

    def to_s
      slug
    end

    private

    def approval_required_categories_are_strings
      return if approval_required_categories.is_a?(Array) && approval_required_categories.all? { |c| c.is_a?(String) }

      errors.add(:approval_required_categories, "must be an array of category strings")
    end

    def single_default_per_account
      return unless is_default

      clash = self.class.where(account_id: account_id, is_default: true).where.not(id: id).exists?
      errors.add(:is_default, "another environment is already the default for this account") if clash
    end
  end
end
