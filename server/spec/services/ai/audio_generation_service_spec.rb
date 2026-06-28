# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::AudioGenerationService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:voice_id) { "21m00Tcm4TlvDq8ikWAM" }
  let(:provider) { create(:ai_provider, :elevenlabs, account: account) }
  let!(:credential) { create(:ai_provider_credential, account: account, provider: provider, credentials: { "api_key" => "el-test-key", "voice_id" => voice_id }) }
  let(:service) { described_class.new(account: account, user: user) }
  let(:base) { "https://api.elevenlabs.io/v1" }

  def stub_tts(id: "21m00Tcm4TlvDq8ikWAM", body: "MP3BYTES", status: 200)
    stub_request(:post, "#{base}/text-to-speech/#{id}")
      .to_return(status: status, body: body, headers: { "Content-Type" => "audio/mpeg" })
  end

  describe "#generate (happy path)" do
    before { stub_tts }

    it "synthesizes audio and returns the bytes (store: false)" do
      result = service.generate(text: "Hello world", store: false)
      expect(result[:audio_data]).to eq("MP3BYTES")
      expect(result[:voice_id]).to eq(voice_id) # resolved from credential
      expect(result[:model]).to eq("eleven_multilingual_v2") # provider default
    end

    it "sends the xi-api-key header to ElevenLabs" do
      service.generate(text: "Hello", store: false)
      expect(WebMock).to have_requested(:post, "#{base}/text-to-speech/#{voice_id}")
        .with(headers: { "xi-api-key" => /\Ael-test/ })
    end

    it "stores the result as an ai_generated audio/mpeg file via FileStorageService" do
      storage_service = instance_double(FileStorageService)
      fo = build_stubbed(:file_object)
      captured = nil
      allow(FileStorageService).to receive(:new).with(account).and_return(storage_service)
      allow(storage_service).to receive(:upload_file) { |_io, **opts| captured = opts; fo }

      result = service.generate(text: "Narration line")
      expect(result[:file_object]).to eq(fo)
      expect(captured[:content_type]).to eq("audio/mpeg")
      expect(captured[:category]).to eq("ai_generated")
      expect(captured[:metadata][:generator]).to eq("elevenlabs")
    end

    it "honours an explicit voice_id" do
      stub_tts(id: "customVoice")
      result = service.generate(text: "Hi", voice_id: "customVoice", store: false)
      expect(result[:voice_id]).to eq("customVoice")
    end
  end

  describe "errors" do
    it "raises when text is blank" do
      expect { service.generate(text: "  ", store: false) }.to raise_error(described_class::GenerationError, /text is required/)
    end

    it "raises when the TTS call fails" do
      stub_tts(status: 422, body: { detail: { message: "bad voice" } }.to_json)
      expect { service.generate(text: "x", store: false) }
        .to raise_error(described_class::GenerationError, /ElevenLabs TTS failed/)
    end

    it "raises when no voice_id is available" do
      credential.update!(credentials: { "api_key" => "el-test-nokey" }) # no voice_id
      expect { service.generate(text: "x", store: false) }
        .to raise_error(described_class::GenerationError, /No voice_id/)
    end

    it "raises when no active elevenlabs provider exists" do
      credential.provider.update!(is_active: false)
      expect { service.generate(text: "x", store: false) }
        .to raise_error(described_class::GenerationError, /No active elevenlabs provider/)
    end
  end
end
