# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Missions::AppLaunchService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:repository) { create(:git_repository, account: account) }
  let(:mission) { create(:ai_mission, :active, account: account, created_by: user, repository: repository) }
  let(:service) { described_class.new(mission: mission) }

  describe "#allocate_port!" do
    it "allocates a port in the valid range" do
      port = service.allocate_port!
      expect(port).to be_between(6000, 6199)
      expect(mission.reload.deployed_port).to eq(port)
    end

    it "avoids ports already in use" do
      create(:ai_mission, :with_deployment, account: account, created_by: user, deployed_port: 6000)
      port = service.allocate_port!
      expect(port).not_to eq(6000)
    end
  end

  describe "#record_deployment!" do
    it "stores deployment info" do
      service.record_deployment!(container_id: "abc123", url: "http://localhost:6001")
      mission.reload
      expect(mission.deployed_container_id).to eq("abc123")
      expect(mission.deployed_url).to eq("http://localhost:6001")
    end
  end

  describe "#cleanup!" do
    before do
      mission.update!(deployed_port: 6000, deployed_url: "http://localhost:6000", deployed_container_id: "abc")
    end

    it "clears deployment data" do
      service.cleanup!
      mission.reload
      expect(mission.deployed_port).to be_nil
      expect(mission.deployed_url).to be_nil
      expect(mission.deployed_container_id).to be_nil
    end
  end
end
