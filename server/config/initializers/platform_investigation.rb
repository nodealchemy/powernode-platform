# frozen_string_literal: true

# Register the AUTOMATIC INVESTIGATION TRIGGER as a status emitter
# (design §5.3, increment A6).
#
# `to_prepare`, not `after_initialize`: `Platform::Investigation::TriggerEmitter`
# is an autoloadable constant, so it has to be resolved inside the reload-aware
# hook or the registry would hold a stale class after the first code reload.
# Registration is by NAME, so a second call REPLACES the first rather than
# stacking a duplicate emitter that would open two investigations per
# transition.
#
# Core registers no trigger KINDS here. `platform_subsystem → down` is the one
# transition core recognises by itself and it is recognised in the emitter's
# own code; every other kind arrives through
# `Platform::Investigation::Triggers.register(...)`, which an extension calls
# from its own engine. Core names no extension's event kinds.
Rails.application.config.to_prepare do
  Platform::Status::Emitters.register(:investigation) do |transition:, events:|
    Platform::Investigation::TriggerEmitter.handle(transition: transition, events: events)
  end
end
