# frozen_string_literal: true

# The Sidekiq Redis connection options, shared by configure_server and
# configure_client in config/application.rb. Sidekiq 8 ignores a `:redis:`
# block in sidekiq.yml, so the timeouts live here (as config.redis options)
# and are asserted by spec/config/sidekiq_redis_url_spec.rb.
#
# POWERNODE_WORKER_REDIS_URL names the role on both sides (the server resolves
# the same variable in Powernode::Redis.worker_url, IMP-daecbb8a050e);
# REDIS_URL stays the fallback.
module SidekiqRedisConfig
  DEFAULT_URL = 'redis://localhost:6379/1'
  NETWORK_TIMEOUT = 5
  POOL_TIMEOUT = 5

  module_function

  def url(env = ENV)
    worker_url = env['POWERNODE_WORKER_REDIS_URL'].to_s.strip
    worker_url.empty? ? env.fetch('REDIS_URL', DEFAULT_URL) : worker_url
  end

  def options(size:, env: ENV)
    { url: url(env), size: size, network_timeout: NETWORK_TIMEOUT, pool_timeout: POOL_TIMEOUT }
  end

  def server_options(env: ENV)
    options(size: env.fetch('WORKER_CONCURRENCY', '25').to_i + 10, env: env)
  end

  def client_options(env: ENV)
    options(size: 5, env: env)
  end
end
