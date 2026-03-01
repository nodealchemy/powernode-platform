# frozen_string_literal: true

namespace :gitea do
  desc "Setup branch protection rules on Gitea for Powernode repository"
  task setup_branch_protection: :environment do
    repository = ENV.fetch("GITEA_REPOSITORY", "powernode/powernode-platform")

    puts "Setting up branch protection for #{repository}..."

    service = Ai::Git::GiteaIntegrationService.new(
      repository_path: Rails.root.to_s,
      gitea_repository: repository
    )

    result = service.setup_branch_protection(
      branches: %w[master develop release/*],
      options: {
        enable_push: false,
        enable_merge_whitelist: true,
        required_approvals: 1,
        enable_status_check: true,
        dismiss_stale_approvals: true
      }
    )

    if result[:success]
      puts "Branch protection configured successfully:"
      result[:rules].each do |rule|
        puts "  - #{rule[:branch]}: OK"
      end
    else
      puts "Some rules failed:"
      result[:rules].each do |rule|
        status = rule[:success] ? "OK" : "FAILED: #{rule[:error]}"
        puts "  - #{rule[:branch]}: #{status}"
      end
    end
  end

  desc "Verify Gitea repository access and configuration"
  task verify: :environment do
    repository = ENV.fetch("GITEA_REPOSITORY", "powernode/powernode-platform")
    owner, repo = repository.split("/")

    puts "Verifying Gitea access for #{repository}..."

    begin
      credential = Devops::GitCredential.find_by(provider_type: "gitea", status: "active")
      raise "No active Gitea credential found" unless credential

      client = Devops::Git::GiteaApiClient.new(credential)
      repo_info = client.get_repository(owner, repo)

      puts "  Repository: #{repo_info['full_name']}"
      puts "  Default Branch: #{repo_info['default_branch']}"
      puts "  Private: #{repo_info['private']}"
      puts "  SSH URL: #{repo_info['ssh_url']}"
      puts "  Clone URL: #{repo_info['clone_url']}"
      puts "  Access: OK"
    rescue StandardError => e
      puts "  Error: #{e.message}"
      puts "  Ensure GITEA_URL and GITEA_TOKEN are configured."
    end
  end
end
