# frozen_string_literal: true

require "spec_helper"
require "open3"
require "timeout"
require "tmpdir"
require "socket"
require "fileutils"

# IMP-7e1c8b0f4849 — opt-in parallel RSpec against the tmpfs test cluster.
# Exercises the pure decision logic in scripts/lib/test-pg.sh (lane names, the shared-cluster refusal,
# the process-count formula) and the wrapper's own refusals. Nothing here starts a cluster or an rspec.
RSpec.describe "parallel RSpec wrapper (scripts/parallel-rspec.sh)" do
  root = File.expand_path("../../..", __dir__)
  lib = File.join(root, "scripts", "lib", "test-pg.sh")
  wrapper = File.join(root, "scripts", "parallel-rspec.sh")

  def lib_call(lib, env, fn, *args)
    Open3.capture3(env, "bash", "-c", 'source "$1"; shift; "$@"', "_", lib, fn, *args)
  end

  describe "test_pg_parallel_lanes" do
    it "names lanes __p1..__pN, a namespace the worktree lanes (2/3/4, _tmpfs) can never occupy" do
      out, _e, st = lib_call(lib, {}, "test_pg_parallel_lanes", "4")
      expect(st).to be_success
      expect(out.split).to eq(%w[__p1 __p2 __p3 __p4])
    end

    it "refuses a non-positive or non-numeric count" do
      %w[0 -1 x].each do |bad|
        _o, _e, st = lib_call(lib, {}, "test_pg_parallel_lanes", bad)
        expect(st).not_to be_success, "expected #{bad.inspect} to be refused"
      end
    end
  end

  describe "test_pg_parallel_guard (refuses the shared cluster)" do
    around do |ex|
      Dir.mktmpdir("par-guard") { |d| @dir = d; ex.run }
    end

    def with_socket(port)
      path = File.join(@dir, ".s.PGSQL.#{port}")
      srv = UNIXServer.new(path)
      yield
    ensure
      srv&.close
      FileUtils.rm_f(path) if path
    end

    it "refuses port 5432, whatever the socket dir holds" do
      _o, err, st = lib_call(lib, { "PGPORT" => nil }, "test_pg_parallel_guard", "5432", @dir)
      expect(st).not_to be_success
      expect(err).to match(/shared/i)
    end

    it "refuses an empty Rails port (that resolves to the shared default)" do
      _o, err, st = lib_call(lib, { "PGPORT" => nil }, "test_pg_parallel_guard", "", @dir)
      expect(st).not_to be_success
      expect(err).to match(/shared/i)
    end

    it "refuses a port with no live tmpfs socket" do
      _o, _e, st = lib_call(lib, { "PGPORT" => nil }, "test_pg_parallel_guard", "5433", @dir)
      expect(st).not_to be_success
    end

    it "refuses literal 5432 even when PGPORT points elsewhere" do
      File.write(File.join(@dir, ".test-pg-tmpfs"), "")
      with_socket(5433) do
        _o, err, st = lib_call(lib, { "PGPORT" => "5433" }, "test_pg_parallel_guard", "5432", @dir)
        expect(st).not_to be_success
        expect(err).to match(/5432/)
      end
    end

    it "refuses a socket in a directory without the tmpfs marker" do
      with_socket(5433) do
        _o, err, st = lib_call(lib, { "PGPORT" => nil }, "test_pg_parallel_guard", "5433", @dir)
        expect(st).not_to be_success
        expect(err).to match(/marker/)
      end
    end

    it "accepts the live tmpfs cluster" do
      File.write(File.join(@dir, ".test-pg-tmpfs"), "")
      with_socket(5433) do
        _o, _e, st = lib_call(lib, { "PGPORT" => nil }, "test_pg_parallel_guard", "5433", @dir)
        expect(st).to be_success
      end
    end
  end

  describe "test_pg_parallel_n (process-count formula, no hardcoded cap)" do
    # cores mem_avail_kb reserve_kb per_process_kb redis_lanes pg_max pg_used conns_per_process
    def n_for(lib, *args)
      out, err, st = lib_call(lib, {}, "test_pg_parallel_n", *args.map(&:to_s))
      expect(st).to be_success, err
      out.split("\t").first.to_i
    end

    it "is bounded by cores when everything else is plentiful" do
      expect(n_for(lib, 16, 64_000_000, 1_000_000, 1_000_000, 31, 200, 5, 5)).to eq(16)
    end

    it "is bounded by available memory after the reserve" do
      # (11_000_000 - 2_000_000) / 1_500_000 = 6
      expect(n_for(lib, 16, 11_000_000, 2_000_000, 1_500_000, 31, 200, 5, 5)).to eq(6)
    end

    it "is bounded by free Redis lanes" do
      expect(n_for(lib, 16, 64_000_000, 1_000_000, 1_000_000, 3, 200, 5, 5)).to eq(3)
    end

    it "is bounded by Postgres connection headroom" do
      # (60 - 3 superuser reserved - 10 used) / 10 = 4
      expect(n_for(lib, 16, 64_000_000, 1_000_000, 1_000_000, 31, 60, 10, 10)).to eq(4)
    end

    it "REFUSES, instead of flooring to 1, when a bound is zero (memory below the reserve, no PG headroom, no redis lane)" do
      [
        [ "16", "100", "1000000", "1000000", "31", "200", "5", "5", /memory/ ],
        [ "16", "64000000", "1000000", "1000000", "31", "0", "0", "5", /postgres/ ],
        [ "16", "64000000", "1000000", "1000000", "0", "200", "5", "5", /redis/ ]
      ].each do |*args, msg|
        out, err, st = lib_call(lib, {}, "test_pg_parallel_n", *args)
        expect(st).not_to be_success, "expected a refusal for #{args.inspect}, got #{out.inspect}"
        expect(err).to match(msg)
      end
    end

    it "agrees with Powernode::Redis on lanes per daemon size" do
      %w[16 32 64].each do |dbs|
        out, _e, _st = lib_call(lib, {}, "test_pg_redis_lanes", dbs)
        top_worker = 14 + (dbs.to_i - 16)
        expect(out.strip.to_i).to eq(((top_worker - 3) / 2) + 1)
      end
    end
  end

  describe "scripts/parallel-rspec.sh --check" do
    it "exists and is executable" do
      expect(File.executable?(wrapper)).to be(true)
    end

    # Hermetic: no server/.env.test.local, no real ledger, no real tmpfs cluster directory.
    def hermetic_env(dir, extra = {})
      { "PGPORT" => nil, "TEST_ENV_LOCAL_FILE" => File.join(dir, "absent.env"), "TEST_REDIS_DIR" => File.join(dir, "redis"),
        "TEST_PG_DIR" => File.join(dir, "pg") }.merge(extra)
    end

    it "refuses to run against the shared 5432 cluster" do
      Dir.mktmpdir("par-check") do |d|
        _o, err, st = Open3.capture3(hermetic_env(d, "DATABASE_PORT" => "5432"), wrapper, "--check")
        expect(st.exitstatus).not_to eq(0)
        expect(err).to match(/shared/i)
      end
    end

    it "refuses when DATABASE_PORT is not declared at all" do
      Dir.mktmpdir("par-check") do |d|
        _o, err, st = Open3.capture3(hermetic_env(d, "DATABASE_PORT" => nil), wrapper, "--check")
        expect(st.exitstatus).not_to eq(0)
        expect(err).to match(/shared|DATABASE_PORT/i)
      end
    end
  end

  describe "scripts/validate.sh VALIDATE_PARALLEL" do
    validate = File.join(root, "scripts", "validate.sh")

    # Runs the real platform_specs function with `bundle` and the wrapper replaced by stubs that only
    # print how they were called, so no rspec and no database is involved.
    def run_platform_specs(validate, env)
      Dir.mktmpdir("validate-par") do |d|
        FileUtils.mkdir_p([ File.join(d, "bin"), File.join(d, "server") ])
        File.write(File.join(d, "bin", "bundle"), "#!/bin/sh\necho \"BUNDLE $*\"\n")
        File.write(File.join(d, "parallel-rspec.sh"), "#!/bin/sh\necho \"WRAPPER $*\"\n")
        FileUtils.chmod("+x", [ File.join(d, "bin", "bundle"), File.join(d, "parallel-rspec.sh") ])
        script = <<~BASH
          RED="" BLUE="" NC="" PROJECT_ROOT="#{d}" SCRIPT_DIR="#{d}"
          source <(sed -n '/^platform_specs() {/,/^}/p' "#{validate}")
          platform_specs
        BASH
        Open3.capture3({ "PATH" => "#{File.join(d, 'bin')}:#{ENV['PATH']}" }.merge(env), "bash", "-c", script)
      end
    end

    it "stays serial (bundle exec rspec) when VALIDATE_PARALLEL is unset" do
      out, _e, st = run_platform_specs(validate, { "VALIDATE_PARALLEL" => nil })
      expect(st).to be_success
      expect(out).to include("BUNDLE exec rspec --format progress")
      expect(out).not_to include("WRAPPER")
    end

    it "hands the platform pass to the wrapper with -n N when VALIDATE_PARALLEL=N" do
      out, _e, st = run_platform_specs(validate, { "VALIDATE_PARALLEL" => "6" })
      expect(st).to be_success
      expect(out).to include("WRAPPER -n 6 -- spec")
      expect(out).not_to include("BUNDLE")
    end

    it "lets the wrapper size the run for VALIDATE_PARALLEL=auto" do
      out, _e, st = run_platform_specs(validate, { "VALIDATE_PARALLEL" => "auto" })
      expect(st).to be_success
      expect(out).to include("WRAPPER -- spec")
    end

    it "fails loudly on a malformed value instead of quietly running serial" do
      out, _e, st = run_platform_specs(validate, { "VALIDATE_PARALLEL" => "yes" })
      expect(st).not_to be_success
      expect(out).not_to include("BUNDLE")
      expect(out).not_to include("WRAPPER")
    end
  end

  describe "scripts/test-redis.sh" do
    redis = File.join(root, "scripts", "test-redis.sh")

    it "prints a loopback-only, persistence-free, 64-database config by default" do
      out, _e, st = Open3.capture3({ "TEST_REDIS_PORT" => nil, "TEST_REDIS_DATABASES" => nil }, redis, "--print-conf")
      expect(st).to be_success
      expect(out).to match(/^bind 127\.0\.0\.1$/)
      expect(out).to match(/^port 6380$/)
      expect(out).to match(/^databases 64$/)
      expect(out).to match(/^save ""$/)
      expect(out).to match(/^appendonly no$/)
    end

    it "refuses to manage the shared daemon's port, and a database count below 16" do
      _o, err, st = Open3.capture3({ "TEST_REDIS_PORT" => "6379" }, redis, "--print-conf")
      expect(st).not_to be_success
      expect(err).to match(/6379/)
      _o, err, st = Open3.capture3({ "TEST_REDIS_DATABASES" => "8" }, redis, "--print-conf")
      expect(st).not_to be_success
      expect(err).to match(/at least 16/)
    end
  end

  describe "per-worktree namespaces (lane prefix + redis ledger)" do
    around { |ex| Dir.mktmpdir("par-ledger") { |d| @ledger = File.join(d, "lanes.ledger"); ex.run } }

    def claim(lib, ledger, want, prefix, pid, mode = "claim")
      lib_call(lib, {}, "test_pg_redis_claim", ledger, "30", want.to_s, prefix, pid.to_s, mode)
    end

    it "names lanes under a worktree prefix and refuses an unvetted one" do
      out, _e, st = lib_call(lib, {}, "test_pg_parallel_lanes", "2", "__w1a2b3cp")
      expect(st).to be_success
      expect(out.split).to eq(%w[__w1a2b3cp1 __w1a2b3cp2])
      %w[_tmpfs _2 __p;x].each do |bad|
        _o, _e, st = lib_call(lib, {}, "test_pg_parallel_lanes", "2", bad)
        expect(st).not_to be_success
      end
    end

    it "hands two concurrent runs disjoint redis ranges and shrinks the second to what is free" do
      a, _e, st = claim(lib, @ledger, 16, "__p", Process.pid)
      expect(st).to be_success
      expect(a.split).to eq(%w[0 16])
      b, _e, st = claim(lib, @ledger, 20, "__w1a2b3cp", Process.pid + 0) # same live pid, other prefix
      expect(st).to be_success
      expect(b.split).to eq(%w[16 14])
    end

    it "refuses a second live run of the same prefix and releases on exit" do
      claim(lib, @ledger, 4, "__p", Process.pid)
      _o, err, st = claim(lib, @ledger, 4, "__p", Process.pid)
      expect(st.exitstatus).to eq(3)
      expect(err).to match(/already has a live/)
      _o, _e, st = lib_call(lib, {}, "test_pg_redis_release", @ledger, Process.pid.to_s)
      expect(st).to be_success
      out, _e, st = claim(lib, @ledger, 4, "__p", Process.pid)
      expect(st).to be_success
      expect(out.split).to eq(%w[0 4])
    end

    it "prunes the claim of a dead process" do
      pid = Process.spawn("true"); Process.wait(pid)
      File.write(@ledger, "#{pid} __p 0 30\n")
      out, _e, st = claim(lib, @ledger, 5, "__p", Process.pid)
      expect(st).to be_success
      expect(out.split).to eq(%w[0 5])
    end
  end

  describe "signal handling (test_pg_run_group)" do
    it "stops the whole child group on SIGTERM and only then lets the EXIT trap release" do
      Dir.mktmpdir("par-signal") do |d|
        script = File.join(d, "w.sh")
        File.write(script, <<~SH)
          #!/usr/bin/env bash
          source "#{lib}"
          trap 'if kill -0 "$(cat #{d}/child.pid)" 2>/dev/null; then echo child-alive > #{d}/released; else echo child-gone > #{d}/released; fi' EXIT
          trap test_pg_on_signal INT TERM
          test_pg_run_group bash -c 'sleep 300 & echo $$ > #{d}/child.pid; wait'
          [ -z "$TEST_PG_SIGNALLED" ] || exit 143
        SH
        pid = Process.spawn("bash", script, out: File::NULL, err: File::NULL)
        Timeout.timeout(10) { sleep 0.1 until File.exist?(File.join(d, "child.pid")) && !File.zero?(File.join(d, "child.pid")) }
        child = File.read(File.join(d, "child.pid")).to_i
        Process.kill("TERM", pid)
        Timeout.timeout(20) { Process.wait(pid) }
        expect(File.read(File.join(d, "released")).strip).to eq("child-gone")
        expect { Process.kill(0, child) }.to raise_error(Errno::ESRCH)
      end
    end

    it "KILLs a group that ignores TERM once PARALLEL_KILL_AFTER seconds have passed" do
      Dir.mktmpdir("par-kill") do |d|
        script = File.join(d, "w.sh")
        File.write(script, <<~SH)
          #!/usr/bin/env bash
          source "#{lib}"
          trap test_pg_on_signal INT TERM HUP QUIT
          test_pg_run_group bash -c "trap '' TERM; echo \$\$ > #{d}/child.pid; while :; do sleep 1; done"
          echo "rc=$?" > #{d}/rc
        SH
        pid = Process.spawn({ "PARALLEL_KILL_AFTER" => "2" }, "bash", script, out: File::NULL, err: File::NULL)
        Timeout.timeout(10) { sleep 0.1 until File.exist?(File.join(d, "child.pid")) && !File.zero?(File.join(d, "child.pid")) }
        child = File.read(File.join(d, "child.pid")).to_i
        started = Time.now
        Process.kill("HUP", pid)
        Timeout.timeout(15) { Process.wait(pid) }
        expect(Time.now - started).to be < 12
        expect(File.read(File.join(d, "rc")).strip).to eq("rc=143")
        expect { Process.kill(0, child) }.to raise_error(Errno::ESRCH)
      end
    end

    it "does not launch the phase when a signal landed before it started" do
      Dir.mktmpdir("par-presig") do |d|
        out, _e, _st = Open3.capture3("bash", "-c", %(source "#{lib}"; TEST_PG_SIGNALLED=1; test_pg_run_group touch #{d}/ran; echo rc=$?))
        expect(out).to include("rc=143")
        expect(File.exist?(File.join(d, "ran"))).to be(false)
      end
    end
  end

  describe "scripts/parallel-rspec.sh --dry-run (serial tail routing)" do
    # A fake psql answers the two sizing queries, so no cluster is needed; ledger, Redis dir and env file are tmpdirs.
    def dry_run(wrapper, *paths)
      Dir.mktmpdir("par-dry") do |d|
        FileUtils.mkdir_p(File.join(d, "bin"))
        File.write(File.join(d, "bin", "psql"), "#!/bin/sh\ncase \"$*\" in *max_connections*) echo 200;; *) echo 5;; esac\n")
        FileUtils.chmod("+x", File.join(d, "bin", "psql"))
        FileUtils.mkdir_p(File.join(d, "pg"))
        File.write(File.join(d, "pg", ".test-pg-tmpfs"), "")
        sock = UNIXServer.new(File.join(d, "pg", ".s.PGSQL.5433")) # the guard only looks for the cluster's socket
        env = { "PATH" => "#{File.join(d, 'bin')}:#{ENV['PATH']}", "DATABASE_PORT" => "5433", "PGPORT" => nil,
                "TEST_ENV_LOCAL_FILE" => File.join(d, "absent.env"), "TEST_REDIS_DIR" => File.join(d, "redis"),
                "TEST_PG_DIR" => File.join(d, "pg"), "TEST_REDIS_PORT" => "6391", "PARALLEL_LANE_PREFIX" => "__p" }
        begin
          Open3.capture3(env, wrapper, "--dry-run", "-n", "2", "--", *paths)
        ensure
          sock.close
        end
      end
    end

    let(:tail_file) { "spec/models/report_request_spec.rb" }

    it "excludes the tail files from the parallel phase for a directory argument, and runs them in the tail" do
      out, err, st = dry_run(wrapper, "spec/models")
      expect(st).to be_success, err
      run = out[/^run  : .*$/]
      expect(run).to include("--exclude-pattern").and include("report_request_spec")
      expect(out[/^tail : .*$/]).to include(tail_file)
    end

    it "keeps an explicitly named tail file out of the parallel arguments" do
      out, err, st = dry_run(wrapper, "spec/models/user_spec.rb", tail_file)
      expect(st).to be_success, err
      run = out[/^run  : .*$/]
      expect(run).to end_with("spec/models/user_spec.rb)")
      expect(run.sub(/--exclude-pattern \(.*?\) /, "")).not_to include(tail_file)
      expect(out[/^tail : .*$/]).to end_with("#{tail_file})")
    end

    it "does not die on a tail entry outside the selected paths (an uninitialised extension submodule)" do
      out, err, st = dry_run(wrapper, "spec/lint")
      expect(st).to be_success, err
      expect(out).not_to match(/does not exist/)
    end
  end

  describe "scripts/test-redis.sh stop" do
    redis_script = File.join(root, "scripts", "test-redis.sh")

    it "refuses to signal a pidfile that is not the daemon serving the port, then stops the real one" do
      skip "redis-server not installed" unless system("command -v redis-server >/dev/null 2>&1")
      port = TCPServer.open("127.0.0.1", 0) { |srv| srv.addr[1] }
      Dir.mktmpdir("par-redis") do |d|
        env = { "TEST_REDIS_DIR" => d, "TEST_REDIS_PORT" => port.to_s, "TEST_REDIS_DATABASES" => "16" }
        real_pid = nil
        begin
          _o, e, st = Open3.capture3(env, redis_script, "start")
          expect(st).to be_success, e
          real_pid = File.read(File.join(d, "redis.pid")).strip
          File.write(File.join(d, "redis.pid"), "#{Process.pid}\n")
          _o, e, st = Open3.capture3(env, redis_script, "stop")
          expect(st).not_to be_success
          expect(e).to match(/not the redis-server serving/)
          File.write(File.join(d, "redis.pid"), "#{real_pid}\n")
          _o, e, st = Open3.capture3(env, redis_script, "stop")
          expect(st).to be_success, e
        ensure
          pid = real_pid.to_i
          Process.kill("TERM", pid) if pid > 1 && pid != Process.pid && File.exist?("/proc/#{pid}")
        end
      end
    end
  end
end
