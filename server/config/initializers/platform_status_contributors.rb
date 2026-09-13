# frozen_string_literal: true

# Register the CORE component-status contributors (design §4.4).
#
# `to_prepare`, not `after_initialize`: the contributors are autoloadable
# constants, so they must be resolved inside the reload-aware hook or the
# registry would hold a stale class after the first code reload in development
# and quietly keep serving the old conditions. Registration is idempotent and
# last-write-wins, which is exactly what a reload needs.
#
# Extensions register their own kinds the same way from their engine's
# `to_prepare`; core names no extension here and never will.
Rails.application.config.to_prepare do
  Platform::Status::Contributors.register_all!
end
