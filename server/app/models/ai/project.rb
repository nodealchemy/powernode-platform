# frozen_string_literal: true

module Ai
  # A PROJECT: the durable thing a fleet of missions is work ON.
  #
  # Operator ruling 2026-09-05. Before this model the platform had no noun for
  # it — the per-project metric time series `belongs_to :mission`, the scaling
  # window lived in `mission.configuration`, and the provisioning brief created
  # a bare infrastructure `Ai::Mission`. So "the project" WAS a mission. Missions end
  # (`TERMINAL_STATUSES`, `completed_at`); projects do not, and nothing bound
  # template + module set + instances + network + volumes + exposed services +
  # repository + budget/bounds + SLOs + the owning team into one row.
  #
  # This is a real model with `has_many :missions`, NOT a facade over the
  # mission: a facade would have inherited the mission's terminal lifecycle,
  # which is precisely the defect.
  #
  # ==== The template seam (core purity) ====
  #
  # The node template a project is composed from belongs to an EXTENSION, and
  # core must never depend on an extension. The reference is therefore
  # POLYMORPHIC (`template_type` + `template_id`): the class name is DATA
  # written by whoever attaches the template. Core carries the pointer without
  # naming what it points at, and an installation without that extension simply
  # holds NULLs. Read it through #template_ref rather than #template when the
  # reader must not constantize a class that may be absent — an MCP payload,
  # for instance, must answer for a row whose extension is not installed.
  #
  # ==== Bounds: a RUNG, not a second source of truth ====
  #
  # `Ai::Mission` already resolves a per-project scaling window through one
  # ladder and one walk (`.resolve_scale_bound`). This model does NOT resolve
  # bounds of its own — it DECLARES them, in the same `watch_policies` /
  # `slo_targets` shape a mission uses, and the mission's ladder reads that
  # declaration as a rung between the mission's own configuration and its
  # template's defaults. Two resolvers would be two opinions of one project's
  # window, which is the failure the single ladder exists to prevent.
  class Project < ApplicationRecord
    self.table_name = "ai_projects"

    include Auditable

    # A project is not work, so it has no terminal state in the mission sense.
    # `archived` is retirement, not completion — the row and its history stay
    # readable.
    STATUSES = %w[active paused archived].freeze

    # The `configuration` sub-hashes the bounds and utilization ladders read.
    # Deliberately the SAME keys `Ai::Mission` uses, so one extractor serves
    # both rungs.
    WATCH_POLICIES_KEY = "watch_policies"
    SLO_TARGETS_KEY    = "slo_targets"

    # ==================== Associations ====================
    belongs_to :account
    belongs_to :created_by, class_name: "User", foreign_key: "created_by_id", optional: true
    belongs_to :repository, class_name: "Devops::GitRepository", foreign_key: "repository_id", optional: true
    belongs_to :team, class_name: "Ai::AgentTeam", foreign_key: "ai_agent_team_id", optional: true

    # See the header: generic on purpose, never an extension class name in core.
    belongs_to :template, polymorphic: true, optional: true

    # `:nullify`, not `:destroy`. A mission is a historical record of work that
    # actually ran; retiring the project it was done for must not erase it.
    has_many :missions, class_name: "Ai::Mission", foreign_key: "ai_project_id",
                        dependent: :nullify, inverse_of: :project

    # ==================== Validations ====================
    validates :name, presence: true, length: { maximum: 255 }
    validates :slug, presence: true, length: { maximum: 255 },
                     format: { with: /\A[a-z0-9][a-z0-9-]*\z/,
                               message: "must be lowercase alphanumeric with hyphens" },
                     uniqueness: { scope: :account_id, case_sensitive: false }
    validates :status, presence: true, inclusion: { in: STATUSES }

    # ==================== Scopes ====================
    scope :active, -> { where(status: "active") }
    scope :paused, -> { where(status: "paused") }
    scope :archived, -> { where(status: "archived") }
    scope :recent, -> { order(created_at: :desc) }

    # ==================== Callbacks ====================
    before_validation :set_defaults, on: :create

    # ==================== Lookup ====================

    # Resolve by UUID or by slug, always inside ONE account. Both doors take the
    # account scope, so neither can answer with another tenant's row — a
    # cross-tenant read is a repeatedly-filed defect class here, and a slug is
    # exactly the kind of guessable handle that invites one.
    def self.find_for_account(account_id, identifier)
      key = identifier.to_s.strip
      return nil if key.empty?

      scope = where(account_id: account_id)
      scope.find_by(id: key) || scope.find_by(slug: key.downcase)
    rescue ActiveRecord::StatementInvalid
      # A non-UUID `identifier` makes the id predicate unrepresentable on a uuid
      # column. Fall back to the slug door rather than surfacing a 500.
      where(account_id: account_id).find_by(slug: key.downcase)
    end

    # ==================== Declarations read by the ladders ====================

    # This project's declared scaling policies, in the shape `Ai::Mission`'s
    # ladder reads. A garbled declaration answers `{}` — the mission's own
    # `.resolve_scale_bound` decides what an ABSENT rung means; this reader only
    # says whether the rung carries anything at all.
    def watch_policies_hash
      configuration_section(WATCH_POLICIES_KEY)
    end

    # This project's declared SLO targets — availability, latency, cost ceiling,
    # and the utilization ceilings `Ai::Mission#utilization_targets` resolves.
    def slo_targets_hash
      configuration_section(SLO_TARGETS_KEY)
    end

    # ==================== Readers ====================

    # The template pointer WITHOUT constantizing it. Safe on an installation
    # where the owning extension is absent.
    def template_ref
      return nil if template_type.blank? || template_id.blank?

      { type: template_type, id: template_id }
    end

    # Mission counts and the ones still in flight. `.includes` is not used: this
    # aggregates in SQL rather than iterating associations.
    def status_rollup
      counts = missions.group(:status).count
      {
        mission_count: counts.values.sum,
        missions_by_status: counts,
        in_progress_mission_ids: missions.in_progress.order(:created_at).pluck(:id)
      }
    end

    def project_summary
      {
        id: id,
        name: name,
        slug: slug,
        status: status,
        description: description,
        repository_id: repository_id,
        team_id: ai_agent_team_id,
        template: template_ref,
        created_at: created_at&.iso8601,
        updated_at: updated_at&.iso8601
      }
    end

    def project_details
      project_summary.merge(
        watch_policies: watch_policies_hash,
        slo_targets: slo_targets_hash,
        metadata: metadata.is_a?(Hash) ? metadata : {},
        mission_count: missions.count
      )
    end

    # Turn a free-text name into a slug. Public because the provisioning brief
    # derives one from the same hint the mission is named from, and two
    # derivations would eventually disagree.
    def self.slugify(text)
      base = text.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
      base = base[0, 80].to_s.gsub(/-+\z/, "")
      base.presence || "project-#{SecureRandom.hex(4)}"
    end

    private

    def configuration_section(key)
      cfg = configuration
      return {} unless cfg.is_a?(Hash)

      section = cfg[key] || cfg[key.to_sym]
      section.is_a?(Hash) ? section.deep_stringify_keys : {}
    end

    def set_defaults
      self.status ||= "active"
      self.configuration = {} unless configuration.is_a?(Hash)
      self.metadata = {} unless metadata.is_a?(Hash)
      self.slug = self.class.slugify(name) if slug.blank?
    end
  end
end
