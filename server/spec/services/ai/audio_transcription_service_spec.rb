# frozen_string_literal: true

require "rails_helper"

# D3 transcription seam, now backed by a real provider path. Resolves an
# account credential whose provider declares audio_transcription, builds the
# adapter, resolves the model FROM the provider, and transcribes.
RSpec.describe Ai::AudioTranscriptionService do
  before do
    # Attachment after_create enqueues worker jobs — keep them off the wire.
    allow(WorkerJobService).to receive(:enqueue_chat_attachment_scan)
    allow(WorkerJobService).to receive(:enqueue_chat_transcription)
  end

  let(:attachment) { create(:chat_message_attachment, :audio, :with_file_object) }
  let(:account) { attachment.account }

  it "no-ops for a non-audio attachment" do
    image = create(:chat_message_attachment, :image)
    expect(described_class.new(image).call.reason).to eq("not_audio")
  end

  it "no-ops when the account has no audio_transcription provider" do
    result = described_class.new(attachment).call
    expect(result.ok?).to be false
    expect(result.reason).to eq("no_transcription_provider")
  end

  context "with a capable provider + active credential" do
    let!(:provider) do
      create(:ai_provider, account: account, provider_type: "openai",
             capabilities: %w[chat audio_transcription],
             supported_models: [ { "id" => "whisper-1", "capabilities" => %w[audio_transcription] } ])
    end
    let!(:credential) do
      create(:ai_provider_credential, account: account, provider: provider, is_active: true)
    end

    it "transcribes via the resolved adapter + provider-resolved model" do
      adapter = instance_double(Ai::Llm::Adapters::OpenaiAdapter, transcribe: "hello world")
      allow(Ai::Llm::AdapterFactory).to receive(:build).and_return(adapter)
      allow(attachment.file_object).to receive(:read).and_return("AUDIOBYTES")

      result = described_class.new(attachment).call

      expect(adapter).to have_received(:transcribe)
        .with(hash_including(model: "whisper-1", audio_bytes: "AUDIOBYTES"))
      expect(result.ok?).to be true
      expect(result.text).to eq("hello world")
    end

    it "no-ops (no_transcription_model) when the provider exposes no transcription model" do
      provider.update!(supported_models: [ { "id" => "gpt-4o", "capabilities" => %w[chat] } ])
      adapter = instance_double(Ai::Llm::Adapters::OpenaiAdapter, transcribe: "x")
      allow(Ai::Llm::AdapterFactory).to receive(:build).and_return(adapter)

      result = described_class.new(attachment).call
      expect(result.ok?).to be false
      expect(result.reason).to eq("no_transcription_model")
    end
  end
end
