# frozen_string_literal: true

require 'jwt'

# Mints short-lived JWTs for worker → server authentication.
# Uses WORKER_ID + JWT_SECRET_KEY from environment.
# Tokens are cached per-thread for 4 minutes (expires in 5).
class WorkerJwt
  TOKEN_LIFETIME = 300    # 5 minutes
  CACHE_LIFETIME = 240    # 4 minutes (refresh before expiry)

  class << self
    # Returns a short-lived JWT for the current worker.
    # Cached per-thread to avoid re-signing on every request.
    def token
      cached = Thread.current[:_worker_jwt]
      if cached && cached[:expires_at] > Time.current
        return cached[:token]
      end

      config = PowernodeWorker.application.config
      worker_id = config.worker_id
      secret = config.jwt_secret_key

      raise "WORKER_ID not configured" if worker_id.nil? || worker_id.empty?
      raise "JWT_SECRET_KEY not configured" if secret.nil? || secret.empty?

      now = Time.current.to_i
      payload = {
        type: "worker",
        sub: worker_id,
        iat: now,
        exp: now + TOKEN_LIFETIME,
        iss: ENV.fetch("JWT_ISSUER", "powernode-platform"),
        aud: ENV.fetch("JWT_AUDIENCE", "powernode-api")
      }

      jwt = JWT.encode(payload, secret, "HS256")
      Thread.current[:_worker_jwt] = { token: jwt, expires_at: Time.current + CACHE_LIFETIME }
      jwt
    end

    # Clear the cached token (useful for testing or after config change)
    def clear_cache!
      Thread.current[:_worker_jwt] = nil
    end
  end
end
