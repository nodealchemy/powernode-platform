# frozen_string_literal: true

require "rails_helper"
require "open3"

# `rails server -b $HOST` overrides config/puma.rb's bind, so the installer
# script must default to loopback in production itself.
RSpec.describe "scripts/systemd/powernode-backend.sh listen address" do
  let(:script) { Rails.root.join("../scripts/systemd/powernode-backend.sh").to_s }

  def host_for(env)
    snippet = File.read(script)[/^PORT=.*?^export PORT HOST RAILS_ENV$/m]
    out, = Open3.capture2(env, "bash", "-c", "#{snippet.sub(/^export.*$/, '')}\necho \"$HOST\"")
    out.strip
  end

  it "defaults to loopback in production" do
    expect(host_for("RAILS_ENV" => "production")).to eq("127.0.0.1")
  end

  it "keeps 0.0.0.0 outside production" do
    expect(host_for("RAILS_ENV" => "development")).to eq("0.0.0.0")
  end

  it "lets HOST override" do
    expect(host_for("RAILS_ENV" => "production", "HOST" => "10.1.2.3")).to eq("10.1.2.3")
  end
end
