# frozen_string_literal: true

module Platform
  # ONE INVESTIGATION of one component (design §5.3).
  #
  # An investigation is what the plane does when a verdict alone is not enough:
  # it assembles the evidence that existed around a failure, ranks candidate
  # causes, and records the reasoning so the next person does not repeat it.
  #
  # ── ONE OPEN INVESTIGATION PER COMPONENT ────────────────────────────────
  # Enforced by a PARTIAL unique index on `(account_id, fingerprint) WHERE
  # status = 'open'`, not by a check in the creating service. A service-side
  # check loses to two triggers firing in the same second — an operator
  # pressing Investigate while the stuck-signal trigger fires is exactly the
  # moment an investigation is most likely to be duplicated. The index is
  # partial so a component investigated last month can be investigated again;
  # a plain unique index would make the first investigation permanent.
  #
  # The fingerprint is DERIVED (`fingerprint_for`) and never hand-written, for
  # the same reason the remediation state is: two writers spelling it
  # differently is two investigations of one outage.
  class Investigation < ApplicationRecord
    # ── Triggers ────────────────────────────────────────────────────────────
    TRIGGER_OPERATOR = "operator"
    TRIGGER_STUCK    = "stuck"
    TRIGGER_DOWN     = "down"
    TRIGGERS = [ TRIGGER_OPERATOR, TRIGGER_STUCK, TRIGGER_DOWN ].freeze

    # ── Statuses ────────────────────────────────────────────────────────────
    # `open` covers both "queued" and "running": the worker job owns the
    # difference and the open-fingerprint rule cares only that one exists.
    # `abandoned` is for an investigation whose component was reaped before it
    # concluded — distinct from `completed`, because it reached no conclusion,
    # and distinct from `failed`, because nothing went wrong.
    STATUS_OPEN      = "open"
    STATUS_COMPLETED = "completed"
    STATUS_FAILED    = "failed"
    STATUS_ABANDONED = "abandoned"
    STATUSES = [ STATUS_OPEN, STATUS_COMPLETED, STATUS_FAILED, STATUS_ABANDONED ].freeze

    OPEN_STATUSES = [ STATUS_OPEN ].freeze

    # Nullable for the same reason the status row's is: a process-wide
    # component has no tenant.
    belongs_to :account, optional: true
    belongs_to :agent, class_name: "Ai::Agent", optional: true

    # WHO PRESSED INVESTIGATE (A6 re-verification G1). Set by the two doors a
    # person acts through, the REST button and the MCP verb, and never by the
    # status emitter, so an automatic investigation carries nil. Ranking uses it
    # as the execution's user, and the executor's security gate reads THAT as a
    # person's consent to spend: see `Ranking.create_execution`.
    belongs_to :opened_by_user, class_name: "User", optional: true

    # jsonb defaults live on the MODEL as lambdas, never on the column alone,
    # so a new record and a reloaded one carry the same object.
    attribute :evidence, :json, default: -> { {} }
    attribute :hypotheses, :json, default: -> { [] }

    validates :component_kind, presence: true, length: { maximum: 255 }
    validates :component_ref, presence: true, length: { maximum: 255 }
    validates :trigger, inclusion: { in: TRIGGERS }
    validates :status, inclusion: { in: STATUSES }
    validates :fingerprint, presence: true, length: { maximum: 255 }

    before_validation :assign_fingerprint

    scope :for_account, ->(account) { where(account_id: account.is_a?(::Account) ? account.id : account) }
    scope :open_investigations, -> { where(status: OPEN_STATUSES) }
    scope :concluded, -> { where.not(status: OPEN_STATUSES) }
    scope :for_component, lambda { |component_kind, component_ref|
      where(component_kind: component_kind, component_ref: component_ref)
    }
    scope :since, ->(time) { where(created_at: time..) }
    scope :recent_first, -> { order(created_at: :desc) }

    # The dedupe key. Deliberately NOT the component_status id: a component
    # that is reaped and re-created gets a new row id but is the same thing to
    # an operator, and an investigation of it should still dedupe.
    def self.fingerprint_for(component_kind:, component_ref:)
      "#{component_kind}:#{component_ref}"
    end

    # What ranking concluded when no agent's ranking was used, or nil when an
    # agent ranked it (or nothing has tried yet). Written only by
    # `Ranking.record_outcome!`; read by the doors' serializers and by the
    # conclusion, so the three cannot describe it differently.
    def ranking_record
      record = evidence.is_a?(Hash) ? evidence["ranking"] : nil
      record.is_a?(Hash) ? record : nil
    end

    def open? = status == STATUS_OPEN

    def concluded? = !open?

    # The winning hypothesis, or nil. `hypotheses` is stored ranked, so this is
    # `first` rather than a re-sort — re-ranking here would be a second ordering
    # rule that could disagree with the one that produced the list.
    def top_hypothesis
      Array(hypotheses).first
    end

    private

    def assign_fingerprint
      return if component_kind.blank? || component_ref.blank?

      self.fingerprint = self.class.fingerprint_for(component_kind: component_kind,
                                                    component_ref: component_ref)
    end
  end
end
