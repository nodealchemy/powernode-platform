# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Llm::Adapters::OpenaiAdapter do
  subject(:adapter) { described_class.new(api_key: "sk-test", base_url: "https://api.openai.com/v1") }

  describe "#transcribe" do
    it "uploads the audio as multipart and returns the transcript text" do
      resp = double("HTTPartyResponse", code: 200, parsed_response: { "text" => "hello world" })
      expect(HTTParty).to receive(:post).with(
        "https://api.openai.com/v1/audio/transcriptions",
        hash_including(multipart: true, headers: hash_including("Authorization" => "Bearer sk-test"))
      ).and_return(resp)

      text = adapter.transcribe(
        audio_bytes: "AUDIO", filename: "voice.ogg", content_type: "audio/ogg", model: "whisper-1"
      )
      expect(text).to eq("hello world")
    end

    it "raises RequestError on a non-2xx response (no fabricated transcript)" do
      resp = double("HTTPartyResponse", code: 400, parsed_response: {}, body: "bad request")
      allow(HTTParty).to receive(:post).and_return(resp)

      expect do
        adapter.transcribe(audio_bytes: "AUDIO", filename: "v.ogg", content_type: "audio/ogg", model: "whisper-1")
      end.to raise_error(Ai::Llm::Adapters::RequestError)
    end
  end
end
