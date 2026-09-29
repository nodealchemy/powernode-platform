# frozen_string_literal: true

# Clears Admin::MaintenanceMode's cached status before every example.
#
# WHY. Admin::MaintenanceMode fronts its AdminSetting rows with a 5s-TTL
# Rails.cache entry (maintenance_mode:status). The per-example DB transaction
# rolls back any AdminSetting row an example wrote, but it does NOT touch
# Rails.cache — so a spec that calls Admin::MaintenanceMode.enable! and never
# clears the cache leaves "enabled: true" cached for up to 5 seconds, which
# can 503 the FIRST authenticated request of whichever spec happens to run
# next in the same process. Global rather than per-spec-file: any new spec
# that touches maintenance mode gets this for free instead of needing its own
# after-hook (and forgetting one is a real prior mistake here — earlier
# revisions of this feature's specs each hand-rolled their own).
#
# BEFORE, not after. RSpec runs after-hooks while the example's own message
# expectations are still armed, so an `after` here reaches
# `Rails.cache.delete("maintenance_mode:status")` through whatever
# `expect(Rails.cache).to receive(:delete).with(...)` the example just set up
# and fails it with an unexpected-arguments error on a call the example never
# made (site_setting_spec's clear_footer_cache! example). A before-hook runs
# ahead of any expectation the example declares, and is equivalent for the
# leak it guards: the entry an example leaves behind is dropped before the
# next one starts.
RSpec.configure do |config|
  config.before do
    Admin::MaintenanceMode.invalidate_cache!
  end
end
