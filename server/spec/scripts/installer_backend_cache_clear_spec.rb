# frozen_string_literal: true

require "rails_helper"

# Installer hosts start Rails through scripts/systemd/powernode-backend.sh,
# which has no other pre-boot Rails step. The one-time legacy cache clear runs
# there before Puma, guarded by a marker file so later boots pay nothing, and
# never fails the start.
RSpec.describe "installer backend start: one-time legacy cache clear" do
  let(:script) { File.read(Rails.root.join("../scripts/systemd/powernode-backend.sh")) }

  it "runs the clear task before exec'ing the server" do
    clear_at = script.index("powernode:cache:clear_legacy_plaintext")
    exec_at = script.index("exec bundle exec rails server")

    expect(clear_at).not_to be_nil
    expect(clear_at).to be < exec_at
  end

  it "is bounded, non-fatal and marker-guarded" do
    block = script[/# One-time legacy cache clear.*?\nfi\n/m]

    expect(block).not_to be_nil
    expect(block).to match(/if timeout \d+ bundle exec rails powernode:cache:clear_legacy_plaintext; then/)
    expect(block).to include("else") # a failed clear falls through to the server start
    expect(block).not_to match(/\bexit\b/)
    expect(block).to match(/touch "\$\{?CACHE_CLEAR_MARKER\}?"/)
    expect(block).to match(/\[\[ ! -f "\$\{?CACHE_CLEAR_MARKER\}?" \]\]/)
  end
end
