# frozen_string_literal: true

require "rails_helper"

# Read-only resolution of the per-vendor tracker configuration. Values come from
# SiteSetting (DB-driven) with ENV fallback; NO secret is ever persisted in code.
RSpec.describe Ai::Connectors::TrackerConfig do
  describe "per-vendor config resolution" do
    it "reads Linear keys from SiteSetting" do
      SiteSetting.set("ai_tracker_linear_api_key", "lin_xxx", setting_type: "string")
      SiteSetting.set("ai_tracker_linear_team_id", "team-1", setting_type: "string")

      expect(described_class.linear_api_key).to eq("lin_xxx")
      expect(described_class.linear_team_id).to eq("team-1")
    end

    it "reads Jira keys from SiteSetting and strips a trailing slash from base_url" do
      SiteSetting.set("ai_tracker_jira_base_url", "https://acme.atlassian.net/", setting_type: "string")
      SiteSetting.set("ai_tracker_jira_email", "bot@acme.test", setting_type: "string")
      SiteSetting.set("ai_tracker_jira_api_token", "jira_xxx", setting_type: "string")
      SiteSetting.set("ai_tracker_jira_project_key", "OPS", setting_type: "string")

      expect(described_class.jira_base_url).to eq("https://acme.atlassian.net")
      expect(described_class.jira_email).to eq("bot@acme.test")
      expect(described_class.jira_api_token).to eq("jira_xxx")
      expect(described_class.jira_project_key).to eq("OPS")
    end

    it "defaults the Jira issue type to Task" do
      expect(described_class.jira_issue_type).to eq("Task")
      SiteSetting.set("ai_tracker_jira_issue_type", "Bug", setting_type: "string")
      expect(described_class.jira_issue_type).to eq("Bug")
    end

    it "reads the Sentry DSN from SiteSetting" do
      SiteSetting.set("ai_tracker_sentry_dsn", "https://k@o1.ingest.sentry.io/9", setting_type: "string")
      expect(described_class.sentry_dsn).to eq("https://k@o1.ingest.sentry.io/9")
    end

    it "falls back to ENV when no SiteSetting row exists" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("AI_TRACKER_LINEAR_API_KEY").and_return("env_lin")
      expect(described_class.linear_api_key).to eq("env_lin")
    end
  end

  describe ".enabled? is adapter-aware" do
    before { SiteSetting.set("ai_tracker_enabled", true, setting_type: "boolean") }

    it "is true for the linear adapter only when its required config is present" do
      SiteSetting.set("ai_tracker_adapter", "linear", setting_type: "string")
      expect(described_class.enabled?).to be(false)

      SiteSetting.set("ai_tracker_linear_api_key", "lin_xxx", setting_type: "string")
      SiteSetting.set("ai_tracker_linear_team_id", "team-1", setting_type: "string")
      expect(described_class.enabled?).to be(true)
    end

    it "is true for jira only with full config" do
      SiteSetting.set("ai_tracker_adapter", "jira", setting_type: "string")
      SiteSetting.set("ai_tracker_jira_base_url", "https://acme.atlassian.net", setting_type: "string")
      SiteSetting.set("ai_tracker_jira_email", "bot@acme.test", setting_type: "string")
      SiteSetting.set("ai_tracker_jira_api_token", "jira_xxx", setting_type: "string")
      SiteSetting.set("ai_tracker_jira_project_key", "OPS", setting_type: "string")
      expect(described_class.enabled?).to be(true)
    end

    it "is true for sentry when a DSN is configured" do
      SiteSetting.set("ai_tracker_adapter", "sentry", setting_type: "string")
      SiteSetting.set("ai_tracker_sentry_dsn", "https://k@o1.ingest.sentry.io/9", setting_type: "string")
      expect(described_class.enabled?).to be(true)
    end

    it "is false when the master switch is off" do
      SiteSetting.set("ai_tracker_enabled", false, setting_type: "boolean")
      SiteSetting.set("ai_tracker_adapter", "sentry", setting_type: "string")
      SiteSetting.set("ai_tracker_sentry_dsn", "https://k@o1.ingest.sentry.io/9", setting_type: "string")
      expect(described_class.enabled?).to be(false)
    end
  end
end
