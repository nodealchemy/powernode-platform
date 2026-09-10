# frozen_string_literal: true

require "rails_helper"

# Campaign 01a08c9b, increment E1 — the schedule read surface.
#
# The isolation oracle carries extra weight here: `devops_schedules` has NO
# account_id, so tenancy comes entirely from a join to the pipeline. A scope
# written on the schedule row alone would return every account's schedules and
# every other example in this file would still pass.
RSpec.describe Ai::Tools::ScheduleReadTool do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let!(:first_user) { create(:user, account: account) }

  def actor(*permissions)
    described_class.new(account: account, user: create(:user, account: account, permissions: permissions))
  end

  let(:tool) { actor("devops.schedules.read") }

  def advertised_actions = %w[list_schedules get_schedule]

  def schedule(owner: account, **attrs)
    pipeline = create(:devops_pipeline, account: owner)
    create(:devops_schedule, pipeline: pipeline, **attrs)
  end

  describe "declarations" do
    it "declares every advertised action, all read-only" do
      advertised = ::Ai::Tools::PlatformApiToolRegistry.all_tools
                                                       .select { |_, klass| klass == described_class.name }
                                                       .keys.map(&:to_s)
      expect(advertised).to match_array(advertised_actions)

      advertised.each do |action|
        declaration = described_class.declared_action(action)
        expect(declaration).not_to be_nil, "#{action} is advertised but not declared"
        expect(declaration[:mutating]).to be(false)
      end
    end

    it "carries readOnlyHint on the wire for every verb" do
      catalog = ::Mcp::ToolCatalog.new(protocol_version: ::Mcp::ProtocolService::ALL_SUPPORTED_VERSIONS.max)
      entries = catalog.list_entries.index_by { |t| t["name"] }

      advertised_actions.each do |action|
        expect(entries["platform.#{action}"]).not_to be_nil
        expect(entries["platform.#{action}"]["annotations"]).to include("readOnlyHint" => true)
      end
    end

    it "floors on devops.schedules.read, the name the REST controller checks" do
      expect(::Permissions.permission_exists?("devops.schedules.read")).to be true
      expect(described_class::ACTION_PERMISSIONS.values.uniq).to eq([ "devops.schedules.read" ])
      expect(described_class::ACTION_PERMISSIONS.keys).to match_array(advertised_actions)
    end
  end

  describe "permission enforcement" do
    it "refuses every verb without devops.schedules.read, and allows every verb with it" do
      row = schedule
      calls = [ { action: "list_schedules" }, { action: "get_schedule", id: row.id } ]

      stranger = actor
      calls.each do |params|
        result = stranger.execute(params: params)
        expect(result[:success]).to be(false), "#{params[:action]} was allowed without the permission"
        expect(result[:error]).to include("devops.schedules.read")
        expect(result[:data]).to be_nil
      end

      calls.each do |params|
        expect(tool.execute(params: params)[:success]).to be(true), "#{params[:action]} was refused for a holder"
      end
    end
  end

  # THE ONE THAT WOULD SILENTLY PASS. Tenancy is a join, not a column.
  describe "account isolation through the pipeline join" do
    it "lists only schedules whose PIPELINE belongs to this account" do
      mine = schedule(name: "Mine Schedule")
      theirs = schedule(owner: other_account, name: "Theirs Schedule")

      result = tool.execute(params: { action: "list_schedules" })
      expect(result.dig(:data, :schedules).map { |s| s[:id] }).to eq([ mine.id ])
      expect(result.to_json).not_to include("Theirs Schedule")
      expect(::Devops::Schedule.where(id: theirs.id)).to exist,
                                                        "the other account's schedule was not created — this oracle would pass vacuously"
    end

    it "reports another account's schedule as absent" do
      theirs = schedule(owner: other_account)

      result = tool.execute(params: { action: "get_schedule", id: theirs.id })
      expect(result[:success]).to be false
      expect(result[:error]).to include("not found")
    end
  end

  describe "list_schedules" do
    it "filters by pipeline and by active_only, both arms" do
      pipeline_a = create(:devops_pipeline, account: account)
      pipeline_b = create(:devops_pipeline, account: account)
      on_a = create(:devops_schedule, pipeline: pipeline_a, is_active: true)
      on_b = create(:devops_schedule, pipeline: pipeline_b, is_active: false)

      by_pipeline = tool.execute(params: { action: "list_schedules", pipeline_id: pipeline_a.id })
                        .dig(:data, :schedules).map { |s| s[:id] }
      expect(by_pipeline).to eq([ on_a.id ])
      expect(by_pipeline).not_to include(on_b.id)

      only_active = tool.execute(params: { action: "list_schedules", active_only: true })
                        .dig(:data, :schedules).map { |s| s[:id] }
      expect(only_active).to include(on_a.id)
      expect(only_active).not_to include(on_b.id)
    end

    it "returns the cron expression, timezone, run times and the owning pipeline" do
      row = schedule(cron_expression: "*/15 * * * *", timezone: "Europe/London", last_run_at: 2.hours.ago)

      listed = tool.execute(params: { action: "list_schedules" }).dig(:data, :schedules).first
      expect(listed).to include(cron_expression: "*/15 * * * *", timezone: "Europe/London", is_active: true)
      expect(listed[:last_run_at]).to be_present
      expect(listed[:pipeline][:id]).to eq(row.pipeline.id)
    end
  end

  describe "get_schedule" do
    it "adds the declared inputs, which the list shape deliberately omits" do
      row = schedule(inputs: { "branch" => "main" })

      detail = tool.execute(params: { action: "get_schedule", id: row.id }).dig(:data, :schedule)
      expect(detail[:inputs]).to eq("branch" => "main")

      listed = tool.execute(params: { action: "list_schedules" }).dig(:data, :schedules).first
      expect(listed).not_to have_key(:inputs)
    end
  end

  it "refuses an action it does not advertise" do
    expect(tool.execute(params: { action: "delete_schedule" })[:success]).to be false
  end
end
