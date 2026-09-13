# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"

# D2 (component status plane campaign, design §8 Track D) completion oracle.
#
# "A delegated task ends in a commit SHA READ BACK FROM THE REPOSITORY and a
# TestVerificationService verdict of verified; a task the agent cannot implement
# yields no SHA."
#
# The actuator's known failure mode is "exists, passes review, never executes",
# so this runs the REAL chain end to end:
#
#   CampaignDriver#delegate → ExecutionService#run_iteration → TaskExecutor
#   → AgentToolBridgeService#execute_tool_loop → GitToolExecutor
#   → Devops::Git::GiteaApiClient (real Faraday) → a git repository on disk
#   → TestVerificationService on a checkout of the read-back SHA
#   → the real internal test_results callback that resolves the task.
#
# Only two HTTP boundaries are replaced, both with STRING-keyed JSON bodies in the
# shape the real peer sends (a symbol-keyed double hiding a string-keyed body has
# burned this campaign twice):
#
#   1. the LLM — the worker's POST /api/v1/llm/complete_with_tools, whose body is
#      worker LlmProxyClient#format_response wrapped in { "data" => ... };
#   2. the Gitea REST API — GiteaContentsContractFake (spec/support), a CONTRACT
#      fake over a real git repository: it enforces the contents-API rules the
#      client relies on (each cited there) and answers a violation the way Gitea
#      does. The drift guard at the bottom pins the client's request shape to it.
#
# The stub cannot prove the real provider's behaviour: the deploy-time check (one
# delegated task against the real dev Gitea) is recorded by the campaign lead.
RSpec.describe "Delegated task git actuation (D2)", type: :request do
  include_context "internal api auth"

  let(:account) { internal_account }
  # Git tools run as the agent's creator and require ai.loops.execute (D2 review F3).
  # ai.campaigns.manage is this actor's OWN grant in THIS account: every mutating campaign
  # action asks the shared campaign check against the account it touches, so start and
  # delegate demand it here, and declaring permissions at all suppresses the implicit OWNER
  # role this spec previously leaned on. The arm below pins that the grant must be held in
  # THIS account — a grant carried in from another one still refuses.
  let(:user) do
    create(:user, account: account, permissions: %w[ai.loops.execute ai.campaigns.manage])
  end

  let(:ai_provider) { create(:ai_provider, account: account) }
  let!(:ai_credential) { create(:ai_provider_credential, account: account, provider: ai_provider) }
  let(:agent) do
    create(:ai_agent, account: account, provider: ai_provider, creator: user, agent_type: "assistant",
                      mcp_metadata: {
                        "model_config" => { "model" => "test-model-1" },
                        "tool_access" => { "enabled" => true, "allowed_tools" => [ "discover_skills" ] }
                      })
  end

  let(:gitea_host) { "https://gitea.d2.test" }
  let(:gitea_api) { "#{gitea_host}/api/v1" }
  let(:git_provider) do
    create(:git_provider, account: account, provider_type: "gitea", api_base_url: gitea_api, web_base_url: gitea_host)
  end
  let(:git_credential) { create(:git_provider_credential, account: account, provider: git_provider, user: user) }
  let(:repository) do
    create(:git_repository, account: account, credential: git_credential, owner: "acme", name: "calc",
                            full_name: "acme/calc", default_branch: "main",
                            clone_url: "#{gitea_host}/acme/calc.git", web_url: "#{gitea_host}/acme/calc")
  end
  let(:mission) { create(:ai_mission, account: account, created_by: user, repository: repository) }

  let(:driver) { Ai::DevLoop::CampaignDriver.new(account: account, user: user) }
  let(:campaign) { driver.start(name: "D2 actuation")[:campaign] }
  let(:loop_record) { campaign.ralph_loops.first }
  let(:branch) { loop_record.branch }

  let(:worker_url) { Rails.application.config.worker_url.to_s.chomp("/") }
  let(:llm_url) { "#{worker_url}/api/v1/llm/complete_with_tools" }

  let(:add_go) { "package calc\n\n// Add returns a + b.\nfunc Add(a, b int) int {\n\treturn a + b\n}\n" }
  let(:passing_test_go) do
    "package calc\n\nimport \"testing\"\n\nfunc TestAdd(t *testing.T) {\n" \
      "\tif got := Add(2, 3); got != 5 {\n\t\tt.Fatalf(\"Add(2, 3) = %d, want 5\", got)\n\t}\n}\n"
  end
  let(:failing_test_go) do
    "package calc\n\nimport \"testing\"\n\nfunc TestAdd(t *testing.T) {\n" \
      "\tif got := Add(2, 3); got != 6 {\n\t\tt.Fatalf(\"Add(2, 3) = %d, want 6\", got)\n\t}\n}\n"
  end

  # Real git repositories live under server/tmp (gitignored, on the repository's
  # disk) — never /tmp, whose root overlay on the dev box is 512M.
  around do |example|
    base = Rails.root.join("tmp").to_s
    FileUtils.mkdir_p(base)
    Dir.mktmpdir("d2-actuation-", base) do |tmp|
      @tmp = tmp
      @origin = File.join(tmp, "origin")
      FileUtils.mkdir_p(@origin)
      example.run
    end
  end

  before do
    @llm_requests = []

    # The write actuator is opt-in (D2 review F3, operator ruling (a)): with no
    # policy row, ralph.repository_write/delete resolve to require_approval and a
    # commit parks. These examples opt in explicitly, as an operator would; the
    # :no_policy_row examples show the default.
    unless RSpec.current_example.metadata[:no_policy_row]
      %w[ralph.repository_write ralph.repository_delete].each do |category|
        Ai::InterventionPolicy.create!(account: account, scope: "global", action_category: category,
                                       policy: "auto_approve", priority: 0, is_active: true)
      end
    end

    git!("init", "-q", "-b", "main")
    File.write(File.join(@origin, "go.mod"), "module example.com/calc\n\ngo 1.21\n")
    File.write(File.join(@origin, "calc.go"), "package calc\n")
    git!("add", "go.mod", "calc.go")
    git!("commit", "-q", "-m", "seed")
    @seed_sha = git!("rev-parse", "HEAD")
    git!("branch", branch, "main")

    @fake = GiteaContentsContractFake.new(repo_path: @origin, api_base: gitea_api, owner: "acme", repo: "calc",
                                          token: git_credential.access_token, git_env: git_env)
    stub_request(:any, %r{\A#{Regexp.escape(gitea_api)}/}).to_return { |request| @fake.call(request) }
  end

  # ---------------------------------------------------------------- helpers

  # Hermetic git: no global/system config (no signing hooks, no aliases).
  def git_env
    {
      "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_NOSYSTEM" => "1",
      "GIT_AUTHOR_NAME" => "gitea", "GIT_AUTHOR_EMAIL" => "gitea@d2.test",
      "GIT_COMMITTER_NAME" => "gitea", "GIT_COMMITTER_EMAIL" => "gitea@d2.test"
    }
  end

  def git!(*args, strip: true)
    out, err, status = Open3.capture3(git_env, "git", "-C", @origin, *args)
    raise "git #{args.join(' ')} failed: #{err}" unless status.success?

    strip ? out.strip : out
  end

  def branch_tip
    git!("rev-parse", "refs/heads/#{branch}")
  end

  def json_reply(status, body)
    { status: status, headers: { "Content-Type" => "application/json" }, body: body.to_json }
  end

  # Body shape of the worker's success_response(format_response(...)).
  def llm_reply(content: nil, tool_calls: nil)
    data = {
      "content" => content, "tool_calls" => tool_calls,
      "finish_reason" => tool_calls ? "tool_calls" : "stop", "model" => "test-model-1",
      "usage" => { "prompt_tokens" => 12, "completion_tokens" => 7, "total_tokens" => 19 }, "cost" => 0.0
    }.compact
    json_reply(200, "success" => true, "data" => data)
  end

  def write_call(id, file_path, content, message)
    { "id" => id, "name" => "write_file",
      "arguments" => { "path" => file_path, "content" => content, "message" => message } }
  end

  def script_llm(*replies)
    stub_request(:post, llm_url).to_return do |request|
      @llm_requests << JSON.parse(request.body)
      replies.shift || llm_reply(content: "done")
    end
  end

  def delegate!(target)
    driver.delegate(campaign, driver_kind: "platform_agent", target: target)
    loop_record.reload
  end

  def run_one_iteration!
    task = loop_record.ralph_tasks.create!(
      task_key: "add-function", position: 1, status: "pending", execution_type: "agent",
      description: "Add func Add(a, b int) int to package calc, with a test.",
      acceptance_criteria: "go test ./... passes"
    )
    result = Ai::Ralph::ExecutionService.new(ralph_loop: loop_record.reload).run_iteration
    expect(result[:success]).to be(true), "run_iteration failed: #{result.inspect}"
    [ task.reload, loop_record.ralph_iterations.order(:created_at).last ]
  end

  def advertised_tool_names
    Array(@llm_requests.first&.dig("tools")).map { |t| t["name"] || t.dig("function", "name") }
  end

  # The real TestVerificationService over a real checkout of the SHA read back
  # from the repository. The runner is the worker's job in production; here it is
  # the same shape (command, dir, timeout) executed as a real subprocess.
  def verify_at(sha)
    checkout = File.join(@tmp, "checkout-#{sha[0, 12]}")
    git!("worktree", "add", "--detach", "-q", checkout, sha)
    go_env = { "GOFLAGS" => "-mod=mod", "GOPROXY" => "off", "GOTOOLCHAIN" => "local", "GOTMPDIR" => @tmp, "TMPDIR" => @tmp }
    runner = lambda do |command:, dir:, timeout_seconds:|
      out, err, status = Open3.capture3(go_env, command, chdir: dir)
      { stdout: out, stderr: err, exit_code: status.exitstatus, timeout_seconds: timeout_seconds }
    end
    Ai::Ralph::TestVerificationService.new(runner: runner)
                                      .verify(dir: checkout, root_entries: Dir.children(checkout), timeout_seconds: 120)
  end

  # The worker's AiTestExecutionJob posts its raw result to this internal
  # callback, which evaluates it and resolves the task.
  def post_test_results!(iteration, verification)
    post "/api/v1/internal/ai/ralph_loops/#{loop_record.id}/iterations/#{iteration.id}/test_results",
         params: { test_result: { framework: verification[:framework], command: verification[:command],
                                  exit_code: verification[:exit_code], output: verification[:output] } },
         headers: service_headers, as: :json
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)["data"]
  end

  def test_job_requests
    WebMock::RequestRegistry.instance.requested_signatures.hash.keys.select do |sig|
      sig.method == :post && sig.uri.to_s.end_with?("/api/v1/jobs") &&
        JSON.parse(sig.body.to_s)["job_class"] == "AiTestExecutionJob"
    end
  end

  def verdict_of(verification)
    Ai::Ralph::TestVerificationService.adjudicate_check_results("output" => verification[:output])[:verdict]
  end

  # ---------------------------------------------------------------- oracle

  describe "a delegated task" do
    it "ends in a commit SHA read back from the repository and a verified TestVerificationService verdict" do
      delegate!(agent_id: agent.id, mission_id: mission.id)
      script_llm(
        llm_reply(tool_calls: [
          write_call("call_1", "add.go", add_go, "Add Add()"),
          write_call("call_2", "add_test.go", passing_test_go, "Test Add()")
        ]),
        llm_reply(content: "Implemented Add with a test.")
      )

      task, iteration = run_one_iteration!

      # The git tools reached the LLM on the tool-bridge path.
      expect(advertised_tool_names).to include("write_file", "read_file")

      # READ BACK: the branch tip IS the recorded SHA, it is a real commit git made,
      # it descends from the seed by exactly the two writes, and it carries the file.
      tip = branch_tip
      expect(iteration.git_commit_sha).to eq(tip)
      expect(git!("cat-file", "-t", tip)).to eq("commit")
      expect(git!("rev-list", "--count", "#{@seed_sha}..#{tip}")).to eq("2")
      expect(git!("show", "#{tip}:add_test.go", strip: false)).to eq(passing_test_go)
      expect(iteration.check_results.dig("actuation", "reason")).to eq("committed #{tip}; the sandboxed test run decides the pass")

      # No fabricated pass: the bridge claims nothing; the task waits on the real suite.
      expect(iteration.checks_passed).to be(false)
      expect(iteration.check_results["awaiting_test_result"]).to be(true)
      expect(task.status).not_to eq("passed")
      jobs = test_job_requests
      expect(jobs.size).to eq(1)
      expect(JSON.parse(jobs.first.body.to_s)["args"].first).to include("repository" => "acme/calc", "branch" => branch)

      # The real verifier over the read-back SHA, resolved through the real callback.
      verification = verify_at(tip)
      expect(verification).to include(success: true, ran: true, framework: "gotest", exit_code: 0)
      expect(verdict_of(verification)).to eq(:verified)
      expect(post_test_results!(iteration, verification)).to include("passed" => true)
      expect(task.reload.status).to eq("passed")
      expect(iteration.reload.checks_passed).to be(true)

      # Contract hygiene: every provider call was contract-backed and well-formed.
      expect(@fake.unhandled).to be_empty
      expect(@fake.unknown_keys).to be_empty
      expect(@fake.writes_refused).to be_empty
    end

    # The update path: an existing file is changed through PUT with the file's
    # CURRENT blob sha (Gitea refuses a stale or wrong one with 422).
    it "an edit to an existing file commits through the update path with the file's current sha" do
      delegate!(agent_id: agent.id, mission_id: mission.id)
      seed_blob = git!("rev-parse", "#{branch}:calc.go")
      edited = "package calc\n\n// Sub returns a - b.\nfunc Sub(a, b int) int {\n\treturn a - b\n}\n"
      script_llm(llm_reply(tool_calls: [ write_call("call_1", "calc.go", edited, "Add Sub()") ]),
                 llm_reply(content: "Added Sub to calc.go."))

      _task, iteration = run_one_iteration!

      put = @fake.requests.find { |r| r[:method] == :put }
      expect(put).to be_present, "no PUT reached the provider: #{@fake.requests.map { |r| [ r[:method], r[:path] ] }}"
      expect(put[:path]).to eq("/repos/acme/calc/contents/calc.go")
      expect(put[:body]["sha"]).to eq(seed_blob)
      expect(@fake.requests.map { |r| r[:method] }).not_to include(:post)

      tip = branch_tip
      expect(iteration.git_commit_sha).to eq(tip)
      expect(git!("rev-parse", "#{tip}^")).to eq(@seed_sha)
      expect(git!("show", "#{tip}:calc.go", strip: false)).to eq(edited)
      expect(iteration.check_results.dig("actuation", "reason")).to eq("committed #{tip}; the sandboxed test run decides the pass")
      expect(@fake.writes_refused).to be_empty
    end

    it "a commit whose tests fail lands as a real SHA but ends NOT verified" do
      delegate!(agent_id: agent.id, mission_id: mission.id)
      script_llm(
        llm_reply(tool_calls: [
          write_call("call_1", "add.go", add_go, "Add Add()"),
          write_call("call_2", "add_test.go", failing_test_go, "Test Add()")
        ]),
        llm_reply(content: "Implemented Add with a test.")
      )

      task, iteration = run_one_iteration!

      tip = branch_tip
      expect(iteration.git_commit_sha).to eq(tip)
      verification = verify_at(tip)
      expect(verification).to include(success: false, ran: true, framework: "gotest")
      expect(verification[:failed_count]).to be_positive
      expect(verdict_of(verification)).to eq(:contradicted)

      expect(post_test_results!(iteration, verification)).to include("passed" => false)
      expect(task.reload.status).not_to eq("passed")
      iteration.reload
      expect(iteration.checks_passed).to be(false)
      expect(iteration.check_results.dig("test_result", "failed_count")).to be_positive
    end

    it "a task the agent cannot implement yields no SHA and no pass, and says why" do
      delegate!(agent_id: agent.id, mission_id: mission.id)
      script_llm(llm_reply(content: "I cannot implement this: the package spec is ambiguous."))

      task, iteration = run_one_iteration!

      expect(advertised_tool_names).to include("write_file") # the actuator WAS available
      expect(iteration.git_commit_sha).to be_nil
      expect(branch_tip).to eq(@seed_sha)
      expect(@fake.requests.map { |r| r[:method] }).not_to include(:post, :put)
      expect(iteration.checks_passed).to be(false)
      expect(iteration.check_results.dig("actuation", "reason")).to eq("no commit: the agent made no repository change")
      expect(task.status).not_to eq("passed")
      expect(test_job_requests).to be_empty
    end

    it "a delegation that carries no repository attaches no git tools, produces no SHA, and says why" do
      delegate!(agent_id: agent.id)
      script_llm(llm_reply(content: "Here is a plan for adding Add."))

      _task, iteration = run_one_iteration!

      expect(advertised_tool_names).not_to include("write_file")
      expect(iteration.git_commit_sha).to be_nil
      expect(branch_tip).to eq(@seed_sha)
      expect(iteration.check_results.dig("actuation", "reason")).to start_with("no repository attached")
    end
  end

  describe "when the provider refuses the commit" do
    it "a 5xx on the write produces no SHA; the iteration ends NOT verified with the provider's reason" do
      delegate!(agent_id: agent.id, mission_id: mission.id)
      @fake.fail_next_write(status: 500, message: "internal error committing to acme/calc")
      script_llm(llm_reply(tool_calls: [ write_call("call_1", "add.go", add_go, "Add Add()") ]),
                 llm_reply(content: "Tried to add Add."))

      task, iteration = run_one_iteration!

      expect(@fake.writes_refused.map { |w| w[:status] }).to eq([ 500 ])
      expect(branch_tip).to eq(@seed_sha)
      expect(iteration.git_commit_sha).to be_nil
      expect(iteration.checks_passed).to be(false)
      expect(task.status).not_to eq("passed")
      expect(test_job_requests).to be_empty

      actuation = iteration.check_results["actuation"]
      expect(actuation["commit_sha"]).to be_nil
      expect(actuation["failed_changes"]).to eq([ { "path" => "add.go", "operation" => "created",
                                                    "error" => "Server error (500): internal error committing to acme/calc" } ])
      expect(actuation["reason"]).to eq("no commit: the repository refused 1 change(s) — created add.go: " \
                                        "Server error (500): internal error committing to acme/calc")
    end

    it "a concurrent commit makes the sha stale: Gitea's 422 conflict leaves no agent SHA, NOT verified, reason recorded" do
      delegate!(agent_id: agent.id, mission_id: mission.id)
      concurrent = nil
      @fake.before_next_write do
        concurrent = @fake.commit!(branch: branch, path: "calc.go", content: "package calc\n\n// concurrent edit\n",
                                   message: "concurrent edit")
      end
      script_llm(llm_reply(tool_calls: [ write_call("call_1", "calc.go", "package calc\n\n// agent edit\n", "Edit calc") ]),
                 llm_reply(content: "Edited calc.go."))

      task, iteration = run_one_iteration!

      # The tip is the concurrent commit on the seed — nothing of the agent's landed.
      expect(branch_tip).to eq(concurrent)
      expect(git!("rev-parse", "#{concurrent}^")).to eq(@seed_sha)
      expect(@fake.writes_refused.map { |w| w[:status] }).to eq([ 422 ])
      expect(iteration.git_commit_sha).to be_nil
      expect(iteration.checks_passed).to be(false)
      expect(task.status).not_to eq("passed")
      expect(test_job_requests).to be_empty

      change = iteration.check_results.dig("actuation", "failed_changes", 0)
      expect(change).to include("path" => "calc.go", "operation" => "updated")
      expect(change["error"]).to match(/Validation failed: sha does not match/)
      expect(iteration.check_results.dig("actuation", "reason")).to start_with("no commit: the repository refused 1 change(s)")
    end
  end

  # ---------------------------------------------------------------- review F1

  describe "tenancy at the actuator (review F1)" do
    let(:other_account) { create(:account) }
    let(:foreign_repository) do
      other_provider = create(:git_provider, account: other_account, provider_type: "gitea",
                                             api_base_url: gitea_api, web_base_url: gitea_host)
      create(:git_repository, account: other_account,
                              credential: create(:git_provider_credential, account: other_account, provider: other_provider),
                              owner: "acme", name: "calc", full_name: "acme/calc", default_branch: "main",
                              clone_url: "#{gitea_host}/acme/calc.git", web_url: "#{gitea_host}/acme/calc")
    end

    # A mission row carrying another account's repository, written past the door
    # and the model (update_column): the shape any unguarded writer could leave.
    def smuggle_foreign_repository!
      mission.update_column(:repository_id, foreign_repository.id)
    end

    def gitea_writes
      %i[post put delete].flat_map do |verb|
        WebMock::RequestRegistry.instance.requested_signatures.hash.keys.select do |sig|
          sig.method == verb && sig.uri.to_s.start_with?(gitea_api)
        end
      end
    end

    it "campaign_delegate refuses a mission whose repository belongs to another account" do
      smuggle_foreign_repository!

      expect { delegate!(agent_id: agent.id, mission_id: mission.id) }
        .to raise_error(ArgumentError, /repository not found in this account/)
      expect(loop_record.reload.mission_id).to be_nil
      expect(gitea_writes).to be_empty
    end

    # The acting user above holds ai.campaigns.manage in THIS account. A holder of the same
    # permission in ANOTHER account — what an account-switch session carries — is refused by
    # name and wires nothing: the grant is answered where the campaign lives, never imported.
    it "campaign_delegate refuses an actor holding ai.campaigns.manage only in another account" do
      foreign_user = create(:user, account: other_account,
                                   permissions: %w[ai.loops.execute ai.campaigns.manage])
      foreign_driver = Ai::DevLoop::CampaignDriver.new(account: account, user: foreign_user)

      expect {
        foreign_driver.delegate(campaign, driver_kind: "platform_agent",
                                          target: { agent_id: agent.id, mission_id: mission.id })
      }.to raise_error(Ai::Campaigns::Authorization::Refused,
                       /user #{foreign_user.id} does not hold 'ai\.campaigns\.manage' in account #{account.id}/)
      expect(loop_record.reload.mission_id).to be_nil
      expect(gitea_writes).to be_empty
    end

    it "a loop whose mission now carries another account's repository gets no git tools and writes nothing" do
      delegate!(agent_id: agent.id, mission_id: mission.id)
      smuggle_foreign_repository!
      script_llm(llm_reply(tool_calls: [ write_call("call_1", "add.go", add_go, "Add Add()") ]),
                 llm_reply(content: "done"))

      _task, iteration = run_one_iteration!

      expect(@llm_requests).not_to be_empty # the agent ran — it was the actuator that was withheld
      expect(advertised_tool_names).not_to include("write_file")
      expect(gitea_writes).to be_empty
      expect(iteration.git_commit_sha).to be_nil
      expect(iteration.check_results.dig("actuation", "reason")).to start_with("no repository attached")
      expect(branch_tip).to eq(@seed_sha)
    end
  end

  # ---------------------------------------------------------------- review F2, F4

  describe "the kill switch (review F2, F4)" do
    def halt!
      Ai::Autonomy::KillSwitchService.new(account: Account.find(account.id))
                                     .emergency_halt!(reason: "D2 review F2", triggered_by: user)
    end

    it "a halt between two writes lets the first land, refuses the second, and asks the model nothing more" do
      delegate!(agent_id: agent.id, mission_id: mission.id)
      replies = [ llm_reply(tool_calls: [ write_call("call_1", "add.go", add_go, "Add Add()") ]), :halt_then_write ]
      stub_request(:post, llm_url).to_return do |request|
        @llm_requests << JSON.parse(request.body)
        reply = replies.shift
        if reply == :halt_then_write
          halt! # thrown by "another process" while the loop is in flight
          reply = llm_reply(tool_calls: [ write_call("call_2", "add_test.go", passing_test_go, "Test Add()") ])
        end
        reply || llm_reply(content: "done")
      end

      _task, iteration = run_one_iteration!

      writes = @fake.requests.select { |r| %i[post put delete].include?(r[:method]) }.map { |r| r[:path] }
      expect(writes).to eq([ "/repos/acme/calc/contents/add.go" ])
      expect(@llm_requests.size).to eq(2) # the bridge stopped; no third model call
      tip = branch_tip
      expect(git!("rev-list", "--count", "#{@seed_sha}..#{tip}")).to eq("1")
      expect(git!("ls-tree", "--name-only", tip).split("\n")).not_to include("add_test.go")
      expect(iteration.git_commit_sha).to eq(tip)
    end

    it "the git write itself refuses while the account is halted" do
      delegate!(agent_id: agent.id, mission_id: mission.id)
      executor = Ai::Ralph::GitToolExecutor.new(ralph_loop: loop_record.reload)
      halt!

      result = executor.execute("write_file", { path: "add.go", content: add_go, message: "Add Add()" })

      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/suspended/i)
      expect(@fake.requests).to be_empty
      expect(branch_tip).to eq(@seed_sha)
    end

    it "run_iteration refuses to start while the account is halted: no model call, no write" do
      delegate!(agent_id: agent.id, mission_id: mission.id)
      task = loop_record.ralph_tasks.create!(task_key: "add-function", position: 1, status: "pending",
                                             execution_type: "agent", description: "Add Add.")
      script_llm(llm_reply(tool_calls: [ write_call("call_1", "add.go", add_go, "Add Add()") ]))
      halt!

      result = Ai::Ralph::ExecutionService.new(ralph_loop: loop_record.reload).run_iteration

      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/suspended/i)
      expect(@llm_requests).to be_empty
      expect(@fake.requests).to be_empty
      expect(task.reload.status).to eq("pending")
      expect(branch_tip).to eq(@seed_sha)
    end
  end

  # ---------------------------------------------------------------- review F3: the default parks

  describe "with no policy row for the write (the default)", :no_policy_row do
    it "parks the commit for an operator: no SHA, one approval, and approving it replays the write and commits" do
      delegate!(agent_id: agent.id, mission_id: mission.id)
      script_llm(llm_reply(tool_calls: [ write_call("call_1", "add.go", add_go, "Add Add()") ]),
                 llm_reply(content: "Asked to add Add."))

      task, iteration = run_one_iteration!

      expect(advertised_tool_names).to include("write_file")
      expect(@fake.requests.map { |r| r[:method] }).not_to include(:post, :put)
      expect(branch_tip).to eq(@seed_sha)
      expect(iteration.git_commit_sha).to be_nil
      expect(task.status).not_to eq("passed")
      expect(test_job_requests).to be_empty

      operation = Ai::DeferredOperation.find_by!(account: account, action_category: "ralph.repository_write")
      approval = operation.approval_request
      expect(approval.status).to eq("pending")
      actuation = iteration.check_results["actuation"]
      expect(actuation["parked_changes"]).to eq([ { "path" => "add.go", "tool" => "write_file",
                                                    "approval_request_id" => approval.id } ])
      expect(actuation["reason"])
        .to eq("no commit: 1 change(s) await operator approval — write_file add.go (approval #{approval.id})")

      approval.approve!

      # The approval replays the write through the same guarded path, and it lands.
      tip = branch_tip
      expect(tip).not_to eq(@seed_sha)
      expect(git!("rev-parse", "#{tip}^")).to eq(@seed_sha)
      expect(git!("show", "#{tip}:add.go", strip: false)).to eq(add_go)
      expect(operation.reload.status).to eq("completed")
      expect(@fake.writes_refused).to be_empty
    end

    # The non-bridge path (an agent with platform tools off) runs the git tools
    # through the same binding, so its writes park by default too.
    it "a non-bridge write parks for an operator too" do
      plain_agent = create(:ai_agent, account: account, provider: ai_provider, creator: user, agent_type: "assistant",
                                      mcp_metadata: { "model_config" => { "model" => "test-model-1" },
                                                      "tool_access" => { "enabled" => false } })
      delegate!(agent_id: plain_agent.id, mission_id: mission.id)
      script_llm(llm_reply(tool_calls: [ write_call("call_1", "add.go", add_go, "Add Add()") ]),
                 llm_reply(content: "Asked to add Add."))

      _task, iteration = run_one_iteration!

      expect(advertised_tool_names).to include("write_file")
      expect(advertised_tool_names).not_to include("discover_skills") # the non-bridge path
      expect(@fake.requests.map { |r| r[:method] }).not_to include(:post, :put)
      expect(iteration.git_commit_sha).to be_nil
      expect(Ai::DeferredOperation.where(account: account, action_category: "ralph.repository_write").count).to eq(1)
      expect(iteration.check_results.dig("actuation", "reason"))
        .to start_with("no commit: 1 change(s) await operator approval — write_file add.go")
    end

    it "parks each write on its own approval" do
      delegate!(agent_id: agent.id, mission_id: mission.id)
      script_llm(
        llm_reply(tool_calls: [
          write_call("call_1", "add.go", add_go, "Add Add()"),
          write_call("call_2", "add_test.go", passing_test_go, "Test Add()")
        ]),
        llm_reply(content: "Asked to add Add and its test.")
      )

      run_one_iteration!

      operations = Ai::DeferredOperation.where(account: account, action_category: "ralph.repository_write")
      expect(operations.count).to eq(2)
      expect(operations.map(&:approval_request_id).compact.uniq.size).to eq(2)
      expect(branch_tip).to eq(@seed_sha)
    end
  end


  # ---------------------------------------------------------------- D2b

  # The non-bridge agent path (TaskExecutor#execute_via_agent → AgenticLoop →
  # #normalize_result) — taken by an agent with platform tools off. It carried the
  # same hardcoded checks_passed: true as the bridge, so a transcript that merely
  # CLAIMED a green run passed the task with no commit.
  describe "the non-bridge agent path (D2b)" do
    let(:plain_agent) do
      create(:ai_agent, account: account, provider: ai_provider, creator: user, agent_type: "assistant",
                        mcp_metadata: {
                          "model_config" => { "model" => "test-model-1" },
                          "tool_access" => { "enabled" => false }
                        })
    end

    it "a prose-only green claim with no commit is not a pass" do
      delegate!(agent_id: plain_agent.id, mission_id: mission.id)
      script_llm(llm_reply(content: "Added Add and its test. go test: 12 examples, 0 failures."))

      task, iteration = run_one_iteration!

      # Non-bridge: only the git tools were advertised, no platform tool.
      expect(advertised_tool_names).to include("write_file")
      expect(advertised_tool_names).not_to include("discover_skills")
      expect(iteration.git_commit_sha).to be_nil
      expect(branch_tip).to eq(@seed_sha)
      expect(iteration.checks_passed).to be(false)
      expect(task.status).not_to eq("passed")
      expect(iteration.check_results.dig("actuation", "reason")).to eq("no commit: the agent made no repository change")
      expect(test_job_requests).to be_empty
    end

    it "a commit on the non-bridge path is read back and waits on the real suite" do
      delegate!(agent_id: plain_agent.id, mission_id: mission.id)
      script_llm(
        llm_reply(tool_calls: [
          write_call("call_1", "add.go", add_go, "Add Add()"),
          write_call("call_2", "add_test.go", passing_test_go, "Test Add()")
        ]),
        llm_reply(content: "Implemented Add with a test.")
      )

      task, iteration = run_one_iteration!

      expect(advertised_tool_names).not_to include("discover_skills")
      tip = branch_tip
      expect(iteration.git_commit_sha).to eq(tip)
      expect(git!("rev-list", "--count", "#{@seed_sha}..#{tip}")).to eq("2")
      expect(iteration.checks_passed).to be(false)
      expect(iteration.check_results["awaiting_test_result"]).to be(true)
      expect(iteration.check_results.dig("actuation", "reason")).to eq("committed #{tip}; the sandboxed test run decides the pass")
      expect(task.status).not_to eq("passed")
      expect(test_job_requests.size).to eq(1)
    end
  end

  # ---------------------------------------------------------------- drift guard

  describe "GiteaContentsContractFake drift guard" do
    let(:client) { Devops::Git::ApiClient.for(git_credential) }

    it "accepts exactly the request bodies the real GiteaApiClient builds, and commits what they carry" do
      expect(client).to be_a(Devops::Git::GiteaApiClient)
      expect(git_credential.access_token).to be_present

      created = client.create_file("acme", "calc", "notes.md", "hello\n", message: "add notes", branch: branch)
      expect(created[:success]).to be(true), created.inspect
      expect(created.dig(:content, "commit", "sha")).to eq(branch_tip)

      file = client.get_file_content("acme", "calc", "notes.md", branch)
      updated = client.update_file("acme", "calc", "notes.md", "hello v2\n", file[:sha], message: "edit notes", branch: branch)
      expect(updated[:success]).to be(true), updated.inspect
      expect(updated.dig(:content, "commit", "sha")).to eq(branch_tip)
      expect(git!("show", "#{branch_tip}:notes.md", strip: false)).to eq("hello v2\n")

      post_body = @fake.requests.find { |r| r[:method] == :post }[:body]
      put_body = @fake.requests.find { |r| r[:method] == :put }[:body]
      # EQUALITY with the pinned client shape: a renamed, dropped or added key in
      # the client fails here instead of being silently accepted by the fake.
      expect(post_body.keys.sort).to eq(GiteaContentsContractFake::CLIENT_CREATE_KEYS.sort)
      expect(put_body.keys.sort).to eq(GiteaContentsContractFake::CLIENT_UPDATE_KEYS.sort)
      expect(Base64.strict_decode64(put_body["content"])).to eq("hello v2\n")
      expect(put_body["sha"]).to eq(file[:sha])
      expect(@fake.unknown_keys).to be_empty
      expect(@fake.writes_refused).to be_empty
    end

    it "refuses every request that breaks the contract, with Gitea's status, and commits nothing" do
      conn = Faraday.new(url: gitea_api)
      calc_sha = git!("rev-parse", "#{branch}:calc.go")
      auth = { "Authorization" => "token #{git_credential.access_token}", "Content-Type" => "application/json" }
      b64 = Base64.strict_encode64("x\n")
      cases = [
        [ :post, "new.txt", { "message" => "m", "branch" => branch }, auth, 422, /content is required/ ],
        [ :post, "new.txt", { "content" => "not base64!!", "branch" => branch }, auth, 422, /not valid base64/ ],
        [ :post, "calc.go", { "content" => b64, "branch" => branch }, auth, 422, /already exists/ ],
        [ :put, "calc.go", { "content" => b64, "branch" => branch }, auth, 422, /sha is required/ ],
        [ :put, "calc.go", { "content" => b64, "sha" => "0" * 40, "branch" => branch }, auth, 422, /sha does not match/ ],
        [ :post, "new.txt", { "content" => b64, "branch" => "no-such-branch" }, auth, 404, /branch does not exist/ ],
        [ :post, "new.txt", { "content" => b64, "branch" => branch }, { "Content-Type" => "application/json" }, 401, /token/ ],
        [ :post, "new.txt", "content=#{b64}", auth.merge("Content-Type" => "text/plain"), 422, /JSON object/ ]
      ]

      cases.each do |method, file_path, body, headers, status, message|
        response = conn.run_request(method, "repos/acme/calc/contents/#{file_path}",
                                    body.is_a?(Hash) ? body.to_json : body, headers)
        expect([ method, file_path, response.status ]).to eq([ method, file_path, status ])
        expect(JSON.parse(response.body)["message"]).to match(message)
      end

      expect(branch_tip).to eq(@seed_sha)
      expect(git!("rev-parse", "#{branch}:calc.go")).to eq(calc_sha)
    end
  end
end
