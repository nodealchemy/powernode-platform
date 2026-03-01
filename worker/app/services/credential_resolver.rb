# frozen_string_literal: true

# Resolves AI provider credentials by fetching decrypted keys from the server API.
# Caches credentials in memory with a short TTL to avoid repeated API calls.
#
# Usage:
#   resolver = CredentialResolver.new(api_client)
#   creds = resolver.resolve(credential_id)
#   # => { "api_key" => "sk-...", "base_url" => "https://api.openai.com/v1", ... }
#
class CredentialResolver
  CACHE_TTL = 5 * 60 # 5 minutes

  # @param api_post_method [Method] bound method reference to backend_api_post
  def initialize(api_post_method)
    @api_post = api_post_method
    @cache = {}
  end

  # Resolve a credential by ID, returning decrypted credential data.
  # Results are cached for CACHE_TTL seconds.
  #
  # @param credential_id [String] UUID of the provider credential
  # @return [Hash] decrypted credential data (api_key, etc.)
  # @raise [CredentialError] if the credential cannot be resolved
  def resolve(credential_id)
    return nil if credential_id.blank?

    cached = @cache[credential_id]
    if cached && cached[:expires_at] > Time.current
      return cached[:data]
    end

    data = fetch_from_server(credential_id)
    @cache[credential_id] = { data: data, expires_at: Time.current + CACHE_TTL }
    data
  end

  # Clear cached credentials (e.g. after rotation)
  def clear_cache(credential_id = nil)
    if credential_id
      @cache.delete(credential_id)
    else
      @cache.clear
    end
  end

  class CredentialError < StandardError; end

  private

  def fetch_from_server(credential_id)
    response = @api_post.call(
      "/api/v1/ai/credentials/#{credential_id}/decrypt",
      {}
    )

    if response.is_a?(Hash) && response["success"] != false
      # Response may be wrapped in { credentials: { api_key: ... } } or direct
      response["credentials"] || response["data"]&.dig("credentials") || response
    else
      error_msg = response.is_a?(Hash) ? (response["error"] || response["message"]) : "Unknown error"
      raise CredentialError, "Failed to decrypt credential #{credential_id}: #{error_msg}"
    end
  end
end
