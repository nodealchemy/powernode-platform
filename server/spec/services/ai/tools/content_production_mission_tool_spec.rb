# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::ContentProductionMissionTool do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, user: user) }

  before do
    # The content_production default template is seeded in increment 1; the
    # mission auto-assigns the default template for its type on create.
    create(:ai_mission_template, :content_production)
    allow(WorkerJobService).to receive(:enqueue_job).and_return(true)
  end

  describe ".definition" do
    it "exposes the content_production tool with an action param" do
      defn = described_class.definition
      expect(defn[:name]).to eq("content_production")
      expect(defn[:parameters]).to include(:action)
      expect(defn[:description].length).to be > 10
    end
  end

  describe "start_content_production" do
    it "creates and starts a content_production mission + linked bundle" do
      result = tool.execute(params: { action: "start_content_production", name: "Launch Teaser", bundle_type: "video_project" })

      expect(result[:success]).to be(true)
      expect(result[:mission][:mission_type]).to eq("content_production")
      expect(result[:mission][:status]).to eq("active")
      expect(result[:mission][:current_phase]).to eq("brief")
      expect(result[:bundle][:bundle_type]).to eq("video_project")

      mission = account.ai_missions.find(result[:mission][:id])
      bundle = FileManagement::Bundle.find(result[:bundle][:id])
      expect(bundle.mission_id).to eq(mission.id)
      expect(mission.created_by).to eq(user)
    end

    it "defaults bundle_type to video_project" do
      result = tool.execute(params: { action: "start_content_production", name: "X" })
      expect(result[:bundle][:bundle_type]).to eq("video_project")
    end

    it "rejects an invalid bundle_type" do
      result = tool.execute(params: { action: "start_content_production", name: "X", bundle_type: "hologram" })
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/invalid bundle_type/)
    end

    it "requires a name" do
      result = tool.execute(params: { action: "start_content_production" })
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/name is required/)
    end

    it "requires user context" do
      result = described_class.new(account: account).execute(params: { action: "start_content_production", name: "X" })
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/user context/)
    end

    it "stores the brief in mission configuration" do
      result = tool.execute(params: { action: "start_content_production", name: "X", brief: { "goal" => "promo" } })
      mission = account.ai_missions.find(result[:mission][:id])
      expect(mission.configuration["brief"]).to eq("goal" => "promo")
    end
  end

  describe "content_production_status" do
    it "returns the mission summary" do
      started = tool.execute(params: { action: "start_content_production", name: "Status Me" })
      result = tool.execute(params: { action: "content_production_status", mission_id: started[:mission][:id] })

      expect(result[:success]).to be(true)
      expect(result[:mission][:current_phase]).to eq("brief")
    end

    it "requires mission_id" do
      result = tool.execute(params: { action: "content_production_status" })
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/mission_id is required/)
    end

    it "errors for an unknown mission" do
      result = tool.execute(params: { action: "content_production_status", mission_id: "00000000-0000-0000-0000-000000000000" })
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/not found/)
    end
  end

  describe "unknown action" do
    it "returns an error" do
      result = tool.execute(params: { action: "explode" })
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/Unknown action/)
    end
  end
end
