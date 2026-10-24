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

    # IMP-44c8b73cad75 — the daemon is shared by every lane of every concurrent run, so one client's
    # FLUSHALL / CONFIG SET / SHUTDOWN is every other run's problem. ACL rules, not rename-command.
    it "denies the instance-wide and admin commands to the default user through ACL rules" do
      out, _e, st = Open3.capture3(redis, "--print-conf")
      expect(st).to be_success
      user = out.lines.grep(/^user default /)
      expect(user.size).to eq(1)
      rule = user.first.split
      expect(rule).to include("on", "nopass", "~*", "&*", "+@all")
      %w[-flushall -debug -monitor -shutdown -config|set -config|rewrite -config|resetstat -acl -module
         -replicaof -slaveof -swapdb -save -bgsave -client|kill -client|pause -move -migrate].each do |deny|
        expect(rule).to include(deny), "expected the default user to carry #{deny}"
      end
      %w[-flushdb -info -config|get -client -scan -keys -select -@all].each do |kept|
        expect(rule).not_to include(kept), "#{kept} must stay allowed"
      end
      expect(out).not_to match(/^rename-command/)
    end

    it "prints no password, plaintext or hashed (stop needs none: it signals the verified pid)" do
      out, _e, st = Open3.capture3(redis, "--print-conf")
      expect(st).to be_success
      out.lines.grep(/^user /).each do |line|
        expect(line.split).not_to include(a_string_matching(/\A[>#<!]/)), "credential token in: #{line}"
      end
      expect(out).not_to match(/^requirepass/)
    end
  end

  describe "scripts/test-redis.sh ACL guard (throwaway daemon)" do
    redis_script = File.join(root, "scripts", "test-redis.sh")

    def skip_without_redis7
      skip "redis-server not installed" unless system("command -v redis-server >/dev/null 2>&1")
      version = `redis-server --version`[/ v=(\d+)\./, 1].to_i
      skip "redis-server #{version}.x predates the ACL subcommand rules (needs 7)" if version < 7
    end

    # A daemon of our own on a free port, under a tmpdir; never 6379 or the live 6380. Started by the script,
    # or (launch:) by the caller, e.g. from an old-style config.
    def with_throwaway(script, launch: nil)
      skip_without_redis7
      port = TCPServer.open("127.0.0.1", 0) { |srv| srv.addr[1] }
      raise "free port collided with a shared daemon" if [ 6379, 6380 ].include?(port)
      Dir.mktmpdir("par-redis-acl") do |d|
        env = { "TEST_REDIS_DIR" => d, "TEST_REDIS_PORT" => port.to_s, "TEST_REDIS_DATABASES" => "16" }
        pidfile = File.join(d, "redis.pid")
        pid = nil
        begin
          if launch
            launch.call(env, d)
          else
            _o, e, st = Open3.capture3(env, script, "start")
            expect(st).to be_success, e
          end
          pid = File.read(pidfile).strip.to_i
          yield env, port, d
        ensure
          # Re-read the pidfile too: a start that dies after launching, or a stop/start inside the example,
          # leaves a daemon the remembered pid does not name.
          pids = [ pid, (File.read(pidfile).strip.to_i if File.exist?(pidfile)) ].compact.uniq
          pids.each do |p|
            next unless p > 1 && p != Process.pid && File.exist?("/proc/#{p}")
            next unless File.read("/proc/#{p}/comm").start_with?("redis-server") &&
                        File.read("/proc/#{p}/cmdline").include?(":#{port}")
            Process.kill("KILL", p)
          rescue Errno::ENOENT, Errno::ESRCH
            nil
          end
        end
      end
    end

    def cli(port, *args)
      out, err, _st = Open3.capture3("timeout", "5", "redis-cli", "-h", "127.0.0.1", "-p", port.to_s, *args)
      out + err
    end

    it "refuses FLUSHALL, CONFIG SET/REWRITE/RESETSTAT, DEBUG, MONITOR, SHUTDOWN, ACL and SWAPDB from clients" do
      with_throwaway(redis_script) do |_env, port|
        cli(port, "-n", "5", "set", "survivor", "1")
        [
          %w[flushall], %w[flushall async], %w[config set maxmemory-policy noeviction], %w[config rewrite],
          %w[config resetstat], %w[debug sleep 0], %w[monitor], %w[shutdown abort], %w[acl setuser default +@all],
          %w[acl whoami], %w[swapdb 0 5], %w[replicaof no one], %w[module list], %w[bgsave], %w[client pause 1],
          %w[move survivor 6], %w[migrate 127.0.0.1 1 survivor 6 100], %w[script kill], %w[function kill]
        ].each do |cmd|
          # DEBUG is also off by default (enable-debug-command no), which answers before the ACL does.
          expect(cli(port, *cmd)).to match(/NOPERM|DEBUG command not allowed/), "expected #{cmd.join(' ').upcase} to be refused"
        end
        expect(cli(port, "-n", "5", "get", "survivor").strip).to eq("1")
      end
    end

    it "keeps FLUSHDB, data commands, SCAN, INFO, CONFIG GET and CLIENT working" do
      with_throwaway(redis_script) do |_env, port|
        expect(cli(port, "-n", "3", "set", "k", "v").strip).to eq("OK")
        expect(cli(port, "-n", "3", "get", "k").strip).to eq("v")
        expect(cli(port, "-n", "3", "setex", "t", "60", "x").strip).to eq("OK")
        expect(cli(port, "-n", "3", "scan", "0", "match", "k*")).to include("k")
        expect(cli(port, "-n", "4", "set", "other-lane", "1").strip).to eq("OK")
        expect(cli(port, "-n", "3", "flushdb").strip).to eq("OK")
        expect(cli(port, "-n", "3", "dbsize").strip).to eq("0")
        expect(cli(port, "-n", "4", "get", "other-lane").strip).to eq("1")
        expect(cli(port, "info", "server")).to match(/process_id:\d+/)
        expect(cli(port, "config", "get", "databases")).to include("16")
        expect(cli(port, "client", "setname", "lane3").strip).to eq("OK")
        expect(cli(port, "client", "list")).to include("name=")
        expect(cli(port, "publish", "chan", "hi").strip).to eq("0")
        expect(cli(port, "eval", "return 1", "0").strip).to eq("1")
      end
    end

    it "still starts, reports status and stops (without SHUTDOWN), and never signals an unrelated pid" do
      with_throwaway(redis_script) do |env, _port, d|
        _o, e, st = Open3.capture3(env, redis_script, "status")
        expect(st).to be_success, e
        _o, e, st = Open3.capture3(env, redis_script, "start")
        expect(st).to be_success, e

        real = File.read(File.join(d, "redis.pid"))
        bystander = Process.spawn("sleep", "60")
        begin
          File.write(File.join(d, "redis.pid"), "#{bystander}\n")
          _o, e, st = Open3.capture3(env, redis_script, "stop")
          expect(st).not_to be_success
          expect(e).to match(/not the redis-server serving/)
          expect(Process.kill(0, bystander)).to eq(1)
        ensure
          begin
            Process.kill("KILL", bystander)
          rescue Errno::ESRCH
            nil
          end
          Process.wait(bystander)
        end

        File.write(File.join(d, "redis.pid"), real)
        _o, e, st = Open3.capture3(env, redis_script, "stop")
        expect(st).to be_success, e
        _o, _e, st = Open3.capture3(env, redis_script, "status")
        expect(st.exitstatus).to eq(3)
      end
    end

    it "warns loudly when it finds a daemon started without (or with an older) command guard" do
      old_style = lambda do |env, d|
        conf, _e, st = Open3.capture3(env, redis_script, "--print-conf")
        expect(st).to be_success
        File.write(File.join(d, "redis.conf"), conf.lines.grep_v(/^user default /).join)
        expect(system("redis-server", File.join(d, "redis.conf"), out: File::NULL)).to be(true)
        Timeout.timeout(5) { sleep 0.1 until cli(env["TEST_REDIS_PORT"], "ping").strip == "PONG" }
      end
      with_throwaway(redis_script, launch: old_style) do |env, port, d|
        expect(cli(port, "-n", "7", "set", "k", "v").strip).to eq("OK")
        expect(cli(port, "flushall").strip).to eq("OK") # the unguarded daemon this warning is about

        out, err, st = Open3.capture3(env, redis_script, "start")
        expect(st).to be_success, err
        expect(out).to include("already running")
        expect(err).to match(/WARNING: .*WITHOUT the command guard.*run 'stop' then 'start'/)

        conf = File.join(d, "redis.conf")
        File.write(conf, "#{File.read(conf)}user default on nopass ~* &* +@all -flushall\n")
        _o, err, st = Open3.capture3(env, redis_script, "start")
        expect(st).to be_success, err
        expect(err).to match(/WARNING: .*OLDER command guard/)

        _o, e, st = Open3.capture3(env, redis_script, "stop")
        expect(st).to be_success, e
        _o, e, st = Open3.capture3(env, redis_script, "start")
        expect(st).to be_success, e
        _o, err, st = Open3.capture3(env, redis_script, "start")
        expect(st).to be_success, err
        expect(err).not_to match(/WARNING/)
        expect(cli(port, "flushall")).to match(/NOPERM/)
      end
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

    # IMP-c314caa0e9da — the TERM-ignoring fixture loops outlive an example that is interrupted (a Timeout, a
    # failed expectation, Ctrl-C) and run forever, pinning worktree cwds. Guarantee: a pid is signalled only if
    # the example recorded it AND /proc/<pid>/cmdline still names this example's own unique par-kill* tmpdir
    # (so a dead, reaped and reused pid is skipped); a group is signalled only if that pid leads it and it is
    # not this process's group. Nothing is signalled when the tmpdir is not a par-kill* directory in Dir.tmpdir.
    def par_kill_alive?(pid)
      File.read("/proc/#{pid}/stat")[/\)\s+(\S)[^)]*\z/, 1] != "Z"
    rescue Errno::ENOENT, Errno::ESRCH
      false
    end

    def par_kill_names_dir?(pid, dir)
      File.binread("/proc/#{pid}/cmdline").tr("\0", " ").include?(dir)
    rescue Errno::ENOENT, Errno::ESRCH, Errno::EACCES
      false
    end

    # Pids of live processes whose command line names this fixture's own unique tmpdir.
    def par_kill_survivors(dir)
      Dir.glob("/proc/[0-9]*/cmdline").filter_map do |f|
        pid = f[%r{/proc/(\d+)/}, 1].to_i
        pid if pid != Process.pid && par_kill_alive?(pid) && par_kill_names_dir?(pid, dir)
      end
    end

    def reap_par_kill(dir, pids)
      real = begin
        File.realpath(dir)
      rescue Errno::ENOENT
        nil
      end
      return unless real && File.basename(real).start_with?("par-kill") && File.dirname(real) == File.realpath(Dir.tmpdir)

      recorded = File.join(dir, "child.pid")
      pids << File.read(recorded).to_i if File.exist?(recorded) && !File.zero?(recorded)
      pids.uniq.select { |pid| pid > 1 && pid != Process.pid && par_kill_names_dir?(pid, dir) }.each do |pid|
        pgid = begin
          Process.getpgid(pid)
        rescue Errno::ESRCH
          nil
        end
        targets = [ pid ]
        targets.unshift(-pid) if pgid == pid && pgid != Process.getpgrp
        targets.each do |target|
          Process.kill("KILL", target)
        rescue Errno::ESRCH, Errno::EPERM
          nil
        end
      end
      pids.each do |pid|
        Process.wait(pid, Process::WNOHANG)
      rescue Errno::ECHILD
        nil
      end
    end

    # Runs the block with a fresh par-kill* tmpdir and a list the block records its pids in; whatever the block
    # does (raise included), the recorded pids and their groups are SIGKILLed and the tmpdir removed afterwards.
    def with_par_kill_fixture
      Dir.mktmpdir("par-kill") do |d|
        pids = []
        begin
          yield d, pids
        ensure
          reap_par_kill(d, pids)
        end
      end
    end

    def spawn_par_kill_wrapper(lib, dir, pids, env = {})
      script = File.join(dir, "w.sh")
      File.write(script, <<~SH)
        #!/usr/bin/env bash
        source "#{lib}"
        trap test_pg_on_signal INT TERM HUP QUIT
        test_pg_run_group bash -c "trap '' TERM; echo \\$\\$ > #{dir}/child.pid; while :; do sleep 1; done"
        echo "rc=$?" > #{dir}/rc
      SH
      pid = Process.spawn(env, "bash", script, out: File::NULL, err: File::NULL, pgroup: true)
      pids << pid
      Timeout.timeout(10) { sleep 0.1 until File.exist?(File.join(dir, "child.pid")) && !File.zero?(File.join(dir, "child.pid")) }
      pids << File.read(File.join(dir, "child.pid")).to_i
      pid
    end

    it "KILLs a group that ignores TERM once PARALLEL_KILL_AFTER seconds have passed" do
      with_par_kill_fixture do |d, pids|
        pid = spawn_par_kill_wrapper(lib, d, pids, { "PARALLEL_KILL_AFTER" => "2" })
        child = pids.last
        started = Time.now
        Process.kill("HUP", pid)
        Timeout.timeout(15) { Process.wait(pid) }
        expect(Time.now - started).to be < 12
        expect(File.read(File.join(d, "rc")).strip).to eq("rc=143")
        expect { Process.kill(0, child) }.to raise_error(Errno::ESRCH)
      end
    end

    it "leaves no par-kill process behind when an example is interrupted mid-run" do
      interrupted = Class.new(StandardError)
      dir = recorded = nil
      begin
        with_par_kill_fixture do |d, pids|
          dir = d
          recorded = pids
          spawn_par_kill_wrapper(lib, d, pids)
          raise interrupted, "interrupted while the fixture loop is running"
        end
      rescue interrupted
        nil
      end
      survivors = par_kill_survivors(dir)
      deadline = Time.now + 2 # SIGKILL is asynchronous
      survivors = par_kill_survivors(dir) while survivors.any? && Time.now < deadline && sleep(0.05)
      # Safety net for this example only (it signals just the pids it recorded); the expectation below is what counts.
      recorded.uniq.select { |p| p > 1 && p != Process.pid && par_kill_names_dir?(p, dir) }.each do |p|
        [ (-p unless Process.getpgid(p) != p || p == Process.getpgrp), p ].compact.each { |t| Process.kill("KILL", t) rescue nil } # rubocop:disable Style/RescueModifier
      end
      expect(survivors).to be_empty, "par-kill processes survived the interrupted example: #{survivors.inspect}"
      expect(File.exist?(dir)).to be(false)
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
