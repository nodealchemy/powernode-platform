# frozen_string_literal: true

module Ai
  # Generates video from a text prompt via a per-account Runway provider.
  #
  # Runway's API is asynchronous: submit a task, poll until it succeeds, then
  # download the rendered clip. The base URL, model, and (optionally) the
  # endpoint paths + version header are resolved from the provider record /
  # metadata — nothing is hardcoded except documented defaults — so the exact
  # contract can be tuned to the live API without code changes. The result is
  # stored as an ai_generated FileManagement::Object (file_type video).
  #
  # No real (billable) call happens without an operator-provided credential; the
  # endpoint/response shapes below follow Runway's documented contract and should
  # be validated against the live API before production use.
  class VideoGenerationService
    include Ai::MediaGenerationCommon

    class GenerationError < StandardError; end

    PROVIDER_TYPE = "runway"
    DEFAULT_SUBMIT_PATH = "/image_to_video"
    DEFAULT_TASK_PATH = "/tasks"
    DEFAULT_POLL_INTERVAL = 5
    DEFAULT_MAX_POLLS = 60

    attr_reader :account, :user

    def initialize(account:, user: nil, poll_interval: DEFAULT_POLL_INTERVAL, max_polls: DEFAULT_MAX_POLLS)
      @account = account
      @user = user
      @poll_interval = poll_interval
      @max_polls = max_polls
    end

    # @return [Hash] :file_object (when store), :model, :task_id, :output_url
    def generate(prompt:, model: nil, duration: nil, ratio: nil, filename: nil, store: true)
      raise GenerationError, "prompt is required" if prompt.to_s.strip.empty?

      provider, credential = resolve_provider_and_credential
      api_key = credential.credentials["api_key"]
      raise GenerationError, "No API key found for #{PROVIDER_TYPE} provider" if api_key.blank?

      base = provider.api_base_url.to_s.chomp("/")
      raise GenerationError, "#{PROVIDER_TYPE} provider has no api_base_url" if base.empty?
      model ||= default_model(provider)

      task_id = submit_task(base, api_key, provider, prompt: prompt, model: model, duration: duration, ratio: ratio)
      output_url = poll_until_complete(base, api_key, provider, task_id)
      bytes = download_output(output_url)

      result = { model: model, task_id: task_id, output_url: output_url, provider: provider.name }
      if store
        result[:file_object] = store_video(bytes, filename: filename || generate_filename(prompt), prompt: prompt, model: model)
      else
        result[:video_data] = bytes
      end
      result
    end

    private

    def auth_headers(api_key, provider)
      headers = { "Authorization" => "Bearer #{api_key}", "Content-Type" => "application/json" }
      version = provider.metadata&.dig("api_version")
      headers["X-Runway-Version"] = version if version.present?
      headers
    end

    def submit_task(base, api_key, provider, prompt:, model:, duration:, ratio:)
      path = provider.metadata&.dig("submit_path") || DEFAULT_SUBMIT_PATH
      body = { model: model, promptText: prompt }
      body[:duration] = duration if duration
      body[:ratio] = ratio if ratio

      resp = HTTP.headers(auth_headers(api_key, provider)).timeout(120).post("#{base}#{path}", json: body)
      raise GenerationError, "Runway submit failed: #{api_error(resp)}" unless resp.status.success?

      data = JSON.parse(resp.body.to_s)
      task_id = data["id"] || data["uuid"] || data.dig("task", "id")
      raise GenerationError, "Runway submit returned no task id" if task_id.blank?
      task_id
    rescue HTTP::Error => e
      raise GenerationError, "HTTP request failed: #{e.message}"
    end

    def poll_until_complete(base, api_key, provider, task_id)
      task_path = provider.metadata&.dig("task_path") || DEFAULT_TASK_PATH

      @max_polls.times do
        resp = HTTP.headers(auth_headers(api_key, provider)).timeout(60).get("#{base}#{task_path}/#{task_id}")
        raise GenerationError, "Runway poll failed: #{api_error(resp)}" unless resp.status.success?

        data = JSON.parse(resp.body.to_s)
        case (data["status"] || data["state"]).to_s.upcase
        when "SUCCEEDED", "COMPLETE", "COMPLETED"
          url = Array(data["output"]).first || data.dig("artifacts", 0, "url") || data["output_url"]
          raise GenerationError, "Runway task succeeded but returned no output url" if url.blank?
          return url
        when "FAILED", "ERROR", "CANCELLED"
          raise GenerationError, "Runway task failed: #{data['failure'] || data['error'] || 'unknown error'}"
        end

        sleep(@poll_interval) if @poll_interval.to_f.positive?
      end

      raise GenerationError, "Runway task #{task_id} did not complete after #{@max_polls} polls"
    rescue HTTP::Error => e
      raise GenerationError, "HTTP request failed: #{e.message}"
    end

    def download_output(url)
      resp = HTTP.timeout(120).get(url)
      raise GenerationError, "Failed to download Runway output (HTTP #{resp.status})" unless resp.status.success?
      resp.body.to_s
    rescue HTTP::Error => e
      raise GenerationError, "Failed to download Runway output: #{e.message}"
    end

    def store_video(bytes, filename:, prompt:, model:)
      store_generated_file(
        bytes,
        filename: filename,
        content_type: "video/mp4",
        metadata: {
          generator: PROVIDER_TYPE,
          model: model,
          prompt: prompt
        }
      )
    end

    def generate_filename(prompt)
      media_filename(prompt, prefix: "ai_generated", ext: "mp4")
    end
  end
end
