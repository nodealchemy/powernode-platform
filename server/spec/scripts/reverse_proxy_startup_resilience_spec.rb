# frozen_string_literal: true

require "spec_helper"

# IMP-7455340041e4 — powernode-reverse-proxy@default landed in a permanent
# `failed` state: Traefik exited 1 within ~1.5s of start (journal:
# "accept tcp [::]:80: use of closed network connection" on web/websecure — a
# SHUTDOWN artifact, not a bind conflict), and a fixed tight RestartSec=5s with
# no backoff burned through StartLimitBurst (5) in ~25s, so a TRANSIENT early
# exit became a permanent outage.
#
# Fix (verified against systemd v255 source during review): exponential restart
# backoff via RestartSteps + RestartMaxDelaySec (both added in systemd 254), so
# transient failures are retried with increasing delay (5s -> ~9s -> ~16.5s ->
# 30s -> 30s) rather than a fixed 5s cadence — while StartLimitBurst stays the
# crash-loop backstop (the 6th start still trips at ~98-173s, < the 300s window,
# so a genuinely permanent failure still lands in `failed`).
#
# NB: a wrapper "wait for :80/:443 free" gate was evaluated and deliberately NOT
# added — on a same-unit Restart= systemd fully stops+reaps the old process
# before the new ExecStart, and LISTEN sockets vanish on process death (no
# TIME_WAIT for listeners; Traefik/Go sets SO_REUSEADDR), so such a gate is a
# no-op for this failure mode. The backoff is the load-bearing fix.
RSpec.describe "powernode-reverse-proxy startup resilience (IMP-7455340041e4)" do
  repo_root = File.expand_path("../../..", __dir__) # server/spec/scripts -> repo root
  let(:unit) { File.read(File.join(repo_root, "scripts/systemd/units/powernode-reverse-proxy@.service")) }

  it "keeps Restart=on-failure (auto-recovery preserved)" do
    expect(unit).to match(/^Restart=on-failure\s*$/)
  end

  it "configures exponential restart backoff (RestartSteps + RestartMaxDelaySec)" do
    expect(unit).to match(/^RestartSteps=[1-9]\d*\s*$/),
      "expected RestartSteps>0 for restart backoff; unit:\n#{unit}"
    expect(unit).to match(/^RestartMaxDelaySec=\S+/),
      "expected RestartMaxDelaySec so the backoff has a ceiling; unit:\n#{unit}"
  end

  it "keeps RestartSec strictly below RestartMaxDelaySec (backoff engages, not clamped away)" do
    restart_sec = unit[/^RestartSec=(\d+)s?\s*$/, 1]&.to_i
    max_delay   = unit[/^RestartMaxDelaySec=(\d+)s?\s*$/, 1]&.to_i
    expect(restart_sec).not_to be_nil
    expect(max_delay).not_to be_nil
    # systemd disables backoff (and warns) unless RestartSec < RestartMaxDelaySec.
    expect(restart_sec).to be < max_delay
  end

  it "still bounds crash loops with a StartLimit safety net (backoff must not defeat it)" do
    expect(unit).to match(/^StartLimitBurst=[1-9]\d*\s*$/)
    expect(unit).to match(/^StartLimitIntervalSec=\d+\s*$/)
  end
end
