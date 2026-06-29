# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Missions::SkillCompositionService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:mission) do
    create(:ai_mission, account: account, created_by: user, objective: "Build a feature")
  end
  let(:discovery_service) { instance_double(Ai::Tools::SemanticToolDiscoveryService) }

  before do
    allow(WorkerJobService).to receive(:enqueue_job).and_return(true)
    allow(Ai::Tools::SemanticToolDiscoveryService).to receive(:new).and_return(discovery_service)
    # No skills matched -> every non-approval phase becomes a generic task.
    allow(discovery_service).to receive(:discover).and_return([])
  end

  # Number of generic tasks a clean compose! should produce: one per
  # non-approval phase (excluding the terminal "completed" phase).
  def expected_task_count
    mission.phases_for_type.count do |phase_key|
      next false if phase_key == "completed"

      cfg = mission.mission_template.phases.find { |p| p["key"] == phase_key }
      !cfg&.dig("requires_approval")
    end
  end

  describe "#compose! transactional task creation" do
    subject(:service) { described_class.new(mission: mission) }

    it "rolls back a partial task set on mid-loop failure, then rebuilds the full graph on retry" do
      # Pre-link a ralph loop so that, without a transaction, the next compose!
      # would see the partial tasks via the `ralph_tasks.exists?` idempotency
      # guard and return the incomplete graph permanently.
      ralph_loop = create(:ai_ralph_loop, account: account)
      mission.update!(ralph_loop_id: ralph_loop.id)

      expect(expected_task_count).to be > 1 # need >=2 phases for a mid-loop failure

      # Raise on the 2nd generic-task creation, leaving a partial set behind.
      call_count = 0
      allow(service).to receive(:create_generic_task!).and_wrap_original do |orig, *args|
        call_count += 1
        raise StandardError, "boom on phase 2" if call_count == 2

        orig.call(*args)
      end

      expect { service.compose! }.to raise_error(StandardError, "boom on phase 2")

      # The whole task-creation block must roll back: no tasks persist.
      expect(Ai::RalphTask.where(ralph_loop_id: ralph_loop.id).count).to eq(0)

      # A clean re-compose! must rebuild the FULL graph (not a stuck partial).
      allow(service).to receive(:create_generic_task!).and_call_original
      result = service.compose!

      expect(result[:nodes].size).to eq(expected_task_count)
      expect(Ai::RalphTask.where(ralph_loop_id: ralph_loop.id).count).to eq(expected_task_count)
    end
  end
end
