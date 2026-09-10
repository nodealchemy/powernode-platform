# frozen_string_literal: true

# Register CORE ESCALATION as a status emitter (design §5.4, §8 row A7).
#
# `to_prepare`, not `after_initialize`: `Platform::Status::Escalation` is an
# autoloadable constant, so it has to be resolved inside the reload-aware hook
# or a code reload would leave the registry holding a stale class. Registration
# is by NAME, so the second call REPLACES the first rather than stacking a
# duplicate emitter that would notify twice per transition.
#
# A separate initializer from the contributor one on purpose: registering a
# kind and registering a mirror are different concerns with different failure
# modes, and one file that does both is one file two lanes edit.
#
# NOTE FOR THE SWEEP RUNNER: the dwell half of A7 (`degraded` persisting past
# its threshold) cannot be seen by an emitter, because nothing transitions
# while a component stays degraded. It needs a periodic call —
# `Platform::Status::Escalation.sweep!(account, now:)` — from the runner, after
# the transitions have been published. That call site is not wired here; see
# `Escalation.sweep!` for the exact placement.
Rails.application.config.to_prepare do
  Platform::Status::Emitters.register(:escalation) do |transition:, events:|
    Platform::Status::Escalation.run!(transition: transition, events: events)
  end
end
