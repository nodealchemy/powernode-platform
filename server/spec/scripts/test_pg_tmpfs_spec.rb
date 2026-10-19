# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"
require "erb"
require "yaml"
require "socket"
require "fileutils"

# IMP-6ecac2740b87 — optional tmpfs-backed, test-only Postgres cluster.
# No real cluster is started: scripts/test-pg-tmpfs.sh runs against a fake PG bin dir, and the pure
# decision logic in scripts/lib/test-pg.sh is sourced and exercised directly.
RSpec.describe "tmpfs test Postgres cluster" do
  root = File.expand_path("../../..", __dir__)
  script = File.join(root, "scripts", "test-pg-tmpfs.sh")
  lib = File.join(root, "scripts", "lib", "test-pg.sh")

  def sh(env, *cmd)
    Open3.capture3(env, *cmd)
  end

  # Run one function from the sourced lib; returns [stdout, stderr, status].
  def lib_call(lib, env, fn, *args)
    sh(env, "bash", "-c", 'source "$1"; shift; "$@"', "_", lib, fn, *args)
  end

  def free_port
    s = TCPServer.new("127.0.0.1", 0)
    s.addr[1].tap { s.close }
  end

  describe "server/config/database.yml.example" do
    let(:example) { File.join(root, "server", "config", "database.yml.example") }

    def render_port(path, env)
      saved = ENV.to_h
      %w[DATABASE_PORT PGPORT TEST_ENV_NUMBER].each { |k| ENV.delete(k) }
      env.each { |k, v| ENV[k] = v }
      YAML.safe_load(ERB.new(File.read(path)).result, aliases: true).fetch("test")["port"].to_i
    ensure
      ENV.replace(saved)
    end

    it "keeps port 5432 when neither DATABASE_PORT nor PGPORT is set" do
      expect(render_port(example, {})).to eq(5432)
    end

    it "honours a DATABASE_PORT override" do
      expect(render_port(example, { "DATABASE_PORT" => "5433" })).to eq(5433)
    end

    it "falls back to PGPORT, as libpq did before the port key existed" do
      expect(render_port(example, { "PGPORT" => "5440" })).to eq(5440)
    end

    it "prefers DATABASE_PORT over PGPORT" do
      expect(render_port(example, { "DATABASE_PORT" => "5433", "PGPORT" => "5440" })).to eq(5433)
    end
  end

  describe "test_pg_dotenv_port" do
    def port_from(lib, content)
      Dir.mktmpdir do |d|
        f = File.join(d, ".env.test.local")
        File.write(f, content)
        out, _err, _st = lib_call(lib, {}, "test_pg_dotenv_port", f)
        out.strip
      end
    end

    {
      "bare" => ["DATABASE_PORT=5433\n", "5433"],
      "export prefix" => ["export DATABASE_PORT=5433\n", "5433"],
      "double quotes" => ["DATABASE_PORT=\"5433\"\n", "5433"],
      "single quotes" => ["DATABASE_PORT='5433'\n", "5433"],
      "leading whitespace and spaces around =" => ["  DATABASE_PORT = 5433\n", "5433"],
      "trailing comment" => ["DATABASE_PORT=5433 # tmpfs\n", "5433"],
      "last assignment wins" => ["DATABASE_PORT=5433\nDATABASE_PORT=5434\n", "5434"],
      "commented out" => ["# DATABASE_PORT=5433\n", ""],
      "non-numeric" => ["DATABASE_PORT=abc\n", ""],
      "other keys" => ["TEST_ENV_NUMBER=_x\n", ""]
    }.each do |label, (content, expected)|
      it "reads #{label}" do
        expect(port_from(lib, content)).to eq(expected)
      end
    end

    it "is empty for a missing file" do
      out, _err, st = lib_call(lib, {}, "test_pg_dotenv_port", "/nonexistent/.env")
      expect(st).to be_success
      expect(out.strip).to eq("")
    end
  end

  describe "tmpfs-mode predicate and cluster resolution" do
    around do |ex|
      Dir.mktmpdir("pgsock") do |d|
        @dir = d
        ex.run
      end
    end

    def with_socket(port)
      srv = UNIXServer.new(File.join(@dir, ".s.PGSQL.#{port}"))
      yield
    ensure
      srv&.close
    end

    it "is true only when the cluster's own socket for that exact port exists" do
      with_socket(5433) do
        _o, _e, st = lib_call(lib, {}, "test_pg_socket_up", @dir, "5433")
        expect(st).to be_success
      end
    end

    it "is false without a socket (e.g. a pgbouncer port)" do
      _o, _e, st = lib_call(lib, {}, "test_pg_socket_up", @dir, "6432")
      expect(st).not_to be_success
    end

    [" 5432", "05433", "5433 ", "5433abc", ""].each do |bad|
      it "rejects the malformed port #{bad.inspect} even when a socket exists" do
        with_socket(5433) do
          _o, _e, st = lib_call(lib, {}, "test_pg_socket_up", @dir, bad)
          expect(st).not_to be_success
        end
      end
    end

    it "resolves to shared when Rails and the client default agree" do
      out, _e, st = lib_call(lib, { "PGPORT" => nil }, "test_pg_resolve_cluster", "", "5432", @dir)
      expect(st).to be_success
      expect(out.strip).to eq("shared")
    end

    it "treats an empty Rails port as 5432" do
      out, _e, st = lib_call(lib, { "PGPORT" => nil }, "test_pg_resolve_cluster", "", "", @dir)
      expect(st).to be_success
      expect(out.strip).to eq("shared")
    end

    it "aborts (2) when a DATABASE_PORT is declared but Rails reported no port" do
      _o, err, st = lib_call(lib, { "PGPORT" => nil }, "test_pg_resolve_cluster", "5433", "", @dir)
      expect(st.exitstatus).to eq(2)
      expect(err).to match(/reported no port/)
    end

    it "defaults an empty Rails port to PGPORT, not a hard-coded 5432" do
      out, _e, st = lib_call(lib, { "PGPORT" => "5440" }, "test_pg_resolve_cluster", "", "", @dir)
      expect(st).to be_success
      expect(out.strip).to eq("shared")
    end

    it "resolves to tmpfs when Rails' port is the live tmpfs socket" do
      with_socket(5433) do
        out, _e, st = lib_call(lib, { "PGPORT" => nil }, "test_pg_resolve_cluster", "5433", "5433", @dir)
        expect(st).to be_success
        expect(out.strip).to eq("tmpfs")
      end
    end

    it "aborts (2) when the declared DATABASE_PORT disagrees with what Rails resolved" do
      with_socket(5433) do
        _o, err, st = lib_call(lib, { "PGPORT" => nil }, "test_pg_resolve_cluster", "5433", "5432", @dir)
        expect(st.exitstatus).to eq(2)
        expect(err).to match(/5433.*5432/)
      end
    end

    it "aborts (3) when Rails points at a port that is neither shared nor the tmpfs cluster" do
      _o, _e, st = lib_call(lib, { "PGPORT" => nil }, "test_pg_resolve_cluster", "6432", "6432", @dir)
      expect(st.exitstatus).to eq(3)
    end

    it "aborts (3) when the tmpfs cluster is down (no socket) instead of falling back to 5432" do
      _o, _e, st = lib_call(lib, { "PGPORT" => nil }, "test_pg_resolve_cluster", "5433", "5433", @dir)
      expect(st.exitstatus).to eq(3)
    end
  end

  describe "scripts/test-pg-tmpfs.sh" do
    around do |ex|
      Dir.mktmpdir("tpg", "/tmp") do |d|
        @tmp = d
        @bin = File.join(d, "bin")
        @log = File.join(d, "fake.log")
        FileUtils.mkdir_p(@bin)
        write_fake("initdb", <<~'SH')
          while [ $# -gt 0 ]; do [ "$1" = "-D" ] && d="$2"; shift; done
          mkdir -p "$d"; echo 16 > "$d/PG_VERSION"; : > "$d/postgresql.conf"
        SH
        write_fake("pg_ctl", <<~'SH')
          args=("$@"); d=""
          for ((i=0;i<${#args[@]};i++)); do [ "${args[i]}" = "-D" ] && d="${args[i+1]}"; done
          act="${args[${#args[@]}-1]}"; echo "pg_ctl $act" >> "$FAKE_LOG"
          case "$act" in
            status) [ -f "$d/.fake_running" ] && exit 0 || exit 3 ;;
            start) : > "$d/.fake_running" ;;
            stop) rm -f "$d/.fake_running" ;;
          esac
        SH
        write_fake("psql", <<~'SH')
          echo "psql $*" >> "$FAKE_LOG"
        SH
        ex.run
      end
    end

    def write_fake(name, body)
      path = File.join(@bin, name)
      File.write(path, "#!/usr/bin/env bash\n#{body}")
      FileUtils.chmod(0o755, path)
    end

    def env_for(dir, extra = {})
      { "TEST_PG_DIR" => dir, "TEST_PG_BIN" => @bin, "TEST_PG_PORT" => @port.to_s,
        "TEST_PG_MIN_FREE_KB" => "1", "FAKE_LOG" => @log,
        "TMPDIR" => @tmp }.merge(extra) # TMPDIR: `stop` must only see THIS example's prep locks
    end

    before { @port = free_port }

    it "exists and is executable" do
      expect(File.executable?(script)).to be(true)
    end

    it "reports stopped (exit 3) when the data dir is missing" do
      _o, _e, st = sh(env_for(File.join(@tmp, "absent")), script, "status")
      expect(st.exitstatus).to eq(3)
    end

    it "prints the unsafe-but-fast settings and the configured port" do
      out, _e, st = sh({ "TEST_PG_PORT" => "5439" }, script, "--print-conf")
      expect(st).to be_success
      %w[fsync synchronous_commit full_page_writes].each { |k| expect(out).to match(/^#{k} = off$/) }
      expect(out).to match(/^port = 5439$/)
      expect(out).to match(/^shared_buffers = 256MB$/)
      expect(out).to match(/^max_locks_per_transaction = 256$/)
    end

    it "refuses to manage port 5432" do
      _o, err, st = sh({ "TEST_PG_PORT" => "5432" }, script, "--print-conf")
      expect(st).not_to be_success
      expect(err).to match(/5432/)
    end

    it "--help does not leak the shell options line" do
      out, _e, _st = sh({}, script, "--help")
      expect(out).to include("Usage:")
      expect(out).not_to include("set -euo pipefail")
    end

    describe "start" do
      let(:dir) { File.join(@tmp, "data") }

      it "initialises, writes the managed conf, marks the dir and makes a superuser role" do
        out, err, st = sh(env_for(dir), script, "start")
        expect(st).to be_success, err
        expect(out).to match(/started: port #{@port}/)
        expect(File).to exist(File.join(dir, ".test-pg-tmpfs"))
        conf = File.read(File.join(dir, "postgresql.conf"))
        expect(conf).to match(/^port = #{@port}$/)
        expect(conf).to match(/^fsync = off$/)
        log = File.read(@log)
        expect(log).to match(/CREATE ROLE powernode WITH SUPERUSER LOGIN/)
        expect(log).not_to match(/NOSUPERUSER/)
      end

      it "is idempotent: a second start is a no-op" do
        sh(env_for(dir), script, "start")
        out, _e, st = sh(env_for(dir), script, "start")
        expect(st).to be_success
        expect(out).to match(/already running/)
        expect(File.read(File.join(dir, "postgresql.conf")).scan("test-pg-tmpfs managed >>>").size).to eq(1)
      end

      it "removes a stale postmaster.pid before starting" do
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, "PG_VERSION"), "16\n")
        File.write(File.join(dir, "postgresql.conf"), "")
        File.write(File.join(dir, "postmaster.pid"), "999999\n#{dir}\n")
        out, err, st = sh(env_for(dir), script, "start")
        expect(st).to be_success, err
        expect(out).to match(/removing stale postmaster\.pid/)
        expect(File).not_to exist(File.join(dir, "postmaster.pid"))
        expect(File.read(@log)).to match(/pg_ctl start/)
      end

      it "fails loudly when the port is held by another process" do
        srv = TCPServer.new("127.0.0.1", @port)
        _o, err, st = sh(env_for(dir), script, "start")
        expect(st).not_to be_success
        expect(err).to match(/port #{@port} is already taken/)
      ensure
        srv&.close
      end
    end

    describe "destroy" do
      def marked_dir(path)
        FileUtils.mkdir_p(path)
        File.write(File.join(path, "PG_VERSION"), "16\n")
        FileUtils.touch(File.join(path, ".test-pg-tmpfs"))
        path
      end

      it "removes a marked data dir under /tmp" do
        dir = marked_dir(File.join(@tmp, "data"))
        _o, err, st = sh(env_for(dir), script, "destroy")
        expect(st).to be_success, err
        expect(File).not_to exist(dir)
      end

      it "refuses a dir without the marker" do
        dir = File.join(@tmp, "plain")
        FileUtils.mkdir_p(dir)
        _o, err, st = sh(env_for(dir), script, "destroy")
        expect(st).not_to be_success
        expect(err).to match(/refusing to destroy/)
        expect(File).to exist(dir)
      end

      # Guard-level only: these must never be fed to a real `destroy` (a broken guard would rm -rf them).
      ["/tmp", "/tmp/", "/dev/shm", "/dev/shm/", "/", "/tmp/.", "/tmp//"].each do |root_dir|
        it "the guard rejects the bare root #{root_dir.inspect}" do
          _o, _e, st = lib_call(lib, {}, "test_pg_safe_to_destroy", root_dir)
          expect(st).not_to be_success
        end
      end

      it "the guard prints the canonical path it validated (callers remove exactly that)" do
        dir = marked_dir(File.join(@tmp, "a", "..", "data"))
        out, _e, st = lib_call(lib, {}, "test_pg_safe_to_destroy", dir)
        expect(st).to be_success
        expect(out.strip).to eq(File.join(@tmp, "data"))
      end

      it "the guard rejects a traversal even when the resolved target is marked" do
        outside = Dir.mktmpdir("outside", Dir.home)
        FileUtils.touch(File.join(outside, ".test-pg-tmpfs"))
        _o, _e, st = lib_call(lib, {}, "test_pg_safe_to_destroy", "/tmp/../#{outside.delete_prefix('/')}")
        expect(st).not_to be_success
      ensure
        FileUtils.rm_rf(outside) if outside
      end
    end
  end

  describe "test_pg_env_opt_in (prepare-worktree.sh --tmpfs-pg)" do
    around do |ex|
      Dir.mktmpdir("optin", "/tmp") do |d|
        @tmp = d
        @bin = File.join(d, "bin")
        FileUtils.mkdir_p(@bin)
        ex.run
      end
    end

    def fake_pg_ctl(exit_code)
      path = File.join(@bin, "pg_ctl")
      File.write(path, "#!/usr/bin/env bash\nexit #{exit_code}\n")
      FileUtils.chmod(0o755, path)
    end

    def opt_in(lib, envfile)
      dir = File.join(@tmp, "data")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "PG_VERSION"), "16\n")
      lib_call(lib, { "TEST_PG_BIN" => @bin, "TEST_PG_DIR" => dir, "TEST_PG_PORT" => "5433" },
               "test_pg_env_opt_in", envfile)
    end

    it "writes DATABASE_PORT only when the cluster is running, replacing an export-style line" do
      fake_pg_ctl(0)
      f = File.join(@tmp, ".env.test.local")
      File.write(f, "TEST_ENV_NUMBER=_x\nexport DATABASE_PORT=\"9999\"\n")
      _o, _e, st = opt_in(lib, f)
      expect(st).to be_success
      expect(File.read(f).lines.grep(/DATABASE_PORT/)).to eq(["DATABASE_PORT=5433\n"])
      expect(File.read(f)).to include("TEST_ENV_NUMBER=_x")
    end

    it "leaves the env file untouched when the cluster is not running" do
      fake_pg_ctl(3)
      f = File.join(@tmp, ".env.test.local")
      File.write(f, "TEST_ENV_NUMBER=_x\n")
      _o, _e, st = opt_in(lib, f)
      expect(st).not_to be_success
      expect(File.read(f)).to eq("TEST_ENV_NUMBER=_x\n")
    end

    it "is wired into prepare-worktree.sh behind --tmpfs-pg" do
      src = File.read(File.join(root, "scripts", "prepare-worktree.sh"))
      expect(src).to match(/--tmpfs-pg\) TMPFS_PG=1/)
      expect(src).to include("test_pg_env_opt_in")
    end
  end
end
