# frozen_string_literal: true

module Devops
  # Deployment service abstraction
  # Supports multiple deployment strategies without direct Docker manipulation
  class DeploymentService
    attr_reader :logger, :api_client

    # Deployment strategies
    STRATEGY_WORKFLOW = "workflow"       # Trigger git provider workflow
    STRATEGY_WEBHOOK = "webhook"         # Call deployment webhook
    STRATEGY_API = "api"                 # Call deployment API
    STRATEGY_KUBERNETES = "kubernetes"   # Kubernetes API (future)

    def initialize(api_client:, logger: nil)
      @api_client = api_client
      @logger = logger || Logger.new($stdout)
    end

    # Deploy using the configured strategy
    # @param config [Hash] Deployment configuration
    # @param context [Hash] Execution context (trigger info, run info, etc.)
    # @return [Hash] Deployment result
    def deploy(config:, context:)
      strategy = config["strategy"] || STRATEGY_WORKFLOW
      environment = config["environment"] || "production"
      version = determine_version(config, context)

      log_info("Starting deployment", strategy: strategy, environment: environment, version: version)

      result = case strategy
               when STRATEGY_WORKFLOW
                 deploy_via_workflow(config, context, environment, version)
               when STRATEGY_WEBHOOK
                 deploy_via_webhook(config, context, environment, version)
               when STRATEGY_API
                 deploy_via_api(config, context, environment, version)
               when STRATEGY_KUBERNETES
                 deploy_via_kubernetes(config, context, environment, version)
               else
                 raise ArgumentError, "Unknown deployment strategy: #{strategy}"
               end

      # Update commit status if configured
      if config["update_status"] != false && context[:commit_sha]
        update_deployment_status(config, context, result)
      end

      result
    end

    private

    # Deploy by triggering a git provider workflow
    def deploy_via_workflow(config, context, environment, version)
      provider_config = fetch_provider_config(context)
      git_ops = GitOperationsService.new(provider_config: provider_config, logger: logger)

      workflow_file = config["workflow"] || "deploy.yml"
      repo = config["workflow_repo"] || context.dig(:repository, :full_name)
      ref = config["workflow_ref"] || "main"

      inputs = {
        environment: environment,
        version: version,
        triggered_by: "powernode-ci",
        run_id: context.dig(:pipeline_run, :id)
      }.merge(config["workflow_inputs"] || {})

      result = git_ops.trigger_workflow(
        repo: repo,
        workflow: workflow_file,
        ref: ref,
        inputs: inputs
      )

      if result
        {
          success: true,
          strategy: STRATEGY_WORKFLOW,
          environment: environment,
          version: version,
          workflow: workflow_file,
          message: "Deployment workflow triggered"
        }
      else
        {
          success: false,
          strategy: STRATEGY_WORKFLOW,
          error: "Workflow dispatch not supported or failed"
        }
      end
    end

    # Deploy by calling a webhook URL
    def deploy_via_webhook(config, context, environment, version)
      webhook_url = config["webhook_url"]
      raise ArgumentError, "webhook_url required for webhook strategy" unless webhook_url

      payload = {
        environment: environment,
        version: version,
        repository: context.dig(:repository, :full_name),
        commit_sha: context[:commit_sha],
        triggered_by: "powernode-ci",
        run_id: context.dig(:pipeline_run, :id),
        timestamp: Time.current.iso8601
      }.merge(config["webhook_payload"] || {})

      # Add authentication if configured
      headers = { "Content-Type" => "application/json" }
      if config["webhook_secret"]
        signature = generate_webhook_signature(payload.to_json, config["webhook_secret"])
        headers["X-Powernode-Signature"] = signature
      end
      if config["webhook_token"]
        headers["Authorization"] = "Bearer #{config['webhook_token']}"
      end

      response = make_http_request(
        url: webhook_url,
        method: :post,
        body: payload,
        headers: headers,
        timeout: config["timeout"] || 30
      )

      {
        success: response[:success],
        strategy: STRATEGY_WEBHOOK,
        environment: environment,
        version: version,
        status_code: response[:status_code],
        response: response[:body],
        message: response[:success] ? "Deployment webhook called" : "Webhook failed"
      }
    end

    # Deploy by calling a deployment API
    def deploy_via_api(config, context, environment, version)
      api_url = config["api_url"]
      raise ArgumentError, "api_url required for API strategy" unless api_url

      endpoint = config["api_endpoint"] || "/deploy"
      full_url = "#{api_url.chomp('/')}#{endpoint}"

      payload = {
        environment: environment,
        version: version,
        image_tag: config["image_tag"] || version,
        services: config["services"] || ["backend", "worker", "frontend"],
        metadata: {
          repository: context.dig(:repository, :full_name),
          commit_sha: context[:commit_sha],
          run_id: context.dig(:pipeline_run, :id)
        }
      }

      headers = { "Content-Type" => "application/json" }
      if config["api_token"]
        headers["Authorization"] = "Bearer #{config['api_token']}"
      end

      response = make_http_request(
        url: full_url,
        method: :post,
        body: payload,
        headers: headers,
        timeout: config["timeout"] || 60
      )

      {
        success: response[:success],
        strategy: STRATEGY_API,
        environment: environment,
        version: version,
        deployment_id: response.dig(:body, "deployment_id"),
        message: response[:success] ? "Deployment API called" : "API call failed"
      }
    end

    def deploy_via_kubernetes(config, context, environment, version)
      log_info("Kubernetes deployment requested", environment: environment, version: version)

      {
        success: false,
        strategy: STRATEGY_KUBERNETES,
        environment: environment,
        version: version,
        error: 'Kubernetes strategy requires cluster configuration. Use workflow or webhook strategy to trigger K8s deployments.'
      }
    end

    def determine_version(config, context)
      config["version"] ||
        context[:commit_sha]&.slice(0, 7) ||
        context.dig(:trigger_context, :head_sha)&.slice(0, 7) ||
        "latest"
    end

    def fetch_provider_config(context)
      # Get provider config from context or fetch from API
      context[:provider_config] || context.dig(:pipeline_run, :pipeline, :provider) ||
        api_client.get("/api/v1/internal/devops/providers/#{context[:provider_id]}")&.dig("data")
    end

    def update_deployment_status(config, context, result)
      return unless context[:commit_sha]

      provider_config = fetch_provider_config(context)
      return unless provider_config

      git_ops = GitOperationsService.new(provider_config: provider_config, logger: logger)

      state = result[:success] ? "success" : "failure"
      description = result[:success] ?
        "Deployed to #{result[:environment]}" :
        "Deployment failed: #{result[:error] || result[:message]}"

      git_ops.update_status(
        repo: context.dig(:repository, :full_name),
        sha: context[:commit_sha],
        state: state,
        context: "powernode/deploy/#{result[:environment]}",
        description: description,
        target_url: config["status_url"]
      )
    rescue StandardError => e
      log_error("Failed to update deployment status", error: e.message)
    end

    def make_http_request(url:, method:, body: nil, headers: {}, timeout: 30)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = timeout
      http.open_timeout = 10

      request = case method
                when :post then Net::HTTP::Post.new(uri)
                when :put then Net::HTTP::Put.new(uri)
                when :patch then Net::HTTP::Patch.new(uri)
                else Net::HTTP::Get.new(uri)
                end

      headers.each { |k, v| request[k] = v }
      request.body = body.to_json if body

      response = http.request(request)

      {
        success: response.code.to_i.between?(200, 299),
        status_code: response.code.to_i,
        body: response.body.present? ? JSON.parse(response.body) : nil
      }
    rescue JSON::ParserError
      {
        success: response.code.to_i.between?(200, 299),
        status_code: response.code.to_i,
        body: response.body
      }
    rescue StandardError => e
      {
        success: false,
        error: e.message
      }
    end

    def generate_webhook_signature(payload, secret)
      "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, payload)}"
    end

    def log_info(message, **metadata)
      formatted = "[DeploymentService] #{message}"
      formatted += " | #{metadata.map { |k, v| "#{k}=#{v}" }.join(' ')}" if metadata.any?
      logger.info formatted
    end

    def log_error(message, **metadata)
      formatted = "[DeploymentService] #{message}"
      formatted += " | #{metadata.map { |k, v| "#{k}=#{v}" }.join(' ')}" if metadata.any?
      logger.error formatted
    end
  end
end
