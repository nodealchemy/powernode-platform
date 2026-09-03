# frozen_string_literal: true

require "rails_helper"

# server/lib/tasks/seed.rake — IMP-e8513b30152d.
#
# db:seed is FIRST BOOT ONLY (the hub's rails-start.sh seeds only while its
# durable .db-initialized marker is absent and runs db:migrate alone on every
# later boot; ops-hub 2026-08-24 measured nine seeded governance rows that never
# landed for exactly this reason). So an ESTABLISHED install upgraded onto this
# change has accounts with no `claude-code` provider scope, and the report path
# no longer mints one — it refuses by name. This narrow, absence-only task is
# that remedy: an operator should not have to re-run the whole seed set to add
# one per-account row.
RSpec.describe "db:seed:claude_code_provider_scopes" do
  let(:slug) { Ai::ClaudeExport::ProviderScopeSeeder::SLUG }

  # Rake::Application rather than Rails.application.load_tasks so this neither
  # depends on nor mutates global Rake state (precedent: claude_sync_spec.rb).
  def run_task!
    previous_application = Rake.application
    Rake.application = Rake::Application.new
    Rake.application.rake_require("tasks/seed", [ Rails.root.join("lib").to_s ], [])
    Rake::Task.define_task(:environment)
    original = $stdout
    $stdout = StringIO.new
    Rake::Task["db:seed:claude_code_provider_scopes"].invoke
  ensure
    $stdout = original
    Rake.application = previous_application
  end

  it "backfills the inactive, non-routable scope for every account that lacks one" do
    first = create(:account)
    second = create(:account)
    expect(Ai::Provider.where(slug: slug).count).to eq(0)

    run_task!

    [ first, second ].each do |account|
      scope = account.ai_providers.find_by(slug: slug)
      expect(scope).to be_present
      expect(scope.is_active).to be false
      expect(scope.provider_identifier).to eq(Ai::ClaudeExport::ProviderScopeSeeder::SOURCE_KEY)
      expect(Ai::Provider.platform_routable.where(account: account)).not_to include(scope)
    end
  end

  it "is idempotent — an existing scope is adopted, never duplicated" do
    account = create(:account)
    Ai::ClaudeExport::ProviderScopeSeeder.ensure_for!(account)

    run_task!

    expect(account.ai_providers.where(slug: slug).count).to eq(1)
  end

  it "is a no-op with no accounts" do
    expect { run_task! }.not_to raise_error
    expect(Ai::Provider.where(slug: slug).count).to eq(0)
  end
end
