# frozen_string_literal: true

# Temporarily sets/unsets TRUSTED_PROXY_CIDRS for the duration of a block,
# restoring whatever was there before. Shared by every spec that needs to
# flip Admin::MaintenanceMode#trusted_proxies_configured? — plain `ENV[...] =`
# would leak into whichever example runs next in the same process.
module TrustedProxyCidrsHelper
  def with_trusted_proxy_cidrs(value)
    original = ENV["TRUSTED_PROXY_CIDRS"]
    ENV["TRUSTED_PROXY_CIDRS"] = value
    yield
  ensure
    original.nil? ? ENV.delete("TRUSTED_PROXY_CIDRS") : (ENV["TRUSTED_PROXY_CIDRS"] = original)
  end
end

RSpec.configure do |config|
  config.include TrustedProxyCidrsHelper
end
