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
#
# Only two HTTP boundaries are replaced, both with STRING-keyed JSON bodies in the
# shape the real peer sends (a symbol-keyed double hiding a string-keyed body has
# burned this campaign twice):
#
#   1. the LLM — the worker's POST /api/v1/llm/complete_with_tools, whose body is
#      worker LlmProxyClient#format_response wrapped in { "data" => ... };
#   2. the Gitea REST API — there is no Gitea in a test, and the platform has no
#      local-filesystem git backend (Devops::Git::ApiClient.for knows only
#      github/gitlab/gitea). The responder below answers the Gitea contents/branch/
#      commit endpoints by running REAL git plumbing against a REAL repository in a
#      tmpdir, so every SHA the platform records is one git itself produced, and the
#      oracle reads it back with the git CLI — never from the platform's own record.
RSpec.describe "Delegated task git actuation (D2)", type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

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

  around do |example|
    Dir.mktmpdir("d2-actuation-") do |tmp|
      @tmp = tmp
      @origin = File.join(tmp, "origin")
      FileUtils.mkdir_p(@origin)
      example.run
    end
  end

  before do
    @gitea_requests = []
    @gitea_unhandled = []
    @llm_requests = []

    git!("init", "-q", "-b", "main")
    File.write(File.join(@origin, "go.mod"), "module example.com/calc\n\ngo 1.21\n")
    File.write(File.join(@origin, "calc.go"), "package calc\n")
    git!("add", "go.mod", "calc.go")
    git!("commit", "-q", "-m", "seed")
    @seed_sha = git!("rev-parse", "HEAD")
    git!("branch", branch, "main")

    stub_request(:any, %r{\A#{Regexp.escape(gitea_api)}/}).to_return { |request| gitea_respond(request) }
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

  def git!(*args, input: nil, env: {}, strip: true)
    out, err, status = Open3.capture3(git_env.merge(env), "git", "-C", @origin, *args, stdin_data: input.to_s)
    raise "git #{args.join(' ')} failed: #{err}" unless status.success?

    strip ? out.strip : out
  end

  def git_try(*args)
    git!(*args)
  rescue RuntimeError
    nil
  end

  def json_reply(status, body)
    { status: status, headers: { "Content-Type" => "application/json" }, body: body.to_json }
  end

  # The Gitea REST surface GitToolExecutor + GiteaApiClient actually call.
  def gitea_respond(request)
    path = Addressable::URI.unencode(request.uri.path.delete_prefix(URI(gitea_api).path))
    @gitea_requests << [ request.method, path ]
    prefix = "/repos/acme/calc/"
    return json_reply(404, "message" => "repo not found") unless path.start_with?(prefix)

    rest = path.delete_prefix(prefix)
    query = Rack::Utils.parse_query(request.uri.query.to_s)
    body = request.body.present? ? JSON.parse(request.body) : {}

    if request.method == :get && (m = rest.match(%r{\Abranches/(.+)\z}))
      sha = git_try("rev-parse", "--verify", "--quiet", "refs/heads/#{m[1]}")
      return json_reply(404, "message" => "branch not found") unless sha

      json_reply(200, "name" => m[1], "commit" => { "id" => sha, "sha" => sha })
    elsif request.method == :get && (m = rest.match(%r{\Acontents/(.+)\z}))
      file_reply(query["ref"].presence || "main", m[1])
    elsif %i[post put].include?(request.method) && (m = rest.match(%r{\Acontents/(.+)\z}))
      write_reply(request.method, m[1], body)
    elsif request.method == :get && (m = rest.match(%r{\Agit/commits/(\h{40})\z}))
      commit_reply(m[1])
    elsif request.method == :get && (m = rest.match(%r{\Acommits/(\h{40})\.diff\z}))
      { status: 200, headers: { "Content-Type" => "text/plain" }, body: git!("diff", "#{m[1]}^", m[1], strip: false) }
    else
      @gitea_unhandled << [ request.method, path ]
      json_reply(501, "message" => "not implemented by the D2 responder: #{request.method} #{path}")
    end
  end

  def file_reply(ref, file_path)
    commit = git_try("rev-parse", "--verify", "--quiet", "#{ref}^{commit}")
    blob = commit && git_try("rev-parse", "--verify", "--quiet", "#{commit}:#{file_path}")
    return json_reply(404, "message" => "file not found") unless blob

    content = git!("cat-file", "blob", blob, strip: false)
    json_reply(200, "name" => File.basename(file_path), "path" => file_path, "sha" => blob, "type" => "file",
                    "size" => content.bytesize, "encoding" => "base64", "content" => Base64.strict_encode64(content))
  end

  def write_reply(method, file_path, body)
    branch_name = body["branch"].presence || "main"
    parent = git_try("rev-parse", "--verify", "--quiet", "refs/heads/#{branch_name}")
    return json_reply(404, "message" => "branch does not exist") unless parent

    existing = git_try("rev-parse", "--verify", "--quiet", "#{parent}:#{file_path}")
    if method == :post && existing
      return json_reply(422, "message" => "repository file already exists [path: #{file_path}]")
    end
    if method == :put && existing != body["sha"]
      return json_reply(422, "message" => "sha does not match [given: #{body['sha']}, expected: #{existing}]")
    end

    content = Base64.strict_decode64(body["content"].to_s)
    blob = git!("hash-object", "-w", "--stdin", input: content)
    index = File.join(@tmp, "index-#{SecureRandom.hex(4)}")
    index_env = { "GIT_INDEX_FILE" => index }
    git!("read-tree", parent, env: index_env)
    git!("update-index", "--add", "--cacheinfo", "100644,#{blob},#{file_path}", env: index_env)
    tree = git!("write-tree", env: index_env)
    commit = git!("commit-tree", tree, "-p", parent, "-m", body["message"].to_s)
    git!("update-ref", "refs/heads/#{branch_name}", commit, parent)
    FileUtils.rm_f(index)

    json_reply(method == :post ? 201 : 200,
               "content" => { "name" => File.basename(file_path), "path" => file_path, "sha" => blob,
                              "type" => "file", "size" => content.bytesize },
               "commit" => { "sha" => commit, "message" => body["message"].to_s })
  end

  def commit_reply(sha)
    return json_reply(404, "message" => "commit not found") unless git_try("cat-file", "-e", "#{sha}^{commit}") || git_try("rev-parse", "--verify", "--quiet", "#{sha}^{commit}")

    parents = git!("rev-list", "--parents", "-n", "1", sha).split.drop(1)
    files = git!("diff-tree", "--no-commit-id", "--name-status", "-r", sha).lines.map do |line|
      status, name = line.strip.split("\t", 2)
      { "filename" => name, "status" => status == "A" ? "added" : "modified" }
    end
    person = { "name" => "gitea", "email" => "gitea@d2.test", "date" => Time.current.iso8601 }
    json_reply(200, "sha" => sha, "parents" => parents.map { |p| { "sha" => p } },
                    "commit" => { "message" => git!("log", "-1", "--format=%B", sha), "author" => person, "committer" => person },
                    "files" => files, "stats" => {})
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
    runner = lambda do |command:, dir:, timeout_seconds:|
      out, err, status = Open3.capture3({ "GOFLAGS" => "-mod=mod", "GOPROXY" => "off", "GOTOOLCHAIN" => "local" },
                                        command, chdir: dir)
      { stdout: out, stderr: err, exit_code: status.exitstatus, timeout_seconds: timeout_seconds }
    end
    Ai::Ralph::TestVerificationService.new(runner: runner)
                                      .verify(dir: checkout, root_entries: Dir.children(checkout), timeout_seconds: 120)
  end

  def test_job_requests
    WebMock::RequestRegistry.instance.requested_signatures.hash.keys.select do |sig|
      sig.method == :post && sig.uri.to_s.end_with?("/api/v1/jobs") &&
        JSON.parse(sig.body.to_s)["job_class"] == "AiTestExecutionJob"
    end
  end

  # ---------------------------------------------------------------- oracle

  it "a delegated task ends in a commit SHA read back from the repository and a verified TestVerificationService verdict" do
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
    tip = git!("rev-parse", "refs/heads/#{branch}")
    expect(iteration.git_commit_sha).to eq(tip)
    expect(git!("cat-file", "-t", tip)).to eq("commit")
    expect(git!("rev-list", "--count", "#{@seed_sha}..#{tip}")).to eq("2")
    expect(git!("show", "#{tip}:add_test.go", strip: false)).to eq(passing_test_go)

    # No fabricated pass: the bridge claims nothing; the task waits on the real suite.
    expect(iteration.checks_passed).to be(false)
    expect(iteration.check_results["awaiting_test_result"]).to be(true)
    expect(task.status).not_to eq("passed")
    jobs = test_job_requests
    expect(jobs.size).to eq(1)
    job_args = JSON.parse(jobs.first.body.to_s)["args"].first
    expect(job_args).to include("repository" => "acme/calc", "branch" => branch)

    # The real verifier over the read-back SHA.
    verification = verify_at(tip)
    expect(verification).to include(success: true, ran: true, framework: "gotest", exit_code: 0)
    expect(Ai::Ralph::TestVerificationService.adjudicate_check_results("output" => verification[:output])[:verdict])
      .to eq(:verified)

    expect(@gitea_unhandled).to be_empty
  end

  it "a task the agent cannot implement yields no SHA and no pass" do
    delegate!(agent_id: agent.id, mission_id: mission.id)
    script_llm(llm_reply(content: "I cannot implement this: the package spec is ambiguous."))

    task, iteration = run_one_iteration!

    expect(advertised_tool_names).to include("write_file") # the actuator WAS available
    expect(iteration.git_commit_sha).to be_nil
    expect(git!("rev-parse", "refs/heads/#{branch}")).to eq(@seed_sha)
    expect(@gitea_requests.map(&:first)).not_to include(:post, :put)
    expect(iteration.checks_passed).to be(false)
    expect(task.status).not_to eq("passed")
    expect(test_job_requests).to be_empty
  end

  it "the verifier's red arm: a committed failing test reads back as a real SHA and adjudicates contradicted" do
    delegate!(agent_id: agent.id, mission_id: mission.id)
    script_llm(
      llm_reply(tool_calls: [
        write_call("call_1", "add.go", add_go, "Add Add()"),
        write_call("call_2", "add_test.go", failing_test_go, "Test Add()")
      ]),
      llm_reply(content: "Implemented Add with a test.")
    )

    _task, iteration = run_one_iteration!

    tip = git!("rev-parse", "refs/heads/#{branch}")
    expect(iteration.git_commit_sha).to eq(tip)
    verification = verify_at(tip)
    expect(verification).to include(success: false, ran: true, framework: "gotest")
    expect(verification[:failed_count]).to be_positive
    expect(Ai::Ralph::TestVerificationService.adjudicate_check_results("output" => verification[:output])[:verdict])
      .to eq(:contradicted)
  end

  it "a delegation that carries no repository attaches no git tools and produces no SHA" do
    delegate!(agent_id: agent.id)
    script_llm(llm_reply(content: "Here is a plan for adding Add."))

    _task, iteration = run_one_iteration!

    expect(advertised_tool_names).not_to include("write_file")
    expect(iteration.git_commit_sha).to be_nil
    expect(git!("rev-parse", "refs/heads/#{branch}")).to eq(@seed_sha)
  end
end
