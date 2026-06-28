# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::VideoGenerationTool do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, user: user) }
  let(:file_object) { build_stubbed(:file_object, :video, account: account) }

  describe ".definition" do
    it "exposes the video_generation tool with an action param" do
      defn = described_class.definition
      expect(defn[:name]).to eq("video_generation")
      expect(defn[:parameters]).to include(:action)
      expect(defn[:description].length).to be > 10
    end
  end

  describe "generate_video" do
    it "delegates to VideoGenerationService and returns the file" do
      svc = instance_double(Ai::VideoGenerationService,
                            generate: { model: "gen3a_turbo", task_id: "t1", provider: "Runway", file_object: file_object })
      expect(Ai::VideoGenerationService).to receive(:new).with(account: account, user: user).and_return(svc)

      result = tool.execute(params: { action: "generate_video", prompt: "a dog skating" })
      expect(result[:success]).to be(true)
      expect(result[:model]).to eq("gen3a_turbo")
      expect(result[:file][:id]).to eq(file_object.id)
    end

    it "requires a prompt" do
      result = tool.execute(params: { action: "generate_video" })
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/prompt is required/)
    end

    it "surfaces a GenerationError as a failure result" do
      svc = instance_double(Ai::VideoGenerationService)
      allow(Ai::VideoGenerationService).to receive(:new).and_return(svc)
      allow(svc).to receive(:generate).and_raise(Ai::VideoGenerationService::GenerationError, "no runway provider")

      result = tool.execute(params: { action: "generate_video", prompt: "x" })
      expect(result[:success]).to be(false)
      expect(result[:error]).to eq("no runway provider")
    end
  end

  describe "unknown action" do
    it "returns an error" do
      result = tool.execute(params: { action: "nope" })
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/Unknown action/)
    end
  end
end
