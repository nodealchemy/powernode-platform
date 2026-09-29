# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"
require "json"
require "fileutils"

# IMP-6d060f65ccae — scripts/land.sh. Real git (bare "remotes" plus working clones) and a local
# mock MCP server that records every JSON-RPC call, so the whole path is exercised: scan,
# fast-forward check, push, gitlink bump, build dispatch/poll, promote, verify, evidence.
#
# NOT covered: a live control plane. The wire format follows scripts/mcp-smoke-test.sh and the verb
# definitions; see the STATUS OF THE WIRE FORMAT note in the script.
RSpec.describe "scripts/land.sh" do
  let(:script) { File.expand_path("../../../scripts/land.sh", __dir__) }
  let(:token) { "tok-#{'z' * 24}" }

  MOCK_SERVER = <<~'PY'
    import json, sys, http.server
    cfg_path, log_path, port_path = sys.argv[1:4]
    counters = {}
    epoch = [None]
    class H(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a): pass
        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
            tool = body['params']['name']
            cfg = json.load(open(cfg_path))
            if cfg.get('_epoch') != epoch[0]:
                counters.clear(); epoch[0] = cfg.get('_epoch')
            with open(log_path, 'a') as f:
                f.write(json.dumps({'tool': tool, 'args': body['params']['arguments'],
                                    'auth': self.headers.get('Authorization')}) + "\n")
            seq = cfg.get(tool.split('.', 1)[-1], [{'success': True}])
            i = counters.get(tool, 0); counters[tool] = i + 1
            item = seq[min(i, len(seq) - 1)]
            out = json.dumps({'jsonrpc': '2.0', 'id': body['id'],
                              'result': {'content': [{'type': 'text', 'text': json.dumps(item)}]}}).encode()
            self.send_response(200); self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(out))); self.end_headers(); self.wfile.write(out)
    s = http.server.HTTPServer(('127.0.0.1', 0), H)
    open(port_path, 'w').write(str(s.server_address[1]))
    s.serve_forever()
  PY

  def sh!(*cmd, chdir: nil, env: {})
    out, err, st = Open3.capture3({ "GIT_AUTHOR_NAME" => "T", "GIT_AUTHOR_EMAIL" => "t@example.invalid",
                                    "GIT_COMMITTER_NAME" => "T", "GIT_COMMITTER_EMAIL" => "t@example.invalid" }.merge(env),
                                  *cmd, chdir: chdir || @dir)
    raise "#{cmd.join(' ')} failed: #{err}" unless st.success?

    out.strip
  end

  def commit_file(repo, name, msg)
    File.write(File.join(repo, name), "#{name}-#{rand(1e9)}\n")
    sh!("git", "add", name, chdir: repo)
    sh!("git", "commit", "-q", "-m", msg, chdir: repo)
    sh!("git", "rev-parse", "HEAD", chdir: repo)
  end

  around do |example|
    Dir.mktmpdir("land-spec") do |dir|
      @dir = dir
      @cfg = File.join(dir, "mock.json")
      @log = File.join(dir, "calls.jsonl")
      File.write(@cfg, "{}")
      File.write(File.join(dir, "mock.py"), MOCK_SERVER)
      port_file = File.join(dir, "port")
      pid = Process.spawn("python3", File.join(dir, "mock.py"), @cfg, @log, port_file, %i[out err] => File::NULL)
      begin
        50.times { break if File.exist?(port_file) && !File.read(port_file).empty?; sleep 0.1 }
        @port = File.read(port_file).to_i
        example.run
      ensure
        Process.kill("TERM", pid)
        Process.wait(pid)
      end
    end
  end

  before do
    %w[core.git ext.git].each { |r| sh!("git", "init", "-q", "--bare", "-b", "develop", File.join(@dir, r)) }
    @work = File.join(@dir, "work")
    @ext = File.join(@work, "extensions/widgets")
    sh!("git", "clone", "-q", File.join(@dir, "core.git"), @work)
    sh!("git", "checkout", "-q", "-b", "develop", chdir: @work)
    FileUtils.mkdir_p(File.dirname(@ext))
    sh!("git", "clone", "-q", File.join(@dir, "ext.git"), @ext)
    sh!("git", "checkout", "-q", "-b", "develop", chdir: @ext)
    @ext_base = commit_file(@ext, "e0.txt", "ext base")
    sh!("git", "push", "-q", "origin", "develop", chdir: @ext)
    File.write(File.join(@work, "c0.txt"), "base\n")
    File.write(File.join(@work, ".gitmodules"), "[submodule \"widgets\"]\n\tpath = extensions/widgets\n\turl = ../ext.git\n")
    sh!("git", "add", "c0.txt", ".gitmodules", chdir: @work)
    sh!("git", "update-index", "--add", "--cacheinfo", "160000,#{@ext_base},extensions/widgets", chdir: @work)
    sh!("git", "commit", "-q", "-m", "core base", chdir: @work)
    sh!("git", "push", "-q", "origin", "develop", chdir: @work)
    @base_tip = sh!("git", "rev-parse", "HEAD", chdir: @work)
    FileUtils.mkdir_p(File.join(@work, "extensions/private/secret-ext"))

    @core_sha = commit_file(@work, "c1.txt", "core: reviewed change")
    @ext_sha = commit_file(@ext, "e1.txt", "ext: reviewed change")
  end

  def calls
    File.exist?(@log) ? File.readlines(@log).map { |l| JSON.parse(l) } : []
  end

  def mock(tool_responses)
    File.write(@cfg, JSON.generate(tool_responses))
  end

  def remote_tip(name = "core.git")
    sh!("git", "--git-dir", File.join(@dir, name), "rev-parse", "develop")
  end

  def happy_mock
    mock(
      "system_dispatch_module_build_batch" => [ { success: true, module_build_batch: { id: "batch-1", status: "dispatched" } } ],
      "system_get_module_build_batch" => [ { success: true, module_build_batch: { id: "batch-1", status: "dispatched", modules: [] } },
                                          { success: true, module_build_batch: { id: "batch-1", status: "complete", modules: built_modules } } ],
      # before the dispatch (hub, ext), then after the build (hub, ext)
      "system_list_module_versions" => [ { success: true, versions: [ { id: "vh-1", version_number: 1 } ] },
                                         { success: true, versions: [ { id: "ve-1", version_number: 1 } ] },
                                         { success: true, versions: [ { id: "vh-2", version_number: 2 }, { id: "vh-1", version_number: 1 } ] },
                                         { success: true, versions: [ { id: "ve-2", version_number: 2 }, { id: "ve-1", version_number: 1 } ] } ],
      "system_list_modules" => [ { success: true, modules: [ { id: "id-hub", name: "hub-backend" }, { id: "id-ext", name: "module-ext" } ],
                                  has_more: false } ],
      "system_promote_module_version" => [ { success: true, promoted: true } ],
      "dev_complete_task" => [ { success: true, task_status: "passed" } ]
    )
  end

  def built_modules
    [ { module: "hub-backend", state: "succeeded" }, { module: "module-ext", state: "succeeded" } ]
  end

  def run_land(*args, env: {})
    full_env = {
      "POWERNODE_LOCAL_CONFIG" => "none", "LAND_REPO_ROOT" => @work,
      "LAND_MCP_URL" => "http://127.0.0.1:#{@port}/", "POWERNODE_MCP_TOKEN" => token,
      "LAND_EXT_PATH" => "extensions/widgets", "LAND_PROMOTE_ENVS" => "staging ops",
      "LAND_POLL_INTERVAL" => "0", "LAND_POLL_TIMEOUT" => "20",
      "LAND_VERIFY_INTERVAL" => "0", "LAND_VERIFY_TIMEOUT" => "0",
      "GIT_AUTHOR_NAME" => "T", "GIT_AUTHOR_EMAIL" => "t@example.invalid",
      "GIT_COMMITTER_NAME" => "T", "GIT_COMMITTER_EMAIL" => "t@example.invalid"
    }.merge(env)
    out, err, st = Open3.capture3(full_env, script, "IMP-x1", *args)
    [ out, err, st.exitstatus ]
  end

  let(:base_args) { [ "--core-sha", @core_sha, "--ext-sha", @ext_sha, "--modules", "hub-backend,module-ext",
                     "--skip-verify", "--skip-catalog-check" ] }

  describe "--dry-run is inert" do
    # Runs a COPY of the scripts so a stub catalog check can prove it was never invoked, with an empty TMPDIR to
    # prove no token file was written. Everything mutable is snapshotted before and after.
    let(:copy) { File.join(@dir, "lscripts") }
    let(:tmpdir) { File.join(@dir, "tmp") }

    before do
      FileUtils.mkdir_p([ File.join(copy, "lib"), tmpdir, File.join(@dir, "worker/app/services/devops") ])
      FileUtils.cp(script, File.join(copy, "land.sh"))
      Dir[File.join(File.dirname(script), "lib/*")].each { |f| FileUtils.cp(f, File.join(copy, "lib")) }
      FileUtils.cp(File.expand_path("../../../worker/app/services/devops/commit_message_hygiene.rb", __dir__),
                   File.join(@dir, "worker/app/services/devops/commit_message_hygiene.rb"))
      File.write(File.join(copy, "check-mcp-catalog-fresh.sh"), "#!/usr/bin/env bash\ntouch #{@dir}/catalog-was-run\n")
      File.chmod(0o755, File.join(copy, "check-mcp-catalog-fresh.sh"))
    end

    def snapshot
      repos = { work: @work, ext: @ext, core_remote: File.join(@dir, "core.git"), ext_remote: File.join(@dir, "ext.git") }
      repos.transform_values do |r|
        git_dir = File.exist?(File.join(r, ".git")) ? File.join(r, ".git") : r
        {
          # ALL refs, remote-tracking included: a fetch would move them
          refs: sh!("git", "--git-dir", git_dir, "for-each-ref", "--format=%(objectname) %(refname)").lines,
          fetch_head: File.exist?(File.join(git_dir, "FETCH_HEAD")) ? File.read(File.join(git_dir, "FETCH_HEAD")) : :absent,
          loose: sh!("git", "--git-dir", git_dir, "count-objects").split.first,
          status: File.exist?(File.join(r, ".git")) ? sh!("git", "-C", r, "status", "--porcelain", "--ignored") : nil
        }
      end
    end

    def dry_env
      { "POWERNODE_LOCAL_CONFIG" => "none", "LAND_REPO_ROOT" => @work, "LAND_MCP_URL" => "http://127.0.0.1:#{@port}/",
        "POWERNODE_MCP_TOKEN" => token, "LAND_EXT_PATH" => "extensions/widgets", "LAND_PROMOTE_ENVS" => "staging ops",
        "TMPDIR" => tmpdir, "GIT_AUTHOR_NAME" => "T", "GIT_AUTHOR_EMAIL" => "t@example.invalid",
        "GIT_COMMITTER_NAME" => "T", "GIT_COMMITTER_EMAIL" => "t@example.invalid" }
    end

    it "does not fetch: when the remote target moved to a commit this clone lacks, it says so and changes nothing" do
      other = File.join(@dir, "other")
      sh!("git", "clone", "-q", "-b", "develop", File.join(@dir, "core.git"), other)
      commit_file(other, "elsewhere.txt", "someone else landed")
      sh!("git", "push", "-q", "origin", "develop", chdir: other)
      before = snapshot
      _out, err, code = Open3.capture3(dry_env, File.join(copy, "land.sh"), "IMP-x1", *base_args, "--dry-run").then { |o, e, st| [ o, e, st.exitstatus ] }

      expect(code).to eq(1)
      expect(err).to match(/not in this clone; --dry-run does not fetch/)
      expect(snapshot).to eq(before)
      expect(snapshot[:work][:fetch_head]).to eq(:absent)
    end

    it "reads the remote tips with ls-remote and leaves every ref and FETCH_HEAD untouched" do
      happy_mock
      before = snapshot
      _out, err, code = Open3.capture3(dry_env, File.join(copy, "land.sh"), "IMP-x1", *base_args, "--dry-run").then { |o, e, st| [ o, e, st.exitstatus ] }

      expect(code).to eq(0), err
      expect(err).to match(/step 0: read the remote develop tips \(git ls-remote; --dry-run does not fetch\)/)
      expect(snapshot).to eq(before)
      expect(snapshot[:work][:fetch_head]).to eq(:absent)
      expect(snapshot[:ext][:fetch_head]).to eq(:absent)
    end

    it "runs the catalog freshness check against the repository, not the caller's working directory (outside --dry-run)" do
      happy_mock
      File.write(File.join(copy, "check-mcp-catalog-fresh.sh"), "#!/usr/bin/env bash\npwd -P > #{@dir}/catalog-cwd\n")
      elsewhere = File.join(@dir, "elsewhere")
      FileUtils.mkdir_p(elsewhere)
      _out, err, st = Open3.capture3(dry_env, File.join(copy, "land.sh"), "IMP-x1", *(base_args - [ "--skip-catalog-check" ]), chdir: elsewhere)

      expect(st.exitstatus).to eq(0), err
      expect(File.read(File.join(@dir, "catalog-cwd")).strip).to eq(File.realpath(@work))
    end

    [ %w[git], %w[mcp], %w[none] ].each do |(mode)|
      it "changes nothing (--merge-via #{mode}, --complete, no --skip-catalog-check)" do
        happy_mock
        args = [ "--core-sha", @core_sha, "--ext-sha", @ext_sha, "--modules", "hub-backend,module-ext", "--skip-verify",
                 "--merge-via", mode, "--complete", "--loop", "loop-1", "--evidence", '{"framework":"rspec","passed":1,"failed":0}',
                 "--core-source-ref", "feat-core", "--ext-source-ref", "feat-ext", "--attest", '{"passed":1}', "--dry-run" ]
        before = snapshot
        full_env = { "POWERNODE_LOCAL_CONFIG" => "none", "LAND_REPO_ROOT" => @work, "LAND_MCP_URL" => "http://127.0.0.1:#{@port}/",
                     "POWERNODE_MCP_TOKEN" => token, "LAND_EXT_PATH" => "extensions/widgets", "LAND_PROMOTE_ENVS" => "staging ops",
                     "LAND_CORE_REPOSITORY" => "owner/core", "LAND_EXT_REPOSITORY" => "owner/ext", "TMPDIR" => tmpdir,
                     "GIT_AUTHOR_NAME" => "T", "GIT_AUTHOR_EMAIL" => "t@example.invalid",
                     "GIT_COMMITTER_NAME" => "T", "GIT_COMMITTER_EMAIL" => "t@example.invalid" }
        out, err, st = Open3.capture3(full_env, File.join(copy, "land.sh"), "IMP-x1", *args)

        expect(err).to include("(dry-run) would: run the catalog freshness check")
        expect(err).not_to match(/BUG: an MCP call/)
        expect(snapshot).to eq(before)
        expect(calls).to be_empty
        expect(File.exist?(File.join(@dir, "catalog-was-run"))).to be false
        expect(File.exist?(File.join(@work, "scripts/local/land-state"))).to be false
        expect(Dir.children(tmpdir)).to eq([]), "left files in TMPDIR: #{Dir.children(tmpdir)}"
        expect(out).not_to include(token)
        expect(err).not_to include(token)
        expect(st.exitstatus).to eq(0), err unless mode == "none" # "none" correctly refuses: nothing is on the target yet
      end
    end
  end

  it "--dry-run does the read-only checks, pushes nothing and calls nothing" do
    happy_mock
    out, err, code = run_land(*base_args, "--dry-run")

    expect(code).to eq(0), err
    expect(remote_tip).to eq(@base_tip)
    expect(remote_tip("ext.git")).to eq(@ext_base)
    expect(calls).to be_empty
    expect(err).to match(/\(dry-run\) would: push extension/)
    expect(err).to match(/\(dry-run\) would: dispatch_module_build_batch/)
    expect(JSON.parse(out).dig("check_results", "landing", "dry_run")).to be true
  end

  it "lands extension then core then a gitlink bump, builds, promotes in order and prints the evidence" do
    happy_mock
    out, err, code = run_land(*base_args)

    expect(code).to eq(0), err
    expect(remote_tip("ext.git")).to eq(@ext_sha)
    tip = remote_tip
    expect(sh!("git", "rev-parse", "#{tip}^", chdir: @work)).to eq(@core_sha)
    expect(sh!("git", "ls-tree", tip, "extensions/widgets", chdir: @work).split[2]).to eq(@ext_sha)
    expect(sh!("git", "log", "-1", "--format=%s", tip, chdir: @work)).to eq("chore(widgets): bump extension pointer to #{@ext_sha[0, 12]}")

    tools = calls.map { |c| c["tool"] }
    expect(tools.uniq).to eq(%w[platform.system_list_modules platform.system_list_module_versions
                                platform.system_dispatch_module_build_batch platform.system_get_module_build_batch
                                platform.system_promote_module_version])
    dispatch = calls.find { |c| c["tool"].end_with?("dispatch_module_build_batch") }["args"]
    expect(dispatch).to include("base_sha" => @base_tip, "head_sha" => tip, "module_slugs" => %w[hub-backend module-ext],
                                "expand_dependents" => false)
    promotes = calls.select { |c| c["tool"].end_with?("promote_module_version") }
                    .map { |c| c["args"].values_at("environment", "module_id", "version_id") }
    expect(promotes).to eq([ %w[staging id-hub vh-2], %w[staging id-ext ve-2], %w[ops id-hub vh-2], %w[ops id-ext ve-2] ])

    landing = JSON.parse(out).dig("check_results", "landing")
    expect(landing).to include("landed_core_sha" => tip, "landed_ext_sha" => @ext_sha, "batch_id" => "batch-1",
                               "batch_status" => "complete", "dry_run" => false)
    expect(landing["hub_verification"]).to eq("status" => "skipped")
  end

  it "keeps the bearer token out of stdout and stderr and sends it as the Authorization header" do
    happy_mock
    out, err, _code = run_land(*base_args)

    expect(out + err).not_to include(token)
    expect(calls.map { |c| c["auth"] }.uniq).to eq([ "Bearer #{token}" ])
  end

  it "calls dev_complete_task with the evidence only when asked to" do
    happy_mock
    evidence = '{"framework":"rspec","passed":9,"failed":0,"command":"x"}'
    run_land(*base_args, "--evidence", evidence)
    expect(calls.map { |c| c["tool"] }).not_to include("platform.dev_complete_task")

    File.delete(@log)
    reset_mock
    out, _err, code = run_land(*base_args, "--evidence", evidence, "--complete", "--loop", "loop-1")
    expect(code).to eq(0)
    complete = calls.find { |c| c["tool"] == "platform.dev_complete_task" }["args"]
    expect(complete).to include("loop_id" => "loop-1", "task_key" => "IMP-x1", "outcome" => "passed", "commit_sha" => remote_tip)
    expect(complete.dig("check_results", "evidence")).to include("framework" => "rspec", "passed" => 9)
    expect(JSON.parse(out)).to include("commit_sha" => remote_tip)
  end

  def dispatches
    calls.select { |c| c["tool"].end_with?("dispatch_module_build_batch") }.map { |c| c["args"].values_at("base_sha", "head_sha") }
  end

  def reset_mock(extra = {})
    cfg = JSON.parse(File.read(@cfg)).merge("_epoch" => rand(1e9)).merge(extra)
    File.write(@cfg, JSON.generate(cfg))
  end

  it "is idempotent: a second run pushes nothing and builds the SAME range, not an empty one" do
    happy_mock
    run_land(*base_args)
    tip = remote_tip
    expect(dispatches).to eq([ [ @base_tip, tip ] ])

    File.delete(@log)
    reset_mock
    _out, err, code = run_land(*base_args)

    expect(code).to eq(0), err
    expect(remote_tip).to eq(tip)
    expect(err).to match(/already on develop/)
    expect(dispatches).to eq([ [ @base_tip, tip ] ])
  end

  it "records the pre-merge base in a state file that survives a parked-then-resumed run" do
    happy_mock
    run_land(*base_args)
    state = JSON.parse(File.read(File.join(@work, "scripts/local/land-state/IMP-x1.json")))

    expect(state).to include("base_sha" => @base_tip, "core_sha" => @core_sha, "ext_sha" => @ext_sha)
  end

  it "with --merge-via none and nothing recorded, refuses rather than building an empty range, until --base-sha names the base" do
    happy_mock
    sh!("git", "push", "-q", File.join(@dir, "core.git"), "#{@core_sha}:refs/heads/develop", chdir: @work)
    sh!("git", "push", "-q", File.join(@dir, "ext.git"), "#{@ext_sha}:refs/heads/develop", chdir: @ext)
    # the pointer is on target too: pretend a person landed everything
    tip = remote_tip
    idx = File.join(@dir, "idx")
    sh!("git", "read-tree", tip, chdir: @work, env: { "GIT_INDEX_FILE" => idx })
    sh!("git", "update-index", "--cacheinfo", "160000,#{@ext_sha},extensions/widgets", chdir: @work, env: { "GIT_INDEX_FILE" => idx })
    tree = sh!("git", "write-tree", chdir: @work, env: { "GIT_INDEX_FILE" => idx })
    ptr = sh!("git", "commit-tree", tree, "-p", tip, "-m", "chore(widgets): bump", chdir: @work)
    sh!("git", "push", "-q", File.join(@dir, "core.git"), "#{ptr}:refs/heads/develop", chdir: @work)

    args = base_args + [ "--merge-via", "none" ]
    _out, err, code = run_land(*args)
    expect(code).to eq(1)
    expect(err).to match(/build range's base is unknown/)
    expect(calls).to be_empty

    _out, err, code = run_land(*args, "--base-sha", @base_tip)
    expect(code).to eq(0), err
    expect(dispatches).to eq([ [ @base_tip, ptr ] ])
  end

  it "refuses an empty build range with a clear message and dispatches nothing" do
    happy_mock
    run_land(*base_args)
    File.delete(@log)
    reset_mock
    tip = remote_tip
    _out, err, code = run_land(*base_args, "--base-sha", tip)

    expect(code).to eq(1)
    expect(err).to match(/build range .* is empty/)
    expect(calls).to be_empty
  end

  it "skips an environment whose pin already serves the built version, logs it, and records it as already current" do
    happy_mock
    mock_cfg = JSON.parse(File.read(@cfg))
    mock_cfg["system_list_module_versions"][2] = { success: true, versions: [ { id: "vh-2", version_number: 2, pinned_in: [ "staging" ] }, { id: "vh-1", version_number: 1 } ] }
    File.write(@cfg, JSON.generate(mock_cfg))
    out, err, code = run_land(*base_args)

    expect(code).to eq(0), err
    promotes = calls.select { |c| c["tool"].end_with?("promote_module_version") }.map { |c| c["args"].values_at("environment", "module_id") }
    expect(promotes).to eq([ %w[staging id-ext], %w[ops id-hub], %w[ops id-ext] ])
    expect(err).to match(/hub-backend already current in staging/)
    promoted = JSON.parse(out).dig("check_results", "landing", "promoted")
    expect(promoted).to include(a_hash_including("environment" => "staging", "module" => "hub-backend", "status" => "already_current"))
    expect(promoted).to include(a_hash_including("environment" => "ops", "module" => "hub-backend", "status" => "promoted"))
  end

  it "takes the promotion environments from configuration or --promote-envs, with no default" do
    happy_mock
    _out, err, code = run_land(*base_args, env: { "LAND_PROMOTE_ENVS" => "" })
    expect(code).to eq(2)
    expect(err).to match(/no promotion environments configured/)
    expect(calls).to be_empty

    _out, err, code = run_land(*base_args, "--promote-envs", "canary", env: { "LAND_PROMOTE_ENVS" => "" })
    expect(code).to eq(0), err
    expect(calls.select { |c| c["tool"].end_with?("promote_module_version") }.map { |c| c["args"]["environment"] }.uniq).to eq(%w[canary])
  end

  it "pins the exact version each build published when promoting" do
    happy_mock
    run_land(*base_args)
    versions = calls.select { |c| c["tool"].end_with?("promote_module_version") }.map { |c| c["args"]["version_id"] }

    expect(versions).to eq(%w[vh-2 ve-2 vh-2 ve-2])
  end

  it "refuses to promote when a requested module did not build, or built no new version" do
    happy_mock
    mock_cfg = JSON.parse(File.read(@cfg))
    mock_cfg["system_get_module_build_batch"] = [ { success: true, module_build_batch: { status: "complete", modules: [ { module: "hub-backend", state: "succeeded" } ] } } ]
    File.write(@cfg, JSON.generate(mock_cfg))
    _out, err, code = run_land(*base_args)
    expect(code).to eq(1)
    expect(err).to match(/module 'module-ext' is not in the build batch/)
    expect(calls.map { |c| c["tool"] }).not_to include("platform.system_promote_module_version")

    File.delete(@log)
    happy_mock
    mock_cfg = JSON.parse(File.read(@cfg)).merge("_epoch" => 2)
    mock_cfg["system_list_module_versions"] = [ { success: true, versions: [ { id: "vh-1", version_number: 1 } ] } ]
    File.write(@cfg, JSON.generate(mock_cfg))
    _out, err, code = run_land(*base_args, "--base-sha", @base_tip)
    expect(code).to eq(1)
    expect(err).to match(/no version newer than #1 exists/)
    expect(calls.map { |c| c["tool"] }).not_to include("platform.system_promote_module_version")
  end

  it "does not promote a module whose build was a no-op" do
    happy_mock
    mock_cfg = JSON.parse(File.read(@cfg))
    mock_cfg["system_get_module_build_batch"] = [ { success: true, module_build_batch: { status: "complete", modules: [
      { module: "hub-backend", state: "succeeded" }, { module: "module-ext", state: "succeeded", outcome: "noop_identical" } ] } } ]
    File.write(@cfg, JSON.generate(mock_cfg))
    _out, err, code = run_land(*base_args)

    expect(code).to eq(0), err
    promoted = calls.select { |c| c["tool"].end_with?("promote_module_version") }.map { |c| c["args"]["module_id"] }
    expect(promoted).to eq(%w[id-hub id-hub])
    expect(err).to match(/module-ext not promoted into staging: build was a no-op/)
  end

  describe "private extensions" do
    it "never creates a core pointer commit or a core commit naming the extension, and rejects the path as a core gitlink" do
      priv = File.join(@work, "extensions/private/priv-ext")
      sh!("git", "init", "-q", "--bare", "-b", "develop", File.join(@dir, "priv.git"))
      sh!("git", "clone", "-q", File.join(@dir, "priv.git"), priv)
      sh!("git", "checkout", "-q", "-b", "develop", chdir: priv)
      commit_file(priv, "p0.txt", "priv base")
      sh!("git", "push", "-q", "origin", "develop", chdir: priv)
      priv_sha = commit_file(priv, "p1.txt", "private change")
      happy_mock
      mock_cfg = JSON.parse(File.read(@cfg))
      mock_cfg["system_list_module_versions"] = [ { success: true, versions: [ { id: "vh-1", version_number: 1 } ] },
                                                  { success: true, versions: [ { id: "vh-2", version_number: 2 } ] } ]
      File.write(@cfg, JSON.generate(mock_cfg))
      args = [ "--core-sha", @core_sha, "--ext-sha", priv_sha, "--ext-path", "extensions/private/priv-ext",
               "--modules", "hub-backend", "--skip-verify", "--skip-catalog-check" ]
      _out, err, code = run_land(*args, env: { "LAND_EXT_PATH" => "" })

      expect(code).to eq(0), err
      expect(sh!("git", "--git-dir", File.join(@dir, "priv.git"), "rev-parse", "develop")).to eq(priv_sha)
      # core got exactly the reviewed commit: no pointer commit on top, and no mention of the extension anywhere
      expect(remote_tip).to eq(@core_sha)
      expect(sh!("git", "--git-dir", File.join(@dir, "core.git"), "log", "--format=%B", "#{@base_tip}..develop")).not_to include("priv")
      expect(sh!("git", "--git-dir", File.join(@dir, "core.git"), "ls-tree", "-r", "develop")).not_to include("priv-ext")
    end
  end

  it "rejects an --ext-path that is not a submodule listed in .gitmodules" do
    _out, err, code = run_land(*base_args, "--ext-path", "extensions/other", env: { "LAND_EXT_PATH" => "" })

    expect(code).to eq(2)
    expect(err).to match(/not a submodule listed in \.gitmodules/)
    expect(calls).to be_empty
  end

  it "refuses to push a generated pointer commit that fails the publication scan" do
    sh!("git", "config", "user.name", "Some Model <noreply@example.invalid>", chdir: @work)
    happy_mock
    _out, err, code = run_land(*base_args, env: { "GIT_COMMITTER_NAME" => "Claude Opus", "GIT_AUTHOR_NAME" => "T" })

    expect(code).to eq(1)
    expect(err).to match(/generated pointer commit .* failed the publication scan/)
    expect(sh!("git", "--git-dir", File.join(@dir, "core.git"), "log", "-1", "--format=%s", "develop")).to eq("core: reviewed change")
  end

  it "polls the hub check until it goes green and records the attempts" do
    happy_mock
    counter = File.join(@dir, "attempts")
    stub = File.join(@dir, "verify-stub.sh")
    File.write(stub, <<~SH)
      #!/usr/bin/env bash
      n=$(( $(cat #{counter} 2>/dev/null || echo 0) + 1 )); echo $n > #{counter}
      if [ "$n" -lt 3 ]; then echo '{"ok":false}'; exit 1; fi
      echo '{"ok":true}'
    SH
    File.chmod(0o755, stub)
    out, err, code = run_land(*(base_args - [ "--skip-verify" ]), env: { "LAND_VERIFY_SCRIPT" => stub, "LAND_VERIFY_TIMEOUT" => "30" })

    expect(code).to eq(0), err
    expect(JSON.parse(out).dig("check_results", "landing", "hub_verification")).to include("ok" => true, "attempts" => 3)
  end

  it "stops at once when the hub check is misconfigured (exit 2), and retries a transport failure (exit 3)" do
    happy_mock
    stub = File.join(@dir, "verify-stub.sh")
    File.write(stub, "#!/usr/bin/env bash\nexit 2\n")
    File.chmod(0o755, stub)
    _out, err, code = run_land(*(base_args - [ "--skip-verify" ]), env: { "LAND_VERIFY_SCRIPT" => stub, "LAND_VERIFY_TIMEOUT" => "30" })
    expect(code).to eq(2)
    expect(err).to match(/misconfigured/)

    File.write(stub, "#!/usr/bin/env bash\nexit 3\n")
    reset_mock
    _out, err, code = run_land(*(base_args - [ "--skip-verify" ]), env: { "LAND_VERIFY_SCRIPT" => stub, "LAND_VERIFY_TIMEOUT" => "0" })
    expect(code).to eq(1)
    expect(err).to match(/still failing after 1 attempt\(s\)/)
  end

  it "stops at a failed build batch and promotes nothing" do
    happy_mock
    mock_cfg = JSON.parse(File.read(@cfg))
    mock_cfg["system_get_module_build_batch"] = [ { success: true, module_build_batch: { status: "failed", modules: [ { module: "hub-backend", state: "failed" } ] } } ]
    File.write(@cfg, JSON.generate(mock_cfg))
    _out, err, code = run_land(*base_args)

    expect(code).to eq(1)
    expect(err).to match(/ended failed: hub-backend=failed; nothing was promoted/)
    expect(calls.map { |c| c["tool"] }).not_to include("platform.system_promote_module_version")
  end

  it "stops when a tool refuses" do
    happy_mock
    mock_cfg = JSON.parse(File.read(@cfg))
    mock_cfg["system_dispatch_module_build_batch"] = [ { success: false, error: "planner refused the range" } ]
    File.write(@cfg, JSON.generate(mock_cfg))
    _out, err, code = run_land(*base_args)

    expect(code).to eq(1)
    expect(err).to match(/planner refused the range/)
    expect(calls.last["tool"]).to eq("platform.system_dispatch_module_build_batch")
    expect(calls.map { |c| c["tool"] }).not_to include("platform.system_get_module_build_batch")
  end

  it "exits 3 when a promotion parks for approval" do
    happy_mock
    mock_cfg = JSON.parse(File.read(@cfg))
    mock_cfg["system_promote_module_version"] = [ { success: true, pending: true, deferred_operation_id: "op-9" } ]
    File.write(@cfg, JSON.generate(mock_cfg))
    _out, err, code = run_land(*base_args)

    expect(code).to eq(3)
    expect(err).to match(/parked for approval/)
  end

  it "refuses a range carrying AI attribution before pushing anything" do
    sh!("git", "commit", "-q", "--amend", "-m", "core: change\n\nCo-Authored-By: Some Model <noreply@example.invalid>", chdir: @work)
    core = sh!("git", "rev-parse", "HEAD", chdir: @work)
    args = [ "--core-sha", core, "--ext-sha", @ext_sha, "--modules", "hub-backend", "--skip-verify", "--skip-catalog-check" ]
    happy_mock
    _out, err, code = run_land(*args)

    expect(code).to eq(1)
    expect(err).to match(/publication scan/)
    expect(err).to match(/ai_attribution/)
    expect(remote_tip).to eq(@base_tip)
    expect(remote_tip("ext.git")).to eq(@ext_base)
    expect(calls).to be_empty
  end

  it "refuses a private-extension name derived from extensions/private, in the extension range too" do
    sh!("git", "commit", "-q", "--amend", "-m", "ext: wire up secret-ext", chdir: @ext)
    ext = sh!("git", "rev-parse", "HEAD", chdir: @ext)
    happy_mock
    out_err = run_land("--core-sha", @core_sha, "--ext-sha", ext, "--modules", "hub-backend", "--skip-verify", "--skip-catalog-check")

    expect(out_err[2]).to eq(1)
    expect(out_err[1]).to match(/extension range .* failed the publication scan/)
    expect(out_err[1]).to match(/private_extension_name/)
    expect(out_err[1]).not_to include("secret-ext")
    expect(remote_tip).to eq(@base_tip)
  end

  it "refuses a commit that is not a fast-forward of the remote target" do
    other = File.join(@dir, "other")
    sh!("git", "clone", "-q", "-b", "develop", File.join(@dir, "core.git"), other)
    commit_file(other, "x.txt", "someone else landed")
    sh!("git", "push", "-q", "origin", "develop", chdir: other)
    happy_mock
    _out, err, code = run_land(*base_args)

    expect(code).to eq(1)
    expect(err).to match(/not a fast-forward/)
    expect(calls).to be_empty
  end

  it "runs the hub verification and fails the landing when it fails" do
    happy_mock
    stub = File.join(@dir, "verify-stub.sh")
    File.write(stub, "#!/usr/bin/env bash\necho '{\"ok\":false,\"checks\":{\"up_ok\":false}}'\nexit 1\n")
    File.chmod(0o755, stub)
    args = base_args - [ "--skip-verify" ]
    _out, err, code = run_land(*args, env: { "LAND_VERIFY_SCRIPT" => stub })

    expect(code).to eq(1)
    expect(err).to match(/hub verification still failing after 1 attempt/)
  end

  it "carries a passing hub verification into the evidence, checking the landed shas since dispatch" do
    happy_mock
    stub = File.join(@dir, "verify-stub.sh")
    File.write(stub, "#!/usr/bin/env bash\necho \"{\\\"ok\\\":true,\\\"args\\\":\\\"$*\\\"}\"\n")
    File.chmod(0o755, stub)
    out, err, code = run_land(*(base_args - [ "--skip-verify" ]), env: { "LAND_VERIFY_SCRIPT" => stub })

    expect(code).to eq(0), err
    verify = JSON.parse(out).dig("check_results", "landing", "hub_verification")
    expect(verify["ok"]).to be true
    expect(verify["args"]).to match(/\A#{remote_tip} #{@ext_sha} --since \d+\z/)
  end

  it "merges through dev_merge_increment when asked and exits 3 while it is parked" do
    mock("dev_merge_increment" => [ { success: true, pending: true, deferred_operation_id: "op-1" } ])
    _out, err, code = run_land(*base_args, "--merge-via", "mcp", "--core-source-ref", "feat-core", "--ext-source-ref", "feat-ext",
                               "--attest", '{"framework":"rspec","passed":1,"failed":0}',
                               env: { "LAND_CORE_REPOSITORY" => "owner/core", "LAND_EXT_REPOSITORY" => "owner/ext" })

    expect(code).to eq(3)
    expect(err).to match(/parked for approval/)
    merge = calls.first
    expect(merge["tool"]).to eq("platform.dev_merge_increment")
    expect(merge["args"]).to include("repository" => "owner/core", "source_ref" => "feat-core", "target_branch" => "develop",
                                     "expected_source_sha" => @core_sha)
    expect(merge["args"]["gate_attestation"]).to include("passed" => 1)
    expect(remote_tip).to eq(@base_tip)
  end

  it "exits 2 naming what is missing when the endpoint or token is not configured" do
    _out, err, code = run_land(*base_args, env: { "LAND_MCP_URL" => "" })
    expect(code).to eq(2)
    expect(err).to match(/LAND_MCP_URL/)

    _out, err, code = run_land(*base_args, env: { "POWERNODE_MCP_TOKEN" => "" })
    expect(code).to eq(2)
    expect(err).to match(/POWERNODE_MCP_TOKEN/)
  end

  it "asks which extension when --ext-sha is given and no path is configured or derivable" do
    File.open(File.join(@work, ".gitmodules"), "a") { |f| f.write("[submodule \"gadgets\"]\n\tpath = extensions/gadgets\n\turl = ../gadgets.git\n") }
    _out, err, code = run_land(*base_args, env: { "LAND_EXT_PATH" => "" })

    expect(code).to eq(2)
    expect(err).to match(/pass --ext-path or set LAND_EXT_PATH/)
    expect(calls).to be_empty
  end

  it "accepts the extension path as an option" do
    happy_mock
    _out, err, code = run_land(*base_args, "--ext-path", "extensions/widgets", env: { "LAND_EXT_PATH" => "" })

    expect(code).to eq(0), err
  end

  it "rejects malformed arguments before touching git or the network" do
    _out, err, code = run_land("--core-sha", "zzz", "--modules", "a")
    expect(code).to eq(2)
    expect(err).to match(/core-sha/)

    _out, err, code = run_land("--core-sha", @core_sha, "--modules", "a b")
    expect(code).to eq(2)
    expect(err).to match(/comma-separated/)
    expect(calls).to be_empty
  end
end
