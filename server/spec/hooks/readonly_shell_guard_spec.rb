# frozen_string_literal: true

require "rails_helper"
require "json"
require "open3"

# platform-reviewer has a shell so it can CHECK work (read-only git, grep, tests),
# but "read-only by charter" is prose. This PreToolUse hook makes it mechanical.
# It is wired in the reviewer's own frontmatter (`hooks:`, scoped to that
# subagent by Claude Code), not in settings.json, so it never restricts the main
# session or other agents. The policy is an allowlist: anything it cannot prove
# read-only is denied (exit 2).
RSpec.describe ".claude/hooks/readonly-shell-guard.sh" do
  let(:repo_root) { File.expand_path("../../..", __dir__) }
  let(:hook) { File.join(repo_root, ".claude", "hooks", "readonly-shell-guard.sh") }

  def run(command, env: {})
    payload = { tool_name: "Bash", tool_input: { command: command } }.to_json
    base = { "RAILS_ENV" => nil, "DATABASE_NAME" => nil, "DATABASE_HOST" => nil, "HOME" => "/home/example" }
    _out, err, status = Open3.capture3(base.merge(env), "bash", hook, stdin_data: payload)
    [ status.exitstatus, err ]
  end

  allowed = [
    "git log --oneline -n 5", "git show HEAD", "git diff develop..HEAD --stat", "git status --short", "git rev-parse HEAD",
    "git ls-files server/app", "git ls-tree -r HEAD", "git cat-file -p HEAD", "git merge-base develop HEAD", "git branch --list",
    "git blame -L 1,10 server/app/models/ai/skill.rb", "git grep -n assemble_task", "git -C /work/tree log -3",
    "rg -n assemble_task server/app", "grep -rn assemble_task server/app", "cat server/app/models/ai/skill.rb",
    "head -n 20 file.rb", "sed -n 1,20p file.rb", "ls -la server", "find server/app -name skill.rb -newer x",
    "git log --oneline | head -5", "git diff | grep -c foo", "go vet ./...", "go test ./internal/...", "wc -l file", "pwd",
    "git diff develop..HEAD", "git log HEAD~3..HEAD --oneline", "git log -p --stat -n 2", "sort -n file", "sort -rn -k2 file",
    "git log --oneline | sort | uniq -c", "uniq -c file", "uniq -f 1 file", "file server/app/models/ai/skill.rb",
    "go test -run TestAssemble -v -count=1 ./internal/...", "go test -race -timeout=60s ./...", "cat /work/tree/server/app/x.rb"
  ]
  denied = [
    "git push origin develop", "git commit -m x", "git checkout develop", "git reset --hard", "git fetch", "git pull", "git branch -D x",
    "git branch newbranch", "git stash", "git diff --output=out.txt", "git config user.name x", "git -c core.pager=sh log",
    "rm -rf x", "touch x", "mkdir x", "mv a b", "cp a b", "chmod +x a", "tee out", "echo hi > out", "cat a >> b", "cat a > b", "ls | tee x",
    "source ~/.bashrc", ". ./env.sh", "env", "export X=1", "curl https://example.test", "wget https://example.test",
    "bundle exec rails runner 'puts 1'", "rails console", "ruby -e 'puts 1'", "python3 -c 'print(1)'", "bash -c 'ls'", "sh x.sh",
    "sed -i s/a/b/ f", "sed -n 'w out' f", "find . -delete", "find . -exec rm {} ;", "find . -execdir ls ;", "find . -fprint out",
    "git log; rm -rf x", "git log && rm x", "git log || rm x", "ls & rm x", "ls `rm x`", "ls $(rm x)", "git log $HOME", "cat ~/.config/powernode/powernode.conf",
    "cat /home/example/.config/powernode/backend-default.conf", "rg token ~/.config/powernode", "grep -r x .config/powernode",
    "rg --pre ./x pattern .", "go run main.go", "go build ./...", "npm install", "docker ps", "systemctl restart x", "ssh host ls", "sudo ls", "",
    # PRE-2 final review: bypasses of the first allowlist. Each must be blocked.
    # Quoted flags slip past a token match on the unquoted spelling:
    "find . -name x \"-delete\"", "git log \"--output=/tmp/x\"", "rg \"--pre=touch\" x .", "cat 'a'",
    # Write or run options the first allowlist did not know about:
    "git grep -Otouch x", "git grep -nOtouch x", "git grep --open-files-in-pager=touch x", "git grep --open x",
    "git log --outp=/tmp/x", "git log --o=/tmp/x", "git diff --no-index a b", "git cat-file --filters HEAD:x",
    "sort -o out file", "sort -ro out file", "sort --output=out file", "sort --out=out file", "sort --compress-program=touch file",
    "uniq in out", "uniq -c in out", "uniq -f 1 in out", "uniq -- in -out",
    "go test -c -o out ./...", "go test -o out ./...", "go test -exec touch ./...", "go test -toolexec touch ./...",
    "go test -coverprofile=out ./...", "go test ./... -args -test.cpuprofile=out", "go vet -vettool=touch ./...",
    "rspec --init", "bundle exec rspec --init", "bundle exec rspec --ini", "bundle exec rspec -r ./x.rb spec",
    "bundle exec rspec --require ./x.rb spec", "bundle exec rspec -O opts spec", "bundle exec rspec --options opts spec",
    "bundle exec rspec --out out spec", "bundle exec rspec -o out spec", "bundle exec rspec -I lib spec", "bundle exec rspec db/seeds.rb",
    "npx jest --config x.js", "npx jest -c x.js", "npx jest --outputFile=out --json", "npx jest -u", "npx jest --updateSnapshot",
    "npx jest --setupFiles x.js", "npx jest --globalSetup x.js",
    "file -C -m x", "file -zC -m x", "file --compile -m x", "file --comp -m x",
    # Globs and path tricks defeat a substring match on the secrets path:
    "cat /home/rett/.c*nfig/powernode/*", "cat /home/example/.c?nfig/powernode/x", "cat /home/example/.c[o]nfig/powernode/x",
    "cat /home/example/.config//powernode/x", "cat /home/example/.config/./powernode/x", "cat /home/example/.config/x/../powernode/x",
    "cat ../../.ssh/id", "ls ~", "cat ~root/x",
    # The process environment and whole-home scans:
    "cat /proc/self/environ", "cat /proc//self/environ", "grep -r token /proc/1", "grep -r token /home/example", "rg token /home/example/",
    "rg token /", "grep -r token /home", "git -C /home/example grep --no-index token"
  ]

  allowed.each do |command|
    it "allows #{command.inspect}" do
      code, err = run(command)
      expect(code).to eq(0), err
    end
  end

  denied.each do |command|
    it "denies #{command.inspect}" do
      code, = run(command)
      expect(code).to eq(2)
    end
  end

  describe "test runners (only when the test DB guard applies)" do
    it "allows rspec and jest when no development environment is exported" do
      expect(run("bundle exec rspec spec/models/ai/skill_spec.rb").first).to eq(0)
      expect(run("npx jest src/foo.test.ts").first).to eq(0)
      expect(run("bundle exec rspec spec/models/ai/skill_spec.rb:12 --format documentation --fail-fast").first).to eq(0)
      expect(run("bundle exec rspec server/spec/hooks -fd --seed 1").first).to eq(0)
      expect(run("npx jest src/foo.test.ts --ci -t name --runInBand").first).to eq(0)
    end

    it "allows rspec under RAILS_ENV=test" do
      expect(run("bundle exec rspec spec/x_spec.rb", env: { "RAILS_ENV" => "test" }).first).to eq(0)
    end

    it "denies rspec when a development environment is exported (the incident: rspec cleaning the dev DB)" do
      expect(run("bundle exec rspec spec/x_spec.rb", env: { "RAILS_ENV" => "development" }).first).to eq(2)
      expect(run("bundle exec rspec spec/x_spec.rb", env: { "DATABASE_NAME" => "powernode_development" }).first).to eq(2)
      expect(run("npx jest", env: { "DATABASE_NAME" => "powernode_development" }).first).to eq(2)
    end
  end

  it "denies on a payload it cannot read, or without a command (when unsure, deny)" do
    _o, _e, s1 = Open3.capture3("bash", hook, stdin_data: "not json")
    _o, _e, s2 = Open3.capture3("bash", hook, stdin_data: { tool_name: "Bash", tool_input: {} }.to_json)
    expect([ s1.exitstatus, s2.exitstatus ]).to eq([ 2, 2 ])
  end

  # Phase 1: the guard can fail OPEN (frontmatter hooks need workspace trust; an
  # unset $CLAUDE_PROJECT_DIR is a non-blocking exit 127), so no role relies on
  # it — the reviewer has no shell at all. The hook stays, hardened, for any
  # future shell role, and the roster still refuses a shell without code that
  # names no guard.
  describe "wiring" do
    def frontmatter(slug)
      YAML.safe_load(File.read(File.join(repo_root, ".claude", "agents", "powernode", "#{slug}.md")).split(/^---$/, 3)[1])
    end

    it "is nowhere in settings.json (it must never restrict the main session)" do
      expect(File.read(File.join(repo_root, ".claude", "settings.json"))).not_to include("readonly-shell-guard")
    end

    it "the reviewer has no shell in phase 1: no Bash in its tools and no hook in its frontmatter" do
      fm = frontmatter("platform-reviewer")
      expect(fm["tools"].split(",").map(&:strip)).not_to include("Bash", "Edit", "Write")
      expect(fm).not_to have_key("hooks")
      expect(Ai::Agents::CanonicalRoster.fetch("platform-reviewer")[:role]).to include(shell: false, code: false)
    end

    it "every role with a shell and no Edit/Write names a guard" do
      Ai::Agents::CanonicalRoster.each do |slug, spec, _|
        role = spec[:role]
        expect(role[:shell_guard]).to be_present, slug if role[:shell] && !role[:code]
      end
    end

    it "the reviewer charter and the ceilings file say it has no shell" do
      expect(Ai::Agents::CanonicalRoster.fetch("platform-reviewer")[:charter]).to match(/no shell/i)
      expect(File.read(File.join(repo_root, "scripts", "claude-agents-size-ceilings.txt"))).to match(/platform-reviewer has no shell/i)
    end
  end
end
