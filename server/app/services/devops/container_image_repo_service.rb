# frozen_string_literal: true

module Devops
  class ContainerImageRepoService
    class RepoCreationError < StandardError; end

    VARIANT_CONFIGS = {
      "base" => {
        description: "Base agent image with MCP auth bootstrap",
        packages: "curl jq bash openssl ca-certificates",
        include_entrypoint: true
      },
      "code" => {
        description: "Code-capable agent image (Node.js, Python, Git)",
        packages: "nodejs python3 git build-essential",
        parent_image: "powernode-agent-base"
      },
      "data" => {
        description: "Data processing agent image (Python, pandas deps)",
        packages: "python3 py3-pip py3-numpy",
        parent_image: "powernode-agent-base"
      },
      "media" => {
        description: "Media processing agent image (ffmpeg, ImageMagick, libvips)",
        packages: "ffmpeg imagemagick vips",
        parent_image: "powernode-agent-base"
      },
      "full" => {
        description: "Full-capability agent image (all tools)",
        packages: "nodejs python3 git build-essential ffmpeg imagemagick vips py3-pip",
        parent_image: "powernode-agent-base"
      },
      "custom" => {
        description: "Custom agent image (empty, user fills in)",
        packages: "",
        parent_image: "powernode-agent-base"
      }
    }.freeze

    def initialize(account:, user:)
      @account = account
      @user = user
      @gitea_client = build_gitea_client
    end

    # Create a Gitea repo with Dockerfile, CI/CD workflow, and optionally an entrypoint.
    #
    # @param name [String] image name (e.g. "powernode-agent-base", "powernode-agent-code")
    # @param variant_type [String] one of VARIANT_CONFIGS keys
    # @param parent_template [Devops::ContainerTemplate, nil] parent template for variant images
    # @return [Hash] { template:, repository:, files_created: }
    def create_image_repo(name:, variant_type:, parent_template: nil)
      config = VARIANT_CONFIGS[variant_type]
      raise RepoCreationError, "Unknown variant type: #{variant_type}" unless config

      # Create Gitea repository under the configured org
      gitea_org = ENV.fetch("POWERNODE_GITEA_ORG", "powernode")
      repo_result = @gitea_client.create_org_repository(gitea_org, name, {
        description: config[:description],
        private: false,
        auto_init: true,
        default_branch: "main"
      })

      # normalize_repository returns string keys; owner is a nested hash
      owner = repo_result.dig("owner", "login") || repo_result["full_name"]&.split("/")&.first || gitea_org
      repo_name = repo_result["name"] || name
      full_name = "#{owner}/#{repo_name}"

      webhook_secret = SecureRandom.hex(32)
      files_created = []

      # Generate and commit Dockerfile
      dockerfile = generate_dockerfile(variant_type, config, name)
      create_repo_file(owner, repo_name, "Dockerfile", dockerfile, "Add Dockerfile")
      files_created << "Dockerfile"

      # Generate entrypoint for base images
      if config[:include_entrypoint]
        entrypoint = generate_entrypoint_script
        create_repo_file(owner, repo_name, "entrypoint.sh", entrypoint, "Add MCP auth bootstrap entrypoint")
        files_created << "entrypoint.sh"
      end

      # Generate CI/CD workflow
      workflow = generate_build_workflow(name)
      create_repo_file(owner, repo_name, ".gitea/workflows/build-push.yml", workflow, "Add CI/CD build workflow")
      files_created << ".gitea/workflows/build-push.yml"

      # Create webhook on the repo
      create_registry_webhook(owner, repo_name, webhook_secret)

      # Create ContainerTemplate linked to the repo
      registry_url = ENV.fetch("POWERNODE_REGISTRY_URL", "git.ipnode.net/powernode")
      template = Devops::ContainerTemplate.create!(
        account: @account,
        created_by: @user,
        name: name,
        category: "ai-agent",
        image_name: name,
        image_tag: "latest",
        registry_url: registry_url,
        visibility: "account",
        status: "active",
        gitea_repo_full_name: full_name,
        webhook_secret: webhook_secret,
        parent_template: parent_template,
        auto_update: true,
        description: config[:description]
      )

      {
        template: template,
        repository: { name: repo_name, full_name: full_name, owner: owner },
        files_created: files_created
      }
    rescue StandardError => e
      Rails.logger.error "[ContainerImageRepo] Failed to create image repo #{name}: #{e.message}"
      raise RepoCreationError, "Image repo creation failed: #{e.message}"
    end

    private

    def generate_dockerfile(variant_type, config, name)
      if variant_type == "base"
        <<~DOCKERFILE
          FROM alpine:3.21

          RUN apk add --no-cache #{config[:packages]}

          COPY entrypoint.sh /usr/local/bin/entrypoint.sh
          RUN chmod +x /usr/local/bin/entrypoint.sh

          WORKDIR /workspace

          ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
          CMD ["sh"]
        DOCKERFILE
      else
        parent = config[:parent_image] || "powernode-agent-base"
        registry_url = ENV.fetch("POWERNODE_REGISTRY_URL", "git.ipnode.net/powernode")
        packages_line = config[:packages].present? ? "RUN apk add --no-cache #{config[:packages]}" : "# Add custom packages here"

        <<~DOCKERFILE
          FROM #{registry_url}/#{parent}:latest

          #{packages_line}

          WORKDIR /workspace
        DOCKERFILE
      end
    end

    def generate_entrypoint_script
      <<~'ENTRYPOINT'
        #!/bin/bash
        set -euo pipefail

        # Phase 1: OAuth token via client_credentials grant
        TOKEN_RESPONSE=$(curl -sf -X POST "$POWERNODE_TOKEN_ENDPOINT" \
          -H "Content-Type: application/x-www-form-urlencoded" \
          -d "grant_type=client_credentials" \
          -d "client_id=$POWERNODE_CLIENT_ID" \
          -d "client_secret=$POWERNODE_CLIENT_SECRET" \
          -d "scope=read write")

        ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
        EXPIRES_IN=$(echo "$TOKEN_RESPONSE" | jq -r '.expires_in')

        [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ] && { echo "FATAL: OAuth failed" >&2; exit 1; }
        export POWERNODE_ACCESS_TOKEN="$ACCESS_TOKEN"

        # Phase 2: Initialize MCP session
        MCP_INIT=$(curl -sf -X POST "${POWERNODE_MCP_URL}/api/v1/mcp/message" \
          -H "Authorization: Bearer $ACCESS_TOKEN" \
          -H "Content-Type: application/json" \
          -H "Accept: application/json" \
          -d "{\"jsonrpc\":\"2.0\",\"method\":\"initialize\",\"id\":1,\"params\":{\"protocolVersion\":\"2025-03-26\",\"capabilities\":{},\"clientInfo\":{\"name\":\"powernode-container-agent\",\"version\":\"1.0.0\"}}}")

        export MCP_SESSION_ID=$(echo "$MCP_INIT" | jq -r '.result.sessionId // empty')

        # Phase 3: Background token refresh
        (while true; do
          sleep $((EXPIRES_IN > 120 ? EXPIRES_IN - 120 : EXPIRES_IN / 2))
          REFRESH=$(curl -sf -X POST "$POWERNODE_TOKEN_ENDPOINT" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "grant_type=client_credentials&client_id=$POWERNODE_CLIENT_ID&client_secret=$POWERNODE_CLIENT_SECRET&scope=read+write")
          NEW_TOKEN=$(echo "$REFRESH" | jq -r '.access_token')
          [ -n "$NEW_TOKEN" ] && [ "$NEW_TOKEN" != "null" ] && {
            export POWERNODE_ACCESS_TOKEN="$NEW_TOKEN"
            EXPIRES_IN=$(echo "$REFRESH" | jq -r '.expires_in')
          }
        done) &

        # Phase 4: Execute agent workload
        exec "$@"
      ENTRYPOINT
    end

    def generate_build_workflow(image_name)
      <<~WORKFLOW
        name: Build and Push Agent Image
        on:
          push:
            branches: [main]
            paths: ['Dockerfile', 'entrypoint.sh', 'mcp-client/**']
          workflow_dispatch:

        jobs:
          build:
            runs-on: ubuntu-latest
            steps:
              - uses: actions/checkout@v4
              - uses: docker/login-action@v3
                with:
                  registry: git.ipnode.net
                  username: ${{ secrets.REGISTRY_USER }}
                  password: ${{ secrets.REGISTRY_TOKEN }}
              - uses: docker/build-push-action@v5
                with:
                  context: .
                  push: true
                  tags: |
                    git.ipnode.net/powernode/#{image_name}:latest
                    git.ipnode.net/powernode/#{image_name}:${{ github.sha }}
              - name: Notify Powernode
                run: |
                  curl -sf -X POST "${{ secrets.POWERNODE_WEBHOOK_URL }}" \\
                    -H "Content-Type: application/json" \\
                    -H "X-Gitea-Signature: $(echo -n '{}' | openssl dgst -sha256 -hmac '${{ secrets.WEBHOOK_SECRET }}' | cut -d' ' -f2)" \\
                    -d '{"repo":"#{image_name}","tag":"${{ github.sha }}","registry":"git.ipnode.net/powernode"}'
      WORKFLOW
    end

    def create_repo_file(owner, repo_name, path, content, message)
      @gitea_client.create_file(owner, repo_name, path, content, message: message, branch: "main")
    rescue StandardError => e
      Rails.logger.warn "[ContainerImageRepo] Failed to create #{path}: #{e.message}"
    end

    def create_registry_webhook(owner, repo_name, secret)
      callback_url = "#{ENV.fetch('POWERNODE_URL', 'http://backend:3000')}/api/v1/webhooks/container_registry"

      @gitea_client.post("/repos/#{owner}/#{repo_name}/hooks", {
        type: "gitea",
        active: true,
        events: %w[push workflow_run],
        config: {
          url: callback_url,
          content_type: "json",
          secret: secret
        }
      })
    rescue StandardError => e
      Rails.logger.warn "[ContainerImageRepo] Failed to create webhook: #{e.message}"
    end

    def build_gitea_client
      credential = @account.git_provider_credentials
        .joins(:provider)
        .where(git_providers: { provider_type: "gitea", is_active: true })
        .first

      raise RepoCreationError, "No active Gitea credentials found" unless credential

      Devops::Git::GiteaApiClient.new(credential)
    end
  end
end
