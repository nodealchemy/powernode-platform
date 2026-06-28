# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::AudioGenerationTool do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, user: user) }
  let(:file_object) { build_stubbed(:file_object, :audio, account: account) }

  describe ".definition" do
    it "exposes the audio_generation tool with an action param" do
      defn = described_class.definition
      expect(defn[:name]).to eq("audio_generation")
      expect(defn[:parameters]).to include(:action)
      expect(defn[:description].length).to be > 10
    end
  end

  describe "generate_audio" do
    it "delegates to AudioGenerationService and returns the file" do
      svc = instance_double(Ai::AudioGenerationService,
                            generate: { model: "eleven_multilingual_v2", voice_id: "v1", provider: "ElevenLabs", file_object: file_object })
      expect(Ai::AudioGenerationService).to receive(:new).with(account: account, user: user).and_return(svc)

      result = tool.execute(params: { action: "generate_audio", text: "Welcome to the demo" })
      expect(result[:success]).to be(true)
      expect(result[:voice_id]).to eq("v1")
      expect(result[:file][:id]).to eq(file_object.id)
    end

    it "requires text" do
      result = tool.execute(params: { action: "generate_audio" })
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/text is required/)
    end

    it "surfaces a GenerationError as a failure result" do
      svc = instance_double(Ai::AudioGenerationService)
      allow(Ai::AudioGenerationService).to receive(:new).and_return(svc)
      allow(svc).to receive(:generate).and_raise(Ai::AudioGenerationService::GenerationError, "no elevenlabs provider")

      result = tool.execute(params: { action: "generate_audio", text: "x" })
      expect(result[:success]).to be(false)
      expect(result[:error]).to eq("no elevenlabs provider")
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
