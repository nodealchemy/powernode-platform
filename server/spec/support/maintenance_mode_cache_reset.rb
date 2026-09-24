# frozen_string_literal: true

# Clears Admin::MaintenanceMode's cached status after every example.
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
RSpec.configure do |config|
  config.after do
    Admin::MaintenanceMode.invalidate_cache!
  end
end
