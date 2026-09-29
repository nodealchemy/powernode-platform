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
    class H(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a): pass
        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
            tool = body['params']['name']
            cfg = json.load(open(cfg_path))
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
    sh!("git", "add", "c0.txt", chdir: @work)
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
                                          { success: true, module_build_batch: { id: "batch-1", status: "complete", modules: [] } } ],
      "system_list_modules" => [ { success: true, modules: [ { id: "id-hub", name: "hub-backend" }, { id: "id-ext", name: "module-ext" } ],
                                  has_more: false } ],
      "system_promote_module_version" => [ { success: true, promoted: true } ],
      "dev_complete_task" => [ { success: true, task_status: "passed" } ]
    )
  end

  def run_land(*args, env: {})
    full_env = {
      "POWERNODE_LOCAL_CONFIG" => "none", "LAND_REPO_ROOT" => @work,
      "LAND_MCP_URL" => "http://127.0.0.1:#{@port}/", "POWERNODE_MCP_TOKEN" => token,
      "LAND_EXT_PATH" => "extensions/widgets",
      "LAND_POLL_INTERVAL" => "0", "LAND_POLL_TIMEOUT" => "20",
      "GIT_AUTHOR_NAME" => "T", "GIT_AUTHOR_EMAIL" => "t@example.invalid",
      "GIT_COMMITTER_NAME" => "T", "GIT_COMMITTER_EMAIL" => "t@example.invalid"
    }.merge(env)
    out, err, st = Open3.capture3(full_env, script, "IMP-x1", *args)
    [ out, err, st.exitstatus ]
  end

  let(:base_args) { [ "--core-sha", @core_sha, "--ext-sha", @ext_sha, "--modules", "hub-backend,module-ext",
                     "--skip-verify", "--skip-catalog-check" ] }

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
    expect(tools.uniq).to eq(%w[platform.system_dispatch_module_build_batch platform.system_get_module_build_batch
                                platform.system_list_modules platform.system_promote_module_version])
    dispatch = calls.find { |c| c["tool"].end_with?("dispatch_module_build_batch") }["args"]
    expect(dispatch).to include("base_sha" => @base_tip, "head_sha" => tip, "module_slugs" => %w[hub-backend module-ext],
                                "expand_dependents" => false)
    promotes = calls.select { |c| c["tool"].end_with?("promote_module_version") }.map { |c| c["args"].values_at("environment", "module_id") }
    expect(promotes).to eq([ %w[staging id-hub], %w[staging id-ext], %w[ops id-hub], %w[ops id-ext] ])

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
    out, _err, code = run_land(*base_args, "--evidence", evidence, "--complete", "--loop", "loop-1")
    expect(code).to eq(0)
    complete = calls.find { |c| c["tool"] == "platform.dev_complete_task" }["args"]
    expect(complete).to include("loop_id" => "loop-1", "task_key" => "IMP-x1", "outcome" => "passed", "commit_sha" => remote_tip)
    expect(complete.dig("check_results", "evidence")).to include("framework" => "rspec", "passed" => 9)
    expect(JSON.parse(out)).to include("commit_sha" => remote_tip)
  end

  it "is idempotent: a second run finds everything on the target and pushes nothing" do
    happy_mock
    run_land(*base_args)
    tip = remote_tip

    _out, err, code = run_land(*base_args)

    expect(code).to eq(0), err
    expect(remote_tip).to eq(tip)
    expect(err).to match(/already on develop/)
  end

  it "stops at a failed build batch and promotes nothing" do
    mock(
      "system_dispatch_module_build_batch" => [ { success: true, module_build_batch: { id: "batch-1" } } ],
      "system_get_module_build_batch" => [ { success: true, module_build_batch: { status: "failed", modules: [ { module: "hub-backend", state: "failed" } ] } } ]
    )
    _out, err, code = run_land(*base_args)

    expect(code).to eq(1)
    expect(err).to match(/ended failed: hub-backend=failed; nothing was promoted/)
    expect(calls.map { |c| c["tool"] }).not_to include("platform.system_promote_module_version")
  end

  it "stops when a tool refuses" do
    mock("system_dispatch_module_build_batch" => [ { success: false, error: "planner refused the range" } ])
    _out, err, code = run_land(*base_args)

    expect(code).to eq(1)
    expect(err).to match(/planner refused the range/)
    expect(calls.size).to eq(1)
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
    expect(err).to match(/hub verification failed/)
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
