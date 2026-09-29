# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"
require "json"
require "fileutils"

# IMP-6d060f65ccae — scripts/pre-critic-gate.sh and its changed-line RuboCop filter. The gate runs
# for real against a throwaway git repository; the heavy external tools (bundle/rubocop, npx/tsc,
# gitleaks, the catalog and leak-guard scripts, the core-purity hook) are replaced by small stubs so
# each check's PASS and FAIL arms can be driven deterministically.
RSpec.describe "scripts/pre-critic-gate.sh" do
  repo_scripts = File.expand_path("../../../scripts", __dir__)
  repo_root = File.expand_path("../../..", __dir__)

  def sh!(*cmd, chdir: nil, env: {})
    out, err, st = Open3.capture3({ "GIT_AUTHOR_NAME" => "T", "GIT_AUTHOR_EMAIL" => "t@example.invalid",
                                    "GIT_COMMITTER_NAME" => "T", "GIT_COMMITTER_EMAIL" => "t@example.invalid" }.merge(env),
                                  *cmd, chdir: chdir || @repo)
    raise "#{cmd.join(' ')} failed: #{err}" unless st.success?

    out.strip
  end

  def write(rel, body, mode: nil)
    path = File.join(@repo, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    File.chmod(mode, path) if mode
  end

  def commit_all(msg)
    sh!("git", "add", "-A")
    sh!("git", "commit", "-q", "-m", msg)
    sh!("git", "rev-parse", "HEAD")
  end

  around do |example|
    Dir.mktmpdir("gate-spec") do |dir|
      @dir = File.realpath(dir)
      @repo = File.join(@dir, "repo")
      @stubs = File.join(@dir, "stubs")
      FileUtils.mkdir_p([ @repo, @stubs ])
      example.run
    end
  end

  before do
    sh!("git", "init", "-q", "-b", "develop", @repo)
    FileUtils.mkdir_p(File.join(@repo, "scripts/lib"))
    FileUtils.cp(File.join(repo_scripts, "pre-critic-gate.sh"), File.join(@repo, "scripts/pre-critic-gate.sh"))
    %w[landing-common.sh commit-range-scan.rb changed-line-offenses.rb].each do |f|
      FileUtils.cp(File.join(repo_scripts, "lib", f), File.join(@repo, "scripts/lib", f))
    end
    FileUtils.mkdir_p(File.join(@repo, "worker/app/services/devops"))
    FileUtils.cp(File.join(repo_root, "worker/app/services/devops/commit_message_hygiene.rb"),
                 File.join(@repo, "worker/app/services/devops/commit_message_hygiene.rb"))
    FileUtils.mkdir_p(File.join(@repo, "extensions/private/hidden-ext"))
    File.write(File.join(@repo, "extensions/private/hidden-ext/.keep"), "")
    File.write(File.join(@repo, ".gitignore"), "/extensions/private/\n.claude/hooks/deployment-identifiers.local.txt\n")

    ok = "#!/usr/bin/env bash\nexit 0\n"
    write("scripts/check-mcp-catalog-fresh.sh", "#!/usr/bin/env bash\n[ -z \"${FAKE_CATALOG_FAIL:-}\" ] || { echo 'catalog is stale'; exit 1; }\n", mode: 0o755)
    %w[check-skill-executor-error-leak.sh check-tool-not-found-leak.sh].each do |g|
      write("scripts/#{g}", "#!/usr/bin/env bash\n[ \"${FAKE_LEAK_FAIL:-}\" != \"#{g}\" ] || { echo 'leak at app/x.rb:1'; exit 1; }\n", mode: 0o755)
    end
    write(".claude/hooks/core-purity-check.sh", <<~SH, mode: 0o755)
      #!/usr/bin/env bash
      f=$(jq -r .tool_input.file_path)
      grep -q HOOK_CRASH "$f" && exit 1
      grep -q FORBIDDEN_EXT "$f" && { echo "names an extension"; exit 2; }
      exit 0
    SH
    # like the real scan, it only finds anything when it was handed an identifier list that exists
    write("scripts/checks/deployment-identifier-check.sh", <<~SH, mode: 0o755)
      #!/usr/bin/env bash
      [ -f "${DEPLOYMENT_ID_LIST:-}" ] || exit 0
      [ "$1" = "--file" ] && grep -q DEPLOY_LOCAL_FACT "$2" && echo "$2:1:DEPLOY_LOCAL_FACT"
      exit 0
    SH
    write(".claude/hooks/deployment-identifiers.local.txt", "DEPLOY_LOCAL_FACT\n")

    # a nested extension checkout, recorded in core as a gitlink by the base commit
    @ext = File.join(@repo, "extensions/widgets")
    FileUtils.mkdir_p(@ext)
    sh!("git", "init", "-q", "-b", "develop", @ext)
    File.write(File.join(@ext, "w.rb"), "# frozen_string_literal: true\n")
    sh!("git", "add", "-A", chdir: @ext)
    sh!("git", "commit", "-q", "-m", "ext base", chdir: @ext)
    @ext_base = sh!("git", "rev-parse", "HEAD", chdir: @ext)

    write("server/app/models/thing.rb", "# frozen_string_literal: true\nclass Thing\nend\n")
    write("frontend/src/a.ts", "export const a = 1\n")
    write("docs/readme.md", "hello\n")
    @base = commit_all("base")

    # stubs on PATH. `bundle exec rubocop ... <files>` answers with $FAKE_RUBOCOP_JSON.
    write_stub("bundle", <<~SH)
      if [ "$1 $2" = "exec rubocop" ]; then
        cat "$FAKE_RUBOCOP_JSON"; grep -q '"offenses": *\\[ *{' "$FAKE_RUBOCOP_JSON" && exit 1; exit 0
      fi
      exit 0
    SH
    write_stub("npx", %(if [ -n "${FAKE_TSC_FAIL:-}" ]; then echo "src/a.ts(1,1): error TS2322: nope"; echo "src/b.ts(2,2): error TS2304: nope"; exit 2; fi\nexit 0))
    write_stub("gitleaks", %(echo "$@" >> "#{@dir}/gitleaks.args"\n[ -z "${FAKE_LEAK:-}" ] || { echo "Finding: REDACTED"; exit 1; }\nexit 0))
    File.write(File.join(@dir, "clean.json"), JSON.generate(files: []))
  end

  def write_stub(name, body)
    path = File.join(@stubs, name)
    File.write(path, "#!/usr/bin/env bash\n#{body}\n")
    File.chmod(0o755, path)
  end

  def rubocop_json(file, lines)
    JSON.generate(files: [ { path: file, offenses: lines.map { |l| { cop_name: "Style/X", message: "bad thing", location: { line: l } } } } ])
  end

  def gate(*args, env: {}, path: nil, script_root: nil)
    full = { "PATH" => path || "#{@stubs}:/usr/local/bin:/usr/bin:/bin:#{File.dirname(RbConfig.ruby)}",
             "FAKE_RUBOCOP_JSON" => File.join(@dir, "clean.json"), "POWERNODE_LOCAL_CONFIG" => "none" }.merge(env)
    root = script_root || @repo
    out, err, st = Open3.capture3(full, File.join(root, "scripts/pre-critic-gate.sh"), *args, chdir: root)
    [ out, err, st.exitstatus ]
  end

  def statuses(json_out)
    JSON.parse(json_out)["checks"].to_h { |c| [ c["name"], c["status"] ] }
  end

  it "passes a clean range and skips what the range does not touch" do
    write("docs/readme.md", "hello again\n")
    head = commit_all("docs only")
    out, err, code = gate("#{@base}..#{head}", "--json")

    expect(code).to eq(0), err
    expect(JSON.parse(out)).to include("ok" => true, "failed" => 0)
    expect(statuses(out)).to eq("rubocop" => "skip", "tsc" => "skip", "catalog" => "skip", "purity" => "pass",
                                "messages" => "pass", "leak-guards" => "pass", "gitleaks" => "pass",
                                "ext-messages" => "skip", "ext-purity" => "skip", "ext-gitleaks" => "skip")
  end

  it "prints a compact human summary ending in the verdict" do
    write("docs/readme.md", "again\n")
    head = commit_all("docs only")
    out, _err, code = gate("#{@base}..#{head}")

    expect(code).to eq(0)
    expect(out).to match(/\Apre-critic gate #{@base[0, 12]}\.\.#{head[0, 12]} \(1 file\(s\) touched\)$/)
    expect(out).to match(/^PASS  purity\t/)
    expect(out.strip.lines.last.strip).to eq("RESULT: PASS")
    expect(out.bytesize).to be < 1200
  end

  describe "rubocop" do
    let(:head) do
      write("server/app/models/thing.rb", "# frozen_string_literal: true\nclass Thing\n  def x = 1\nend\n")
      commit_all("touch a server file")
    end

    it "fails on an offense on a line the range added" do
      File.write(File.join(@dir, "off.json"), rubocop_json("app/models/thing.rb", [ 3 ]))
      out, _err, code = gate("#{@base}..#{head}", "--json", env: { "FAKE_RUBOCOP_JSON" => File.join(@dir, "off.json") })

      expect(code).to eq(1)
      rubocop = JSON.parse(out)["checks"].find { |c| c["name"] == "rubocop" }
      expect(rubocop).to include("status" => "fail", "summary" => "1 file(s), 1 offense(s) on changed lines")
      expect(rubocop["detail"]).to include("server/app/models/thing.rb:3 Style/X")
    end

    it "does not fail on an offense that was already there (an unchanged line)" do
      File.write(File.join(@dir, "old.json"), rubocop_json("app/models/thing.rb", [ 1, 2 ]))
      out, err, code = gate("#{@base}..#{head}", "--json", env: { "FAKE_RUBOCOP_JSON" => File.join(@dir, "old.json") })

      expect(code).to eq(0), err
      expect(statuses(out)["rubocop"]).to eq("pass")
    end
  end

  it "runs tsc only when frontend/ is touched, and fails with the error count" do
    write("frontend/src/a.ts", "export const a = 2\n")
    head = commit_all("frontend change")
    out, _err, code = gate("#{@base}..#{head}", "--json", env: { "FAKE_TSC_FAIL" => "1" })

    expect(code).to eq(1)
    tsc = JSON.parse(out)["checks"].find { |c| c["name"] == "tsc" }
    expect(tsc).to include("status" => "fail", "summary" => "2 error(s)")

    out, _err, code = gate("#{@base}..#{head}", "--json")
    expect(code).to eq(0)
    expect(statuses(out)["tsc"]).to eq("pass")
  end

  it "runs the catalog check when tool-bearing paths change, and fails when it is stale" do
    write("server/app/models/thing.rb", "# frozen_string_literal: true\nclass Thing; end\n")
    head = commit_all("server change")
    out, _err, code = gate("#{@base}..#{head}", "--json", env: { "FAKE_CATALOG_FAIL" => "1" })

    expect(code).to eq(1)
    expect(statuses(out)["catalog"]).to eq("fail")
    expect(gate("#{@base}..#{head}", "--json")[2]).to eq(0)
  end

  it "reports a purity hit by file name only, never the matched text" do
    write("server/app/models/thing.rb", "# frozen_string_literal: true\n# FORBIDDEN_EXT\nclass Thing\nend\n")
    write("docs/readme.md", "DEPLOY_LOCAL_FACT\n")
    head = commit_all("bad content")
    out, _err, code = gate("#{@base}..#{head}", "--json")

    expect(code).to eq(1)
    purity = JSON.parse(out)["checks"].find { |c| c["name"] == "purity" }
    expect(purity["summary"]).to eq("2 finding(s) in 2 touched file(s)")
    expect(purity["detail"]).to include("core-purity: server/app/models/thing.rb", "deployment identifier: docs/readme.md")
    expect(out).not_to include("DEPLOY_LOCAL_FACT")
  end

  describe "the deployment-identifier scan" do
    def worktree_of(head)
      wt = File.join(@dir, "wt")
      sh!("git", "worktree", "add", "-q", "--detach", wt, head)
      wt
    end

    it "reads the gitignored identifier list from the main checkout when run in a worktree" do
      write("docs/readme.md", "DEPLOY_LOCAL_FACT\n")
      head = commit_all("bad content")
      wt = worktree_of(head)
      expect(File.exist?(File.join(wt, ".claude/hooks/deployment-identifiers.local.txt"))).to be false

      out, _err, code = gate("#{@base}..#{head}", "--json", script_root: wt)

      expect(code).to eq(1)
      purity = JSON.parse(out)["checks"].find { |c| c["name"] == "purity" }
      expect(purity["detail"]).to include("deployment identifier: docs/readme.md")
    end

    it "FAILS, rather than passing vacuously, when no list exists anywhere" do
      write("docs/readme.md", "fine\n")
      head = commit_all("docs")
      File.delete(File.join(@repo, ".claude/hooks/deployment-identifiers.local.txt"))
      out, _err, code = gate("#{@base}..#{head}", "--json")

      expect(code).to eq(1)
      purity = JSON.parse(out)["checks"].find { |c| c["name"] == "purity" }
      expect(purity["detail"]).to include("identifiers were NOT scanned")

      out, _err, code = gate("#{@base}..#{head}", "--json", env: { "GATE_ALLOW_NO_IDENTIFIER_LIST" => "1" })
      expect(code).to eq(0)
      expect(statuses(out)["purity"]).to eq("pass")
    end

    it "fails when the core-purity hook is missing or crashes" do
      write("server/app/models/thing.rb", "# frozen_string_literal: true\n# HOOK_CRASH\nclass Thing; end\n")
      head = commit_all("crashing content")
      out, _err, code = gate("#{@base}..#{head}", "--json")
      expect(code).to eq(1)
      expect(JSON.parse(out)["checks"].find { |c| c["name"] == "purity" }["detail"]).to include("hook errored (exit 1)")

      FileUtils.rm(File.join(@repo, ".claude/hooks/core-purity-check.sh"))
      out, _err, code = gate("#{@base}..#{head}", "--json", "--no-head-check")
      expect(code).to eq(1)
      expect(JSON.parse(out)["checks"].find { |c| c["name"] == "purity" }["detail"]).to include("hook is missing")
    end
  end

  describe "an extension pointer bump" do
    def bump(msg: "ext change", file: "x.rb", body: "# frozen_string_literal: true\n")
      File.write(File.join(@ext, file), body)
      sh!("git", "add", "-A", chdir: @ext)
      sh!("git", "commit", "-q", "-m", msg, chdir: @ext)
      commit_all("bump extension pointer")
    end

    it "gates the commits behind the bump: clean passes all three ext checks" do
      head = bump
      out, err, code = gate("#{@base}..#{head}", "--json")

      expect(code).to eq(0), err
      expect(statuses(out)).to include("ext-messages" => "pass", "ext-purity" => "pass", "ext-gitleaks" => "pass")
      expect(File.read(File.join(@dir, "gitleaks.args"))).to include("--source=#{@ext}", "#{@ext_base}..")
    end

    it "fails ext-messages on attribution in an extension commit that the core range never shows" do
      head = bump(msg: "ext change\n\nCo-Authored-By: Some Model <noreply@example.invalid>")
      out, _err, code = gate("#{@base}..#{head}", "--json")

      expect(code).to eq(1)
      checks = JSON.parse(out)["checks"].to_h { |c| [ c["name"], c ] }
      expect(checks["messages"]["status"]).to eq("pass")
      expect(checks["ext-messages"]["status"]).to eq("fail")
      expect(checks["ext-messages"]["detail"]).to include("extensions/widgets", "ai_attribution")
    end

    it "fails ext-purity for a touched extension file, ext-gitleaks on a finding" do
      head = bump(file: "bad.rb", body: "# FORBIDDEN_EXT\n")
      out, _err, code = gate("#{@base}..#{head}", "--json", env: { "FAKE_LEAK" => "1" })

      expect(code).to eq(1)
      expect(statuses(out)).to include("ext-purity" => "fail", "ext-gitleaks" => "fail")
    end

    it "fails when the bumped commits are not in the extension checkout" do
      head = bump
      FileUtils.rm_rf(File.join(@ext, ".git"))
      sh!("git", "init", "-q", "-b", "develop", @ext)
      out, _err, code = gate("#{@base}..#{head}", "--json", "--no-head-check")

      expect(code).to eq(1)
      expect(JSON.parse(out)["checks"].find { |c| c["name"] == "ext-messages" }["detail"]).to include("not in the checkout")
    end
  end

  it "fails a commit that carries AI attribution or names a private extension, without echoing the text" do
    write("docs/readme.md", "x\n")
    sh!("git", "add", "-A")
    sh!("git", "commit", "-q", "-m", "wire up hidden-ext\n\nCo-Authored-By: Some Model <noreply@example.invalid>")
    head = sh!("git", "rev-parse", "HEAD")
    out, _err, code = gate("#{@base}..#{head}", "--json")

    expect(code).to eq(1)
    messages = JSON.parse(out)["checks"].find { |c| c["name"] == "messages" }
    expect(messages["status"]).to eq("fail")
    expect(messages["detail"]).to include("ai_attribution", "private_extension_name")
    expect(out).not_to include("hidden-ext")
  end

  it "fails when a leak guard fails, naming the guard" do
    write("docs/readme.md", "y\n")
    head = commit_all("docs")
    out, _err, code = gate("#{@base}..#{head}", "--json", env: { "FAKE_LEAK_FAIL" => "check-tool-not-found-leak.sh" })

    expect(code).to eq(1)
    guards = JSON.parse(out)["checks"].find { |c| c["name"] == "leak-guards" }
    expect(guards).to include("summary" => "1 of 2 guard(s) failed")
    expect(guards["detail"]).to include("check-tool-not-found-leak.sh failed:")
  end

  it "runs gitleaks over the range with matches redacted, and fails on a finding" do
    write("docs/readme.md", "z\n")
    head = commit_all("docs")
    out, _err, code = gate("#{@base}..#{head}", "--json", env: { "FAKE_LEAK" => "1" })

    expect(code).to eq(1)
    expect(statuses(out)["gitleaks"]).to eq("fail")
    args = File.read(File.join(@dir, "gitleaks.args"))
    expect(args).to include("--log-opts=#{@base}..#{head}", "--redact")
  end

  it "fails rather than silently passing when gitleaks is not installed" do
    write("docs/readme.md", "w\n")
    head = commit_all("docs")
    # a PATH that has everything the gate needs EXCEPT gitleaks
    bin = File.join(@dir, "nogl")
    FileUtils.mkdir_p(bin)
    %w[ruby git jq bash env awk sed grep tr cut head tail sort wc mktemp cat rm mv date dirname basename ls readlink cp uniq tee timeout].each do |tool|
      real = ENV.fetch("PATH").split(":").map { |d| File.join(d, tool) }.find { |f| File.executable?(f) }
      File.symlink(real, File.join(bin, tool)) if real
    end
    FileUtils.cp(File.join(@stubs, "bundle"), File.join(bin, "bundle"))
    FileUtils.cp(File.join(@stubs, "npx"), File.join(bin, "npx"))
    out, _err, code = gate("#{@base}..#{head}", "--json", path: bin)

    expect(code).to eq(1)
    expect(JSON.parse(out)["checks"].find { |c| c["name"] == "gitleaks" }["summary"]).to match(/not installed; nothing was scanned/)
  end

  it "honours --skip and --only" do
    write("docs/readme.md", "v\n")
    head = commit_all("docs")

    out, = gate("#{@base}..#{head}", "--json", "--only", "messages")
    expect(statuses(out).select { |_, v| v != "skip" }).to eq("messages" => "pass")

    out, = gate("#{@base}..#{head}", "--json", "--skip", "gitleaks,purity", env: { "FAKE_LEAK" => "1" })
    expect(statuses(out)).to include("gitleaks" => "skip", "purity" => "skip")
  end

  it "refuses when the working tree is not at <head>, unless told otherwise" do
    write("docs/readme.md", "u\n")
    head = commit_all("docs")
    sh!("git", "checkout", "-q", @base)

    _out, err, code = gate("#{@base}..#{head}")
    expect(code).to eq(2)
    expect(err).to match(/working tree is at/)

    _out, _err, code = gate("#{@base}..#{head}", "--no-head-check")
    expect(code).to eq(0)
  end

  it "rejects a range that is not base..head" do
    _out, err, code = gate("just-one-ref")
    expect(code).to eq(2)
    expect(err).to match(/<base>\.\.<head>/)
  end
end

RSpec.describe "scripts/lib/changed-line-offenses.rb" do
  let(:script) { File.expand_path("../../../scripts/lib/changed-line-offenses.rb", __dir__) }

  def git!(dir, *args)
    out, err, st = Open3.capture3({ "GIT_AUTHOR_NAME" => "T", "GIT_AUTHOR_EMAIL" => "t@example.invalid",
                                    "GIT_COMMITTER_NAME" => "T", "GIT_COMMITTER_EMAIL" => "t@example.invalid" }, "git", "-C", dir, *args)
    raise err unless st.success?

    out.strip
  end

  around do |example|
    Dir.mktmpdir("col-spec") do |dir|
      @repo = dir
      git!(dir, "init", "-q", "-b", "develop")
      FileUtils.mkdir_p(File.join(dir, "server/app"))
      File.write(File.join(dir, "server/app/a.rb"), (1..6).map { |i| "l#{i}\n" }.join)
      git!(dir, "add", "-A")
      git!(dir, "commit", "-q", "-m", "base")
      @base = git!(dir, "rev-parse", "HEAD")
      lines = File.readlines(File.join(dir, "server/app/a.rb"))
      lines[2] = "changed3\n"
      lines.insert(5, "inserted\n")
      File.write(File.join(dir, "server/app/a.rb"), lines.join)
      git!(dir, "commit", "-qam", "edit")
      @head = git!(dir, "rev-parse", "HEAD")
      example.run
    end
  end

  def run_filter(offense_lines, prefix: "server/")
    json = JSON.generate(files: [ { path: "app/a.rb", offenses: offense_lines.map { |l| { cop_name: "C/x", message: "m", location: { line: l } } } } ])
    out, _err, st = Open3.capture3(script, @repo, @base, @head, "--prefix", prefix, stdin_data: json)
    [ JSON.parse(out), st.exitstatus ]
  end

  it "keeps offenses on changed and inserted lines and drops the rest" do
    # head file: l1 l2 changed3 l4 l5 inserted l6 -> changed = lines 3 and 6
    result, code = run_filter([ 1, 2, 3, 4, 6, 7 ])

    expect(code).to eq(1)
    expect(result["offenses"].map { |o| o["line"] }).to eq([ 3, 6 ])
    expect(result["offenses"].first).to include("file" => "server/app/a.rb", "cop" => "C/x")
  end

  it "exits 0 with a zero count when nothing sits on a changed line" do
    result, code = run_filter([ 1, 2, 4 ])

    expect(code).to eq(0)
    expect(result["count"]).to eq(0)
  end
end
