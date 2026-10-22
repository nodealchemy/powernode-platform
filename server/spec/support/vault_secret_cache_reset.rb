# frozen_string_literal: true

# Empties Security::VaultClient::SECRET_CACHE before every example.
#
# The cache is per process and lives outside the example's DB transaction, so
# a secret one example reads (or plants) would otherwise be served to the next
# example in the same process for up to five minutes. Before, not after, for
# the reason maintenance_mode_cache_reset.rb gives: a before-hook runs ahead of
# any expectation the example sets up.
RSpec.configure do |config|
  config.before do
    Security::VaultClient::SECRET_CACHE.clear
  end
end
