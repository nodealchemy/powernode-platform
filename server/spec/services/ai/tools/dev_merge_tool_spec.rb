# frozen_string_literal: true

require "rails_helper"

# dev_merge_increment (IMP-e82f619dde7a) — the governed way to land a reviewed
# increment. The call parks; only an approved replay hands the merge to the
# worker, over the HTTP boundary. Every example stubs WorkerJobService, so
# nothing is enqueued anywhere real, and the server runs no git at all.
RSpec.describe Ai::Tools::DevMergeTool do
  let(:account) { create(:account) }
  let!(:user) { create(:user, account: account, permissions: [ "devops.repositories.write" ]) }
  let(:tool) { described_class.new(account: account, user: user, call_origin: Ai::Tools::CallOrigin::MCP_OAUTH) }
  let(:sha) { "a" * 40 }
  let(:attestation) { { "framework" => "rspec", "passed" => 12, "failed" => 0, "command" => "bundle exec rspec x" } }
  let!(:mirror) { create(:git_repository, account: account, full_name: "mirror-owner/platform") }
  let!(:repository) do
    create(:git_repository, account: account, full_name: "origin-owner/platform",
                            metadata: { Devops::GitRepository::PUSH_MIRRORS_KEY => [ mirror.id ] })
  end

  before do
    allow(WorkerJobService).to receive(:enqueue_job).and_return({ "data" => { "job_id" => "jid-1" } })
    # This host's private-extension names are declared, so the merge can know
    # what it must refuse (Ai::DevMerge::ForbiddenNames).
    SiteSetting.set(Ai::DevMerge::ForbiddenNames::SETTING_KEY, %w[zzhidden], setting_type: "json")
  end

  def indeterminate
    Ai::DevMerge::ForbiddenNames::Result.new(names: [], determinate: false, reason: "cannot tell which exist")
  end

  def merge(**overrides)
    params = { action: "dev_merge_increment", repository: repository.full_name, source_ref: "feature/increment",
               target_branch: "develop", expected_source_sha: sha, gate_attestation: attestation }.merge(overrides)
    tool.execute(params: params.with_indifferent_access)
  end

  def approve(parked, as: user, origin: Ai::ApprovalDecision::REST_SESSION)
    request = Ai::ApprovalRequest.find(parked[:data][:approval_request_id])
    Ai::Autonomy::ApprovalWorkflowService.new(account: account).approve(request: request, approver: as, origin: origin)
  end

  def operation_for(parked)
    Ai::DeferredOperation.find(parked[:data][:deferred_operation_id])
  end

  describe "the advertised contract" do
    let(:description) { described_class.action_definitions["dev_merge_increment"][:description] }

    it "says develop needs a person's session by default, how an account relaxes it, and that release/master always do" do
      expect(description).to include("develop requires a human session by default")
      expect(description).to include("{requires_human_session: false}")
      expect(description).to include("release/* and master always require one")
    end
  end

  # The worker re-checks the allowlist before any git runs, with the SAME
  # literal. A drift between the two would let one side accept a target the
  # other was written to refuse.
  %w[TARGET_BRANCH REF SHA SUBMODULE_PATH].each do |name|
    it "uses the same #{name} literal as the worker" do
      worker_source = Rails.root.join("..", "worker", "app", "services", "devops", "increment_merge_service.rb").read
      literal = worker_source[/^\s*#{name} = %r\{(.+)\}$/, 1]

      expect(literal).to eq(described_class.const_get(name).source)
    end
  end

  describe "parking" do
    it "parks a develop merge for approval and enqueues nothing" do
      parked = merge

      expect(parked[:success]).to be(true)
      expect(parked[:data]).to include(pending: true, action_category: "dev.merge")
      expect(operation_for(parked).executor_class).to eq("Ai::Executors::DeferredToolCall")
      # develop is not FLAGGED human-only; only release/* and master are.
      request = Ai::ApprovalRequest.find(parked[:data][:approval_request_id])
      expect(request.request_data).not_to have_key("requires_human_session")
      expect(WorkerJobService).not_to have_received(:enqueue_job)
    end

    # The verb is declared destructive (the *dev_merge* deny overlay and the
    # destructive-declaration lint hold the two in step), and
    # Ai::Approvals::HumanSessionPolicy reads a destructive tool call as
    # needing a person's session. So by default a develop merge needs one too,
    # and the parked envelope says so rather than implying a tool door could
    # decide it.
    it "reports that a develop merge needs a person's session by default" do
      parked = merge

      expect(parked[:data]).to include(requires_human_session: true)
      expect(Ai::ApprovalRequest.find(parked[:data][:approval_request_id]).requires_human_session?).to be(true)
    end

    %w[master release/0.3.0].each do |target|
      it "parks a #{target} merge for a person's own session" do
        parked = merge(target_branch: target)

        expect(parked[:data]).to include(pending: true, requires_human_session: true)
        request = Ai::ApprovalRequest.find(parked[:data][:approval_request_id])
        expect(request.request_data["requires_human_session"]).to be(true)
        expect(WorkerJobService).not_to have_received(:enqueue_job)
      end
    end
  end

  describe "the remotes a person approves are the remotes that run" do
    it "pins the resolved remotes into the parked call and names them on the approval card" do
      parked = merge
      operation = operation_for(parked)

      expect(operation.params.dig("tool_params", "_pinned_remotes", "repository"))
        .to eq([ { "id" => repository.id, "full_name" => repository.full_name },
                 { "id" => mirror.id, "full_name" => mirror.full_name } ])
      expect(operation.approval_request.description).to include("origin-owner/platform", "mirror-owner/platform")
    end

    it "writes the pin itself: a caller-supplied pin is overwritten" do
      parked = merge(_pinned_remotes: { "repository" => [ { "id" => "forged", "full_name" => "x/y" } ] })

      expect(operation_for(parked).params.dig("tool_params", "_pinned_remotes", "repository").map { |r| r["id"] })
        .to eq([ repository.id, mirror.id ])
    end
  end

  describe "refused before it parks, so no one is asked to approve a merge that can only fail" do
    before { allow(Shared::ExtensionPaths).to receive(:private_slugs).and_return(%w[zzhidden]) }

    def expect_refused(result, message)
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(message)
      expect(Ai::ApprovalRequest.count).to eq(0)
      expect(WorkerJobService).not_to have_received(:enqueue_job)
    end

    it("a short SHA") { expect_refused(merge(expected_source_sha: "abc123"), /40-character/) }
    %w[feature/x main release release/..x release/-x].each do |target|
      it("the target #{target.inspect}") { expect_refused(merge(target_branch: target), /target_branch/) }
    end
    it("a ref that reads as an option") { expect_refused(merge(source_ref: "--upload-pack=x"), /source_ref/) }
    it("an attestation that is not an object") { expect_refused(merge(gate_attestation: "trust me"), /gate_attestation/) }

    it "a missing attestation" do
      expect { merge(gate_attestation: {}) }.to raise_error(ArgumentError, /gate_attestation/)
      expect(Ai::ApprovalRequest.count).to eq(0)
    end
    it("a repository outside the account") { expect_refused(merge(repository: create(:git_repository).full_name), /not a repository/) }

    it "a host that cannot tell which private extensions exist" do
      allow(Ai::DevMerge::ForbiddenNames).to receive(:resolve).and_return(indeterminate)

      expect_refused(merge, /cannot tell which exist/)
    end

    it "a remote whose clone URL is not https" do
      mirror.update!(clone_url: "http://git.example.invalid/mirror-owner/platform.git")

      expect_refused(merge, /https/)
    end

    it "a remote whose clone URL carries userinfo" do
      mirror.update!(clone_url: "https://user:pw@git.example.invalid/mirror-owner/platform.git")

      expect_refused(merge, /https/)
    end

    it "a configured mirror that is no longer active" do
      mirror.update!(is_archived: true)

      expect_refused(merge, /fewer remotes than configured/)
    end

    it "a pointer bump whose summary carries an AI attribution line" do
      bump = { parent_repository: repository.full_name, submodule_path: "extensions/demo",
               summary: "Co-Authored-By: Someone <x@example.invalid>" }

      expect_refused(merge(pointer_bump: bump), /AI attribution/)
    end

    it "a pointer bump whose summary names a private extension, without echoing the name" do
      bump = { parent_repository: repository.full_name, submodule_path: "extensions/demo", summary: "wire the Zzhidden seam" }

      result = merge(pointer_bump: bump)
      expect_refused(result, /private extension/)
      expect(result[:error]).not_to match(/zzhidden/i)
    end

    it "a pointer bump path that climbs out of the repository" do
      bump = { parent_repository: repository.full_name, submodule_path: "../etc" }

      expect_refused(merge(pointer_bump: bump), /submodule_path/)
    end
  end

  describe "the approved replay" do
    it "dispatches exactly once, with every configured remote, and audits the dispatch" do
      parked = merge
      expect(approve(parked)).to be(true)

      expect(WorkerJobService).to have_received(:enqueue_job).once
      expect(WorkerJobService).to have_received(:enqueue_job).with(
        "Git::DevMergeIncrementJob",
        hash_including(queue: "services", args: [ hash_including(
          "deferred_operation_id" => operation_for(parked).id,
          "source_ref" => "feature/increment", "target_branch" => "develop", "expected_source_sha" => sha,
          "remotes" => [ hash_including("repository_id" => repository.id), hash_including("repository_id" => mirror.id) ]
        ) ])
      )

      operation = operation_for(parked)
      expect(operation.status).to eq("completed")
      # What Api::V1::Internal::Ai::DevMergesController later reads to decide
      # whether EVERY dispatched remote was reached.
      expect(operation.result.dig("data", "dispatched")).to be(true)
      expect(operation.result.dig("data", "remotes").map { |r| r["repository_id"] }).to eq([ repository.id, mirror.id ])
      # A second decision on the same operation is a no-op, never a second dispatch.
      operation.on_approval_decision(operation.approval_request)
      expect(WorkerJobService).to have_received(:enqueue_job).once

      row = AuditLog.find_by!(action: "dev_merge.dispatched", resource_id: operation.id)
      expect(row.metadata).to include("gate_attestation" => attestation, "expected_source_sha" => sha,
                                      "target_branch" => "develop")
      expect(row.metadata.to_json).not_to include("forbidden_names")
    end

    it "hands the worker the names Ai::DevMerge::ForbiddenNames resolves, and only there" do
      allow(Ai::DevMerge::ForbiddenNames).to receive(:resolve)
        .and_return(Ai::DevMerge::ForbiddenNames::Result.new(names: %w[zzhidden zz-other], determinate: true))
      approve(merge)

      expect(WorkerJobService).to have_received(:enqueue_job)
        .with(anything, hash_including(args: [ hash_including("forbidden_names" => %w[zzhidden zz-other]) ]))
    end

    it "refuses to dispatch when the names became unknowable after the call parked" do
      parked = merge
      allow(Ai::DevMerge::ForbiddenNames).to receive(:resolve).and_return(indeterminate)
      approve(parked)

      expect(WorkerJobService).not_to have_received(:enqueue_job)
      expect(operation_for(parked).result["error"]).to match(/cannot tell which exist/)
    end

    it "refuses to dispatch when the remote set changed after approval was asked for" do
      parked = merge
      extra = create(:git_repository, account: account, full_name: "late-owner/platform")
      repository.update!(metadata: { Devops::GitRepository::PUSH_MIRRORS_KEY => [ mirror.id, extra.id ] })
      approve(parked)

      expect(WorkerJobService).not_to have_received(:enqueue_job)
      expect(operation_for(parked).result["error"]).to match(/remote set changed/)
    end

    it "refuses to dispatch when the repository was archived after the call parked" do
      parked = merge
      repository.update!(is_archived: true)
      approve(parked)

      expect(WorkerJobService).not_to have_received(:enqueue_job)
      expect(operation_for(parked).result.dig("error")).to match(/not active/)
    end
  end

  describe "no approval, no job" do
    it "an auto_approve policy row cannot turn the park into an unattended merge" do
      Ai::InterventionPolicy.create!(account: account, scope: "global", action_category: "dev.merge",
                                     policy: "auto_approve", is_active: true, priority: 100)

      result = merge

      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/approved request/)
      expect(WorkerJobService).not_to have_received(:enqueue_job)
    end

    it "a rejected request dispatches nothing" do
      parked = merge
      request = Ai::ApprovalRequest.find(parked[:data][:approval_request_id])
      Ai::Autonomy::ApprovalWorkflowService.new(account: account)
                                           .reject(request: request, approver: user, comments: "no",
                                                   origin: Ai::ApprovalDecision::REST_SESSION)

      expect(WorkerJobService).not_to have_received(:enqueue_job)
    end
  end

  describe "an account that lifts the session requirement for dev.merge" do
    let(:other) { create(:user, account: account, permissions: [ "devops.repositories.write" ]) }

    before do
      Ai::InterventionPolicy.create!(account: account, scope: "global", action_category: "dev.merge",
                                     policy: "require_approval", is_active: true, priority: 100,
                                     conditions: { "requires_human_session" => false })
    end

    it "lets another principal approve a develop merge through a tool door" do
      parked = merge

      expect(parked[:data]).not_to have_key(:requires_human_session)
      expect(approve(parked, as: other, origin: Ai::Tools::CallOrigin::MCP_OAUTH)).to be(true)
      expect(WorkerJobService).to have_received(:enqueue_job).once
    end

    %w[master release/0.3.0].each do |target|
      it "cannot lift it for #{target}: the call's own flag wins" do
        parked = merge(target_branch: target)

        expect(parked[:data]).to include(requires_human_session: true)
        expect(Ai::ApprovalRequest.find(parked[:data][:approval_request_id]).requires_human_session?).to be(true)
        expect(approve(parked, as: other, origin: Ai::Tools::CallOrigin::MCP_OAUTH)).to be(false)
        expect(WorkerJobService).not_to have_received(:enqueue_job)
      end
    end
  end

  describe "release/* and master need a person's own session" do
    it "is not approvable through a tool door, and dispatches nothing" do
      parked = merge(target_branch: "master")

      expect(approve(parked, origin: Ai::Tools::CallOrigin::MCP_OAUTH)).to be(false)
      expect(WorkerJobService).not_to have_received(:enqueue_job)
    end

    it "dispatches as the person who approved it in their own session" do
      parked = merge(target_branch: "release/0.3.0")

      expect(approve(parked)).to be(true)
      expect(WorkerJobService).to have_received(:enqueue_job).once
        .with(anything, hash_including(args: [ hash_including("committer" => hash_including("email" => user.email)) ]))
    end
  end

  it "is denied to every instance principal, whatever it was granted" do
    instance_tool = described_class.new(account: account, call_origin: Ai::Tools::CallOrigin::MCP_INSTANCE)
    instance_tool.instance_authorized = true

    expect { instance_tool.execute(params: { action: "dev_merge_increment", repository: repository.full_name }) }
      .to raise_error(Mcp::ProtocolService::PermissionDeniedError, /destroy-shaped/)
    expect(Mcp::Principal.destructive_tool?("platform.dev_merge_increment")).to be(true)
    expect(WorkerJobService).not_to have_received(:enqueue_job)
  end

  it "does nothing while the account's AI is suspended (kill switch)" do
    account.update!(ai_suspended: true)

    expect(merge[:error]).to match(/kill switch/)
    expect(Ai::ApprovalRequest.count).to eq(0)
  end
end
