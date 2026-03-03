# frozen_string_literal: true

module Ai
  class ImageGenerationService
    OPENAI_IMAGES_URL = "https://api.openai.com/v1/images/generations"

    VALID_SIZES = %w[1024x1024 1024x1792 1792x1024].freeze
    VALID_QUALITIES = %w[standard hd].freeze
    VALID_STYLES = %w[vivid natural].freeze

    class GenerationError < StandardError; end

    attr_reader :account

    def initialize(account:)
      @account = account
    end

    # Generate an image using DALL-E 3
    #
    # @param prompt [String] image description
    # @param size [String] 1024x1024, 1024x1792, or 1792x1024
    # @param quality [String] standard or hd
    # @param style [String] vivid or natural
    # @param model [String] dall-e-3 (default)
    # @param filename [String] output filename (default: auto-generated)
    # @param store [Boolean] whether to store in FileManagement (default: true)
    # @return [Hash] result with :image_data (base64), :file_object (if stored), :revised_prompt
    def generate(prompt:, size: "1024x1024", quality: "hd", style: "vivid", model: "dall-e-3", filename: nil, store: true)
      validate_params!(size, quality, style)

      credential = resolve_credential
      api_key = credential.credentials["api_key"]
      raise GenerationError, "No API key found for OpenAI provider" if api_key.blank?

      response = call_api(api_key, prompt: prompt, size: size, quality: quality, style: style, model: model)
      image_data = parse_response(response)

      result = {
        image_data: image_data[:b64_json],
        revised_prompt: image_data[:revised_prompt],
        model: model,
        size: size,
        quality: quality,
        style: style
      }

      if store
        result[:file_object] = store_image(
          image_data[:b64_json],
          filename: filename || generate_filename(prompt),
          prompt: prompt,
          revised_prompt: image_data[:revised_prompt],
          model: model,
          size: size
        )
      end

      result
    end

    # Generate and return raw binary data without storing
    #
    # @return [String] raw PNG bytes
    def generate_raw(prompt:, size: "1024x1024", quality: "hd", style: "vivid", model: "dall-e-3")
      result = generate(prompt: prompt, size: size, quality: quality, style: style, model: model, store: false)
      Base64.decode64(result[:image_data])
    end

    private

    def validate_params!(size, quality, style)
      raise GenerationError, "Invalid size: #{size}. Valid: #{VALID_SIZES.join(', ')}" unless VALID_SIZES.include?(size)
      raise GenerationError, "Invalid quality: #{quality}. Valid: #{VALID_QUALITIES.join(', ')}" unless VALID_QUALITIES.include?(quality)
      raise GenerationError, "Invalid style: #{style}. Valid: #{VALID_STYLES.join(', ')}" unless VALID_STYLES.include?(style)
    end

    def resolve_credential
      # Find an OpenAI provider for this account
      provider = Ai::Provider.where(account: account, provider_type: "openai", is_active: true)
                             .first

      raise GenerationError, "No active OpenAI provider found for account #{account.id}" unless provider

      credential = provider.provider_credentials.active.where(account_id: account.id).first
      raise GenerationError, "No active credential found for OpenAI provider #{provider.id}" unless credential

      credential
    end

    def call_api(api_key, prompt:, size:, quality:, style:, model:)
      body = {
        model: model,
        prompt: prompt,
        n: 1,
        size: size,
        quality: quality,
        style: style,
        response_format: "b64_json"
      }

      response = HTTP.headers(
        "Authorization" => "Bearer #{api_key}",
        "Content-Type" => "application/json"
      ).timeout(120).post(OPENAI_IMAGES_URL, json: body)

      unless response.status.success?
        error_body = JSON.parse(response.body.to_s) rescue { "error" => { "message" => response.body.to_s } }
        error_msg = error_body.dig("error", "message") || "Unknown API error (HTTP #{response.status})"
        raise GenerationError, "DALL-E API error: #{error_msg}"
      end

      JSON.parse(response.body.to_s)
    rescue HTTP::Error => e
      raise GenerationError, "HTTP request failed: #{e.message}"
    end

    def parse_response(response_data)
      data = response_data.dig("data", 0)
      raise GenerationError, "No image data in API response" unless data

      {
        b64_json: data["b64_json"],
        revised_prompt: data["revised_prompt"]
      }
    end

    def store_image(b64_data, filename:, prompt:, revised_prompt:, model:, size:)
      raw_bytes = Base64.decode64(b64_data)
      io = StringIO.new(raw_bytes)

      storage_service = FileStorageService.new(account)
      storage_service.upload_file(
        io,
        filename: filename,
        content_type: "image/png",
        category: "ai_generated",
        metadata: {
          generator: "dall-e",
          model: model,
          prompt: prompt,
          revised_prompt: revised_prompt,
          size: size,
          generated_at: Time.current.iso8601
        }
      )
    rescue FileStorageService::StorageNotFoundError => e
      Rails.logger.warn "[ImageGenerationService] No file storage configured, skipping upload: #{e.message}"
      nil
    end

    def generate_filename(prompt)
      slug = prompt.parameterize[0..40]
      "ai_generated_#{slug}_#{SecureRandom.hex(4)}.png"
    end
  end
end
