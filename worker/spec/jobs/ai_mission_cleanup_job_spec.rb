# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiMissionCleanupJob, type: :job do
  let(:job_instance) { described_class.new }
  let(:job_args) { { "mission_id" => "mission-uuid-1", "account_id" => "acc-uuid-1" } }

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
    allow(AiAgentFleetReapJob).to receive(:perform_async)
  end

  after { Sidekiq::Worker.clear_all }

  def stub_mission(mission)
    allow(job_instance).to receive(:backend_api_get)
      .with("/api/v1/ai/missions/mission-uuid-1")
      .and_return("success" => true, "data" => { "mission" => mission })
  end

  describe "fleet-aware cleanup" do
    it "dispatches a fleet reap when the mission has provisioned members" do
      stub_mission(
        "id" => "mission-uuid-1",
        "configuration" => { "fleet" => { "members" => [ { "instance_id" => "i-1" }, { "instance_id" => "i-2" } ] } }
      )

      job_instance.execute(job_args)

      expect(AiAgentFleetReapJob).to have_received(:perform_async)
        .with({ "mission_id" => "mission-uuid-1", "account_id" => "acc-uuid-1" })
    end

    it "does not dispatch a reap when the mission has no fleet members" do
      stub_mission("id" => "mission-uuid-1", "configuration" => {})

      job_instance.execute(job_args)

      expect(AiAgentFleetReapJob).not_to have_received(:perform_async)
    end
  end
end
