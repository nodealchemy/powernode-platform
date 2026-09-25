# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Llm::Adapters::OpenaiAdapter do
  subject(:adapter) { described_class.new(api_key: "sk-test", base_url: "https://api.openai.com/v1") }

  # M-5: a later system message (turn-scoped context) stays at its position, so
  # the leading system message is byte-stable as the history grows. Mirrors
  # worker/spec/services/ai/llm/client_system_prompt_spec.rb.
  describe "mid-conversation system messages" do
    let(:messages) { [ { role: "user", content: "hi" } ] }

    it "keeps a later system message in place and the leading one byte-stable" do
      first = adapter.send(:build_chat_body, messages, "gpt-test", system_prompt: "core")
      grown = messages + [ { role: "system", content: "turn context", clear_at: "next_user_message" },
                           { role: "assistant", content: "ok" } ]
      body = adapter.send(:build_chat_body, grown, "gpt-test", system_prompt: "core")

      expect(body[:messages].first).to eq(first[:messages].first)
      expect(body[:messages].map { |m| m[:role] }).to eq(%w[system user system assistant])
      expect(body[:messages][2]).to eq(role: "system", content: "turn context")
    end
  end

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
