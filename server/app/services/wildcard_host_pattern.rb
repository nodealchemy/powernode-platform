# frozen_string_literal: true

require "public_suffix"

# Strict validation for "*.example.com" host patterns. A wildcard trusted host
# also becomes a credentialed CORS regex origin (CorsConfigurationService), so an
# over-broad pattern like "*.com" would trust every origin under a public suffix.
#
# Valid: "*." + a registrable domain (at least two labels, not itself a public
# suffix, last label not all digits). Used by every door that accepts wildcards.
module WildcardHostPattern
  LABEL = /[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?/i
  BASE = /\A#{LABEL}(?:\.#{LABEL})+\z/

  module_function

  def wildcard?(pattern)
    pattern.to_s.include?("*")
  end

  def valid?(pattern)
    pattern = pattern.to_s.strip
    return false unless pattern.start_with?("*.")

    base = pattern.delete_prefix("*.").downcase
    return false if base.length > 253 || !base.match?(BASE)
    return false if base.split(".").last.match?(/\A\d+\z/)

    # nil for a bare public suffix ("co.uk", "github.io"); unknown TLDs ("corp.internal") pass.
    !PublicSuffix.domain(base).nil?
  rescue PublicSuffix::Error
    false
  end
end
