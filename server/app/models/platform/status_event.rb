# frozen_string_literal: true

module Platform
  # ONE row per verdict transition, written by Platform::Status::SweepRunner
  # and by nothing else (design §4.3, "one producer, always").
  #
  # WHY THE SINGLE-PRODUCER RULE IS WORTH A COMMENT. The obvious alternative —
  # let each interested subsystem notice a change and record its own event —
  # is how a platform ends up with three feeds that disagree about whether a
  # node went down, and an operator who learns to trust none of them. The
  # sweep is the only thing that computes a verdict, so it is the only thing
  # that can know a verdict CHANGED. Everyone else subscribes: the broadcast,
  # this table, or Platform::Status::Emitters.
  #
  # Two kinds, and the second is deliberately redundant:
  # - `platform.component_status_changed` on EVERY transition.
  # - `platform.component_down` ADDITIONALLY on a transition to `down`.
  #
  # The second is not derivable-in-practice noise: escalation, notification
  # routing and the operator feed all want "show me the outages" without
  # scanning every transition and re-deriving severity, and a consumer that
  # only cares about outages should not have to know the verdict ladder to
  # find them. Both rows carry the same `occurred_at`.
  class StatusEvent < ApplicationRecord
    KIND_STATUS_CHANGED = "platform.component_status_changed"
    KIND_COMPONENT_DOWN = "platform.component_down"
    KINDS = [ KIND_STATUS_CHANGED, KIND_COMPONENT_DOWN ].freeze

    # Nullable for the same reason the status row's is: a process-wide
    # component has no tenant.
    belongs_to :account, optional: true
    # Nullified rather than cascaded when the component is reaped — the
    # history of what a component did outlives the component.
    belongs_to :component_status, class_name: "Platform::ComponentStatus", optional: true

    attribute :payload, :json, default: -> { {} }

    validates :component_kind, presence: true, length: { maximum: 255 }
    validates :component_ref, presence: true, length: { maximum: 255 }
    validates :kind, inclusion: { in: KINDS }
    # NOT `presence`, and nil is not an accident: a REMOVAL (the component's
    # record was reaped, or a wildcard error row cleared on recovery) is a
    # transition to nothing. Inventing a destination verdict for it — "ok",
    # say — would claim an observation the platform never made.
    validates :to_verdict, inclusion: { in: ComponentStatus::VERDICTS }, allow_nil: true
    # NOT `presence` — nil is the meaningful value for a first sighting, and a
    # presence validation would force the producer to invent a prior verdict.
    validates :from_verdict, inclusion: { in: ComponentStatus::VERDICTS }, allow_nil: true
    validates :occurred_at, presence: true

    scope :for_account, ->(account) { where(account_id: account.is_a?(::Account) ? account.id : account) }
    scope :shared,      -> { where(account_id: nil) }
    scope :of_kind,     ->(kind) { where(kind: kind) }
    scope :for_component, lambda { |component_kind, component_ref|
      where(component_kind: component_kind, component_ref: component_ref)
    }
    scope :recent_first, -> { order(occurred_at: :desc) }

    def down_event?
      kind == KIND_COMPONENT_DOWN
    end

    # First sighting: there was no previous verdict to move away from.
    def first_sighting?
      from_verdict.nil?
    end

    # The component stopped existing. `payload["reason"]` says which way —
    # "Reaped" (its record is gone) or "Recovered" (a wildcard error row
    # cleared when its contributor started working again).
    def removal?
      to_verdict.nil?
    end
  end
end
