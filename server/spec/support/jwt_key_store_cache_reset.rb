# frozen_string_literal: true

# Drops Security::JwtKeyStore's in-process key cache before every example.
#
# The cache outlives the example's DB transaction: an example that rotates
# leaves this process holding a secret whose store row was rolled back, and the
# next example would sign with it until the cache expired, then switch secrets
# mid-run. Before, not after, as in maintenance_mode_cache_reset.rb.
RSpec.configure do |config|
  config.before do
    Security::JwtKeyStore.clear_cache!
  end
end
