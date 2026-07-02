# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::ImageGenerationService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, :openai, account: account) }
  let!(:credential) { create(:ai_provider_credential, account: account, provider: provider, credentials: { "api_key" => "sk-test-key" }) }
  let(:service) { described_class.new(account: account, user: user) }
  let(:b64_png) { Base64.strict_encode64("PNGBYTES") }

  def stub_images_api(status: 200, body: nil)
    body ||= { data: [{ b64_json: b64_png, revised_prompt: "a refined cat" }] }
    stub_request(:post, described_class::OPENAI_IMAGES_URL)
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  describe "#generate (happy path)" do
    before { stub_images_api }

    it "returns the base64 image and revised prompt (store: false)" do
      result = service.generate(prompt: "a cat", store: false)

      expect(result[:image_data]).to eq(b64_png)
      expect(result[:revised_prompt]).to eq("a refined cat")
      expect(result[:model]).to eq("dall-e-3")
    end

    it "sends the bearer API key resolved from the provider credential" do
      service.generate(prompt: "a cat", store: false)

      expect(WebMock).to have_requested(:post, described_class::OPENAI_IMAGES_URL)
        .with(headers: { "Authorization" => "Bearer sk-test-key" })
    end

    it "stores the result as an ai_generated image/png file via FileStorageService" do
      storage_service = instance_double(FileStorageService)
      fo = build_stubbed(:file_object)
      captured = nil
      allow(FileStorageService).to receive(:new).with(account).and_return(storage_service)
      allow(storage_service).to receive(:upload_file) { |_io, **opts| captured = opts; fo }

      result = service.generate(prompt: "a cat")

      expect(result[:file_object]).to eq(fo)
      expect(captured[:content_type]).to eq("image/png")
      expect(captured[:category]).to eq("ai_generated")
      expect(captured[:metadata][:generator]).to eq("dall-e")
    end

    it "returns nil file_object when no file storage is configured" do
      allow(FileStorageService).to receive(:new).with(account)
        .and_raise(FileStorageService::StorageNotFoundError, "none")

      result = service.generate(prompt: "a cat")

      expect(result[:file_object]).to be_nil
    end
  end

  describe "errors" do
    it "raises on an invalid size" do
      expect { service.generate(prompt: "a cat", size: "10x10", store: false) }
        .to raise_error(described_class::GenerationError, /Invalid size/)
    end

    it "raises with the parsed provider error message when the API call fails" do
      stub_images_api(status: 400, body: { error: { message: "content policy violation" } })

      expect { service.generate(prompt: "a cat", store: false) }
        .to raise_error(described_class::GenerationError, /content policy violation/)
    end

    it "raises when no active openai provider exists" do
      credential.provider.update!(is_active: false)

      expect { service.generate(prompt: "a cat", store: false) }
        .to raise_error(described_class::GenerationError, /No active openai provider/)
    end
  end
end
