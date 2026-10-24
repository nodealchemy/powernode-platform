# frozen_string_literal: true

require "rails_helper"
require "puma"
require "puma/configuration"

# The worker reaches the backend through the ingress, which strips and then
# sets the forwarded client-cert headers. Puma listening on every interface
# lets anything that can reach :3000 skip that ingress and forge them, so in
# production Puma listens on loopback only, unless the operator names an address.
RSpec.describe "config/puma.rb bind" do
  def binds_with(env)
    keys = %w[RAILS_ENV RACK_ENV PUMA_BIND_ADDRESS PORT]
    saved = keys.to_h { |k| [ k, ENV[k] ] }
    keys.each { |k| ENV.delete(k) }
    env.each { |k, v| ENV[k] = v }
    conf = Puma::Configuration.new({ config_files: [ Rails.root.join("config/puma.rb").to_s ] }, {})
    conf.load
    conf.clamp
    conf.options[:binds]
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  it "binds loopback only in production" do
    expect(binds_with("RAILS_ENV" => "production")).to eq([ "tcp://127.0.0.1:3000" ])
  end

  it "honours PORT in production" do
    expect(binds_with("RAILS_ENV" => "production", "PORT" => "3100")).to eq([ "tcp://127.0.0.1:3100" ])
  end

  it "lets an operator name the address, for a container behind a separate proxy" do
    expect(binds_with("RAILS_ENV" => "production", "PUMA_BIND_ADDRESS" => "0.0.0.0")).to eq([ "tcp://0.0.0.0:3000" ])
  end

  it "keeps the existing development listener" do
    expect(binds_with("RAILS_ENV" => "development")).to eq([ "tcp://[::]:3000" ])
  end
end
