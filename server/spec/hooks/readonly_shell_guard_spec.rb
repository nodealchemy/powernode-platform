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
    "rg -n assemble_task server/app", "grep -rn 'assemble_task' server/app", "cat server/app/models/ai/skill.rb",
    "head -n 20 file.rb", "sed -n 1,20p file.rb", "ls -la server", "find server/app -name '*.rb' -newer x",
    "git log --oneline | head -5", "git diff | grep -c foo", "go vet ./...", "go test ./internal/...", "wc -l file", "pwd"
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
    "rg --pre ./x pattern .", "go run main.go", "go build ./...", "npm install", "docker ps", "systemctl restart x", "ssh host ls", "sudo ls", ""
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

  describe "wiring" do
    it "is in the reviewer's frontmatter, scoped to Bash, and nowhere in settings.json" do
      reviewer = File.read(File.join(repo_root, ".claude", "agents", "powernode", "platform-reviewer.md"))
      fm = YAML.safe_load(reviewer.split(/^---$/, 3)[1])
      hooks = fm.dig("hooks", "PreToolUse")

      expect(hooks.first["matcher"]).to eq("Bash")
      expect(hooks.first["hooks"].first["command"]).to include("readonly-shell-guard.sh")
      expect(File.read(File.join(repo_root, ".claude", "settings.json"))).not_to include("readonly-shell-guard")
    end

    it "is only on roles that have a shell and no Edit/Write" do
      roles = Ai::Agents::CanonicalRoster.each.to_h { |slug, spec, _| [ slug, spec[:role] ] }
      guarded = roles.select { |_s, r| r[:shell_guard] }.keys

      expect(guarded).to eq(roles.select { |_s, r| r[:shell] && !r[:code] }.keys)
      expect(guarded).to include("platform-reviewer")
    end

    it "is stated in the reviewer charter and the ceilings file" do
      expect(Ai::Agents::CanonicalRoster.fetch("platform-reviewer")[:charter]).to match(/readonly-shell-guard|allowlist/i)
      expect(File.read(File.join(repo_root, "scripts", "claude-agents-size-ceilings.txt"))).to match(/readonly-shell-guard/)
    end
  end
end
