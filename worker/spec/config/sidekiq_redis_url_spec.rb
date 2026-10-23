# frozen_string_literal: true

require 'rails_helper'
require 'sidekiq/config'

# IMP-daecbb8a050e: POWERNODE_WORKER_REDIS_URL names the Sidekiq Redis on both
# sides (the server resolves it in Powernode::Redis.worker_url, and the worker
# reads it before REDIS_URL). With it unset the worker must behave exactly as it
# always has (REDIS_URL, then the /1 default).
#
# Sidekiq 8 ignores a `:redis:` block in sidekiq.yml, so the URL and the
# network/pool timeouts are config.redis options, built by SidekiqRedisConfig and
# applied by the configure_server / configure_client blocks in application.rb.
RSpec.describe 'Sidekiq Redis configuration' do
  def with_env(env)
    keys = %w[POWERNODE_WORKER_REDIS_URL REDIS_URL WORKER_CONCURRENCY]
    previous = keys.to_h { |k| [k, ENV.key?(k) ? ENV[k] : :absent] }
    keys.each { |k| env[k].nil? ? ENV.delete(k) : ENV[k] = env[k] }
    yield
  ensure
    previous.each { |k, v| v == :absent ? ENV.delete(k) : ENV[k] = v }
  end

  def redis_url_with(env)
    with_env(env) { SidekiqRedisConfig.server_options[:url] }
  end

  describe 'URL precedence' do
    it 'reads REDIS_URL when POWERNODE_WORKER_REDIS_URL is unset (unchanged behaviour)' do
      expect(redis_url_with('REDIS_URL' => 'redis://r.example:6379/0')).to eq('redis://r.example:6379/0')
    end

    it 'keeps the /1 default when neither is set' do
      expect(redis_url_with({})).to eq('redis://localhost:6379/1')
    end

    it 'prefers POWERNODE_WORKER_REDIS_URL over REDIS_URL' do
      url = redis_url_with('POWERNODE_WORKER_REDIS_URL' => 'redis://w.example:6379/1',
                           'REDIS_URL' => 'redis://r.example:6379/0')
      expect(url).to eq('redis://w.example:6379/1')
    end

    it 'treats a blank POWERNODE_WORKER_REDIS_URL as unset' do
      url = redis_url_with('POWERNODE_WORKER_REDIS_URL' => ' ', 'REDIS_URL' => 'redis://r.example:6379/0')
      expect(url).to eq('redis://r.example:6379/0')
    end
  end

  describe 'timeouts reach the connection pool' do
    {
      'server' => :server_options,
      'client' => :client_options
    }.each do |role, builder|
      it "gives the #{role} config network_timeout 5 and pool_timeout 5" do
        opts = SidekiqRedisConfig.public_send(builder)
        expect(opts[:network_timeout]).to eq(5)
        expect(opts[:pool_timeout]).to eq(5)

        cfg = Sidekiq::Config.new
        cfg.redis = opts
        expect(Sidekiq::RedisConnection).to receive(:create)
          .with(hash_including(network_timeout: 5, pool_timeout: 5)).and_call_original
        pool = cfg.new_redis_pool(2, role)
        expect(pool.instance_variable_get(:@timeout)).to eq(5)
        # The socket timeout reached redis-client too (no connection is made).
        pool.with { |c| expect(c.config.read_timeout).to eq(5) }
      end
    end

    it 'sizes the server pool from WORKER_CONCURRENCY plus headroom, and the client pool at 5' do
      with_env('WORKER_CONCURRENCY' => '7') do
        expect(SidekiqRedisConfig.server_options[:size]).to eq(17)
        expect(SidekiqRedisConfig.client_options[:size]).to eq(5)
      end
    end
  end

  it 'no longer carries a (dead) :redis: block in sidekiq.yml' do
    raw = File.read(File.expand_path('../../config/sidekiq.yml', __dir__))
    expect(raw).not_to match(/^:redis:/)
  end

  # application.rb's configure_server/configure_client blocks do not run under
  # RSpec (the server block never does, and the client one runs once at load), so
  # pin that both take their options from SidekiqRedisConfig.
  it 'is applied by config/application.rb for both the server and the client config' do
    app = File.read(File.expand_path('../../config/application.rb', __dir__))
    expect(app).to include('config.redis = SidekiqRedisConfig.server_options')
    expect(app).to include('config.redis = SidekiqRedisConfig.client_options')
  end
end
