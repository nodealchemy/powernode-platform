# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"
require "json"

# IMP-6d060f65ccae — scripts/verify-hub-deploy.sh. The remote half runs against fake
# `systemctl` / `uptime` / `curl` executables on PATH, through `bash -s` as the transport, so
# the whole script (config loading, remote program, JSON assembly, verdict) is exercised
# without any deployment fact.
RSpec.describe "scripts/verify-hub-deploy.sh" do
  let(:script) { File.join(File.expand_path("../../..", __dir__), "scripts/verify-hub-deploy.sh") }

  around do |example|
    Dir.mktmpdir("verify-hub") do |dir|
      @dir = dir
      example.run
    end
  end

  let(:core_sha) { "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678" }
  let(:ext_sha) { "0123456789abcdef0123456789abcdef01234567" }

  def write_exe(name, body)
    path = File.join(@dir, "bin", name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#!/usr/bin/env bash\n#{body}\n")
    File.chmod(0o755, path)
  end

  # Fake hub. boot 2026-09-01, rails entered 2026-09-20 unless overridden.
  def install_hub(active: "active", enter: "Sun 2026-09-20 10:00:00 UTC", boot: "2026-09-01 08:00:00", failed: "")
    write_exe("systemctl", <<~SH)
      case "$*" in
        *"--state=failed"*) printf '%s' #{failed.inspect} ;;
        "list-units powernode-*-rails.service"*) echo "powernode-fake-rails.service loaded active running Rails" ;;
        "is-active"*) echo #{active} ;;
        "show -p ActiveEnterTimestamp"*) echo #{enter.inspect} ;;
      esac
    SH
    write_exe("uptime", %(echo #{boot.inspect}))
    write_exe("curl", %(printf '%s' "${FAKE_UP:-200}"))
    File.write(File.join(@dir, "passwd"), (1..25).map { |i| "u#{i}:x:#{i}:#{i}::/:/bin/false\n" }.join)
  end

  def run_script(*args, env: {})
    full_env = {
      "PATH" => "#{File.join(@dir, 'bin')}:#{ENV.fetch('PATH')}",
      "POWERNODE_LOCAL_CONFIG" => "none",
      "HUB_EXEC_CMD" => "bash -s",
      "HUB_CORE_SHA_CMD" => "echo #{core_sha}",
      "HUB_EXT_SHA_CMD" => "echo #{ext_sha}",
      "HUB_PASSWD_FILE" => File.join(@dir, "passwd")
    }.merge(env)
    stdout, stderr, status = Open3.capture3(full_env, script, *args)
    [ stdout, stderr, status.exitstatus ]
  end

  it "prints one small JSON document and exits 0 when every check holds" do
    install_hub
    out, _err, code = run_script(core_sha, ext_sha)

    expect(code).to eq(0)
    doc = JSON.parse(out)
    expect(doc).to include(
      "rails_unit" => "powernode-fake-rails.service", "rails_restarted_after_boot" => true,
      "up_status" => 200, "passwd_lines" => 25, "core_present" => true, "ext_present" => true,
      "failed_units" => [], "ok" => true
    )
    expect(doc["rails_active_enter"]).to be > doc["host_boot"]
    expect(doc).to have_key("checks")
    expect(out.bytesize).to be < 800
  end

  it "accepts an abbreviated sha" do
    install_hub
    out, _err, code = run_script(core_sha[0, 9])

    expect(code).to eq(0)
    expect(JSON.parse(out)).to include("core_present" => true, "ext_present" => nil)
  end

  it "fails when the deployed core sha differs, and names the check" do
    install_hub
    out, err, code = run_script("f" * 40, ext_sha)

    expect(code).to eq(1)
    expect(JSON.parse(out)).to include("core_present" => false, "ok" => false)
    expect(err).to match(/core_present/)
  end

  it "fails when rails has not restarted since boot" do
    install_hub(enter: "Mon 2026-09-01 08:00:00 UTC")
    out, err, code = run_script(core_sha)

    expect(code).to eq(1)
    expect(JSON.parse(out)).to include("rails_restarted_after_boot" => false)
    expect(err).to match(/restarted_after_boot/)
  end

  it "requires the restart to be at or after --since" do
    install_hub
    since_epoch = Time.utc(2026, 9, 25).to_i
    out, _err, code = run_script(core_sha, "--since", since_epoch.to_s)

    expect(code).to eq(1)
    expect(JSON.parse(out)).to include("rails_restarted_after_boot" => false)
  end

  it "fails when /up does not answer 200" do
    install_hub
    out, err, code = run_script(core_sha, env: { "FAKE_UP" => "502" })

    expect(code).to eq(1)
    expect(JSON.parse(out)).to include("up_status" => 502)
    expect(err).to match(/up_ok/)
  end

  it "fails when rails is not active" do
    install_hub(active: "failed")
    _out, err, code = run_script(core_sha)

    expect(code).to eq(1)
    expect(err).to match(/rails_active/)
  end

  it "fails on a truncated passwd file" do
    install_hub
    File.write(File.join(@dir, "passwd"), "root:x:0:0::/root:/bin/bash\n")
    out, err, code = run_script(core_sha)

    expect(code).to eq(1)
    expect(JSON.parse(out)).to include("passwd_lines" => 1)
    expect(err).to match(/passwd_ok/)
  end

  it "fails and lists failed powernode units" do
    install_hub(failed: "powernode-x-sidekiq.service loaded failed failed Sidekiq\n")
    out, err, code = run_script(core_sha)

    expect(code).to eq(1)
    expect(JSON.parse(out)["failed_units"]).to eq([ "powernode-x-sidekiq.service" ])
    expect(err).to match(/no_failed_units/)
  end

  it "exits 2 without contacting anything when the access command is not configured" do
    install_hub
    _out, err, code = run_script(core_sha, env: { "HUB_EXEC_CMD" => "" })

    expect(code).to eq(2)
    expect(err).to match(/HUB_EXEC_CMD/)
  end

  it "exits 2 rather than faking ext_present when no ext sha command is configured" do
    install_hub
    _out, err, code = run_script(core_sha, ext_sha, env: { "HUB_EXT_SHA_CMD" => "" })

    expect(code).to eq(2)
    expect(err).to match(/HUB_EXT_SHA_CMD/)
  end

  it "exits 2 when the transport fails" do
    install_hub
    _out, err, code = run_script(core_sha, env: { "HUB_EXEC_CMD" => "false" })

    expect(code).to eq(2)
    expect(err).to match(/nothing was verified/)
  end

  it "unwraps a guest-agent JSON envelope" do
    install_hub
    wrapped = %(bash -s | jq -Rs '{"out-data": .}')
    out, _err, code = run_script(core_sha, env: { "HUB_EXEC_CMD" => wrapped, "HUB_EXEC_UNWRAP" => "qga-json" })

    expect(code).to eq(0)
    expect(JSON.parse(out)).to include("ok" => true)
  end

  it "rejects a malformed sha before any call" do
    install_hub
    _out, err, code = run_script("not-a-sha")

    expect(code).to eq(2)
    expect(err).to match(/hex/)
  end

  it "lets the environment win over a config file" do
    install_hub
    cfg = File.join(@dir, "landing.env")
    File.write(cfg, "HUB_EXEC_CMD='false'\nHUB_CORE_SHA_CMD='echo #{'e' * 40}'\n")
    out, _err, code = run_script(core_sha, env: { "POWERNODE_LOCAL_CONFIG" => cfg })

    expect(code).to eq(0)
    expect(JSON.parse(out)).to include("core_present" => true)
  end
end
