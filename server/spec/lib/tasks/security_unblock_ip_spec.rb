# frozen_string_literal: true

require "rails_helper"

# server/lib/tasks/security.rake — host-side recovery for an operator whose own
# address was IP-blocked by RequestInspector. The blocked IP cannot reach the
# admin unblock endpoint (it sits behind login, which the block 429s), so the
# only other path used to be a hand-typed redis-cli DEL.
RSpec.describe "security:unblock_ip" do
  let(:ip) { "198.51.100.77" }

  def run_task(*args)
    previous_application = Rake.application
    begin
      Rake.application = Rake::Application.new
      Rake.application.rake_require("tasks/security", [ Rails.root.join("lib").to_s ], [])
      Rake::Task.define_task(:environment)
      Rake::Task["security:unblock_ip"].invoke(*args)
    ensure
      Rake.application = previous_application
    end
  end

  def quietly
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  before do
    Security::IpBlockStore.unblock!(ip)
    Security::IpBlockStore.block!(ip, duration_seconds: 300)
  end

  after { Security::IpBlockStore.unblock!(ip) }

  it "lifts the block through IpBlockStore.unblock! and leaves the offense count standing" do
    Security::IpBlockStore.bump_offense(ip)
    count = Security::IpBlockStore.offense_count(ip)

    out = quietly { run_task(ip) }

    expect(Security::IpBlockStore.blocked?(ip)).to be(false)
    expect(Security::IpBlockStore.offense_count(ip)).to eq(count)
    expect(out).to include("lifted")
  ensure
    Security::IpBlockStore.with { |redis| redis.del("#{Security::IpBlockStore::OFFENSES_PREFIX}#{ip}") }
  end

  it "writes an audit row naming the IP" do
    account = create(:account)

    expect { quietly { run_task(ip) } }.to change {
      AuditLog.where(action: "ip_block_lifted").count
    }.by(1)

    row = AuditLog.where(action: "ip_block_lifted").order(:created_at).last
    expect(row.account_id).to eq(account.id)
    expect(row.metadata["ip"]).to eq(ip)
    expect(row.metadata["was_blocked"]).to be(true)
    expect(row.ip_address).to eq(ip)
  end

  it "says so when the IP was not blocked, and still succeeds" do
    Security::IpBlockStore.unblock!(ip)

    out = quietly { run_task(ip) }

    expect(out).to include("was not blocked")
  end

  it "aborts without an IP argument" do
    expect { quietly { run_task } }.to raise_error(SystemExit)
  end

  it "rejects a CIDR range" do
    expect { quietly { run_task("198.51.100.0/24") } }.to raise_error(SystemExit)
    expect(Security::IpBlockStore.blocked?(ip)).to be(true)
  end

  it "aborts rather than claim success when Redis is unreachable" do
    allow(Security::IpBlockStore).to receive(:with).and_return(nil)

    expect { quietly { run_task(ip) } }.to raise_error(SystemExit)
  end

  it "rejects a value that is not an IP address" do
    expect { quietly { run_task("not-an-ip") } }.to raise_error(SystemExit)
  end
end
