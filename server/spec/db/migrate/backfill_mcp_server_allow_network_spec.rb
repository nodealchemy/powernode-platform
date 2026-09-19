# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260919140000_backfill_mcp_server_allow_network.rb")

# IMP-a50680fd53d8. Every existing stdio McpServer predates the
# systemd-run sandbox's network-deny-by-default; this migration backfills
# capabilities["allow_network"]=true onto every one of them so nothing
# breaks on deploy, without touching a server that already has the key
# set (explicitly true OR false) or a non-stdio server (the sandbox only
# ever applies to stdio spawns).
RSpec.describe BackfillMcpServerAllowNetwork do
  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }

  it "sets allow_network=true on an existing stdio server that never had the key" do
    server = create(:mcp_server, connection_type: "stdio", capabilities: { "tools" => true })

    migration.up

    expect(server.reload.capabilities["allow_network"]).to be(true)
  end

  it "leaves a stdio server's explicit allow_network=false alone" do
    server = create(:mcp_server, connection_type: "stdio", capabilities: { "allow_network" => false, "tools" => true })

    migration.up

    expect(server.reload.capabilities["allow_network"]).to be(false)
  end

  it "leaves a stdio server's explicit allow_network=true alone (idempotent)" do
    server = create(:mcp_server, connection_type: "stdio", capabilities: { "allow_network" => true, "tools" => true })

    migration.up

    expect(server.reload.capabilities).to eq("allow_network" => true, "tools" => true)
  end

  it "does not touch a non-stdio server" do
    server = create(:mcp_server, connection_type: "http", command: nil, args: [], capabilities: { "tools" => true })

    migration.up

    expect(server.reload.capabilities).not_to have_key("allow_network")
  end

  it "handles a null capabilities column on a stdio server" do
    server = create(:mcp_server, connection_type: "stdio")
    server.update_columns(capabilities: nil)

    migration.up

    expect(server.reload.capabilities["allow_network"]).to be(true)
  end

  it "refuses to run down: a backfilled row cannot be told apart from an explicit one" do
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
