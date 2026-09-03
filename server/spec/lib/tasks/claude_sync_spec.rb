# frozen_string_literal: true

require "rails_helper"

# server/lib/tasks/claude_sync.rake — the operator face of the Claude Code
# agent export (claude:sync_agents) and of the REVERSE path
# (claude:import_agents), which files an Ai::AgentProposal per hand-authored
# agent file and never creates an agent directly (canonical rule: official
# agents are seeded canonicals; guidance-agent-escalation).
RSpec.describe "claude:* rake tasks" do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account, provider_type: "openai", is_active: true) }
  let(:target_dir) { Dir.mktmpdir("claude-sync-rake") }

  after { FileUtils.remove_entry(target_dir) if File.exist?(target_dir) }

  # Rake::Application is used rather than Rails.application.load_tasks so this
  # neither depends on nor mutates global Rake state; `:environment` is a no-op
  # here because rails_helper already booted the app.
  def run_task(name, *args, env: {})
    previous_application = Rake.application
    previous_env = env.keys.index_with { |k| ENV[k] }
    begin
      env.each { |k, v| ENV[k] = v }
      Rake.application = Rake::Application.new
      Rake.application.rake_require("tasks/claude_sync", [ Rails.root.join("lib").to_s ], [])
      Rake::Task.define_task(:environment)
      silence_stream { Rake::Task[name].invoke(*args) }
    ensure
      previous_env.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      Rake.application = previous_application
    end
  end

  def silence_stream
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end

  describe "claude:sync_agents" do
    it "exports the CANONICAL set only by default (no account rows), into TARGET_DIR" do
      canonical = create(:ai_agent, :global, is_system: true, name: "Canonical Planner")
      own = create(:ai_agent, account: account, provider: provider, name: "My Local Agent")

      run_task("claude:sync_agents", env: { "TARGET_DIR" => target_dir, "ACCOUNT_ID" => nil, "INCLUDE_ACCOUNT" => nil })

      expect(File.exist?(File.join(target_dir, "#{canonical.slug}.md"))).to be true
      expect(File.exist?(File.join(target_dir, "#{own.slug}.md"))).to be false
    end

    it "exports the account's own rows (not the canonicals) when ACCOUNT_ID is given" do
      canonical = create(:ai_agent, :global, is_system: true, name: "Canonical Planner")
      own = create(:ai_agent, account: account, provider: provider, name: "My Local Agent")

      run_task("claude:sync_agents", env: { "TARGET_DIR" => target_dir, "ACCOUNT_ID" => account.id })

      expect(File.exist?(File.join(target_dir, "#{own.slug}.md"))).to be true
      expect(File.exist?(File.join(target_dir, "#{canonical.slug}.md"))).to be false
    end
  end

  describe "claude:import_agents[path]" do
    let!(:concierge) do
      create(:ai_agent, account: account, provider: provider, name: "Concierge", is_concierge: true, status: "active")
    end

    def write_agent_file(name, frontmatter:, body:)
      File.write(File.join(target_dir, "#{name}.md"), "#{YAML.dump(frontmatter)}---\n\n#{body}\n")
    end

    it "files one agent_create proposal per hand-authored file with the would-be canonical spec, creating no agent" do
      write_agent_file("release-shepherd",
                       frontmatter: { "name" => "release-shepherd",
                                      "description" => "Use this agent when a release needs shepherding.",
                                      "model" => "opus",
                                      "tools" => "Read, Grep, mcp__powernode__platform_list_agents, mcp__powernode__platform_search_knowledge" },
                       body: "You shepherd releases through the gate.")

      agents_before = Ai::Agent.count
      expect {
        run_task("claude:import_agents", target_dir, env: { "ACCOUNT_ID" => account.id })
      }.to change(Ai::AgentProposal, :count).by(1)
      expect(Ai::Agent.count).to eq(agents_before)

      proposal = Ai::AgentProposal.order(:created_at).last
      expect(proposal.proposal_type).to eq("agent_create")
      expect(proposal.status).to eq("pending_review")
      expect(proposal.ai_agent_id).to eq(concierge.id)
      expect(proposal.account_id).to eq(account.id)

      spec = proposal.proposed_changes
      expect(spec["slug"]).to eq("release-shepherd")
      expect(spec["name"]).to eq("Release Shepherd")
      expect(spec["agent_type"]).to eq("assistant")
      expect(spec["description"]).to eq("Use this agent when a release needs shepherding.")
      expect(spec["system_prompt"]).to eq("You shepherd releases through the gate.")
      expect(spec.dig("tool_access", "tool_families")).to contain_exactly("list_agents", "search_knowledge")
      expect(spec.dig("model_config", "model_requirements", "tier")).to eq("reasoning")
    end

    it "attributes the proposal to the Platform Architect when one exists" do
      architect = create(:ai_agent, account: account, provider: provider, name: "Platform Architect", status: "active")
      write_agent_file("some-agent", frontmatter: { "name" => "some-agent", "description" => "x", "model" => "sonnet" },
                                     body: "Body.")

      run_task("claude:import_agents", target_dir, env: { "ACCOUNT_ID" => account.id })

      expect(Ai::AgentProposal.order(:created_at).last.ai_agent_id).to eq(architect.id)
    end

    it "skips generated files (those carrying the generated header) and files without frontmatter" do
      write_agent_file("generated-one", frontmatter: { "name" => "generated-one", "description" => "x", "model" => "sonnet" },
                                        body: "#{Ai::ClaudeExport::AgentSkeletonSync::GENERATED_HEADER}\n\nfetch me")
      File.write(File.join(target_dir, "notes.md"), "just prose, no frontmatter\n")

      expect {
        run_task("claude:import_agents", target_dir, env: { "ACCOUNT_ID" => account.id })
      }.not_to change(Ai::AgentProposal, :count)
    end
  end
end
