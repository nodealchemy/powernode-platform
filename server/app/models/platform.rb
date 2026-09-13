# frozen_string_literal: true

# Platform namespace — the platform's view of ITSELF.
#
# Everything under here answers "what is this installation doing right now",
# as opposed to what an account's agents are doing (Ai::), what the fleet
# hardware is doing (the system extension), or what a tenant's data looks
# like. It is CORE: extensions contribute into its seams, core never names an
# extension.
#
# Models:
# - Platform::ComponentStatus (platform_component_statuses)
#
# Services live under app/services/platform/ (Platform::Status::Registry,
# Platform::Status::SweepService, Platform::Status::Rollup, ...).
module Platform
  def self.table_name_prefix
    "platform_"
  end
end
