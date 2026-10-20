# frozen_string_literal: true

require 'rails_helper'
require 'erb'
require 'yaml'

# IMP-daecbb8a050e — POWERNODE_WORKER_REDIS_URL names the Sidekiq Redis on both
# sides: the server resolves it in Powernode::Redis.worker_url, and the worker
# reads it before REDIS_URL. With it unset the worker must behave exactly as it
# always has (REDIS_URL, then the /1 default).
RSpec.describe 'sidekiq.yml Redis URL' do
  def redis_url_with(env)
    keys = %w[POWERNODE_WORKER_REDIS_URL REDIS_URL]
    previous = keys.to_h { |k| [k, ENV.key?(k) ? ENV[k] : :absent] }
    keys.each { |k| env[k].nil? ? ENV.delete(k) : ENV[k] = env[k] }
    raw = File.read(File.expand_path('../../config/sidekiq.yml', __dir__))
    YAML.safe_load(ERB.new(raw).result, permitted_classes: [Symbol], aliases: true)[:redis]['url']
  ensure
    previous.each { |k, v| v == :absent ? ENV.delete(k) : ENV[k] = v }
  end

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

  # application.rb's configure_server/configure_client blocks are not exercised
  # under RSpec (the server block never runs here, and the client one runs once
  # at load), so pin that both use the same resolution as this file.
  it 'is mirrored by config/application.rb for both the server and client config' do
    app = File.read(File.expand_path('../../config/application.rb', __dir__))
    expect(app).to include("sidekiq_redis_url = ENV['POWERNODE_WORKER_REDIS_URL'].presence || " \
                           "ENV.fetch('REDIS_URL', 'redis://localhost:6379/1')")
    expect(app.scan('config.redis = { url: sidekiq_redis_url,').size).to eq(2)
  end
end
