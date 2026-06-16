# frozen_string_literal: true

# Skips examples tagged `requires_extension: <slug>` when that extension is not
# loaded in the current process. The canonical test mode is CORE mode (default
# Gemfile, no extensions), so specs covering extension-only features (billing,
# analytics tiers, public registration, etc.) skip-with-reason there and run
# normally in full mode where the extension's engine is loaded.
#
# Detection uses the slug-agnostic extension registry seam:
#   Powernode::ExtensionRegistry.loaded?(slug) -> Boolean
# (equivalently Shared::FeatureGateService.extension_loaded?(slug)).
RSpec.configure do |config|
  config.before(:each) do |example|
    slug = example.metadata[:requires_extension]
    next unless slug

    loaded = Powernode::ExtensionRegistry.loaded?(slug.to_s)
    skip("requires the '#{slug}' extension (not loaded in this mode)") unless loaded
  end
end
