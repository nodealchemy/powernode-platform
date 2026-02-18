# frozen_string_literal: true

# Enterprise associations for Account model
# Loaded by the PowernodeEnterprise engine via config.to_prepare decorator loading.
#
# These associations are only available when the enterprise engine is present.
Account.class_eval do
  # AI Credit System associations (Enterprise - Credit System)
  has_one :ai_account_credits, class_name: "Ai::AccountCredit", dependent: :destroy
  has_many :ai_credit_transactions, class_name: "Ai::CreditTransaction", dependent: :destroy
  has_many :ai_credit_purchases, class_name: "Ai::CreditPurchase", dependent: :destroy
  has_many :ai_credit_transfers_sent, class_name: "Ai::CreditTransfer", foreign_key: :from_account_id, dependent: :destroy
  has_many :ai_credit_transfers_received, class_name: "Ai::CreditTransfer", foreign_key: :to_account_id, dependent: :destroy

  # AI Outcome Billing associations (Enterprise - Outcome Billing)
  has_many :ai_outcome_definitions, class_name: "Ai::OutcomeDefinition", dependent: :destroy
  has_many :ai_sla_contracts, class_name: "Ai::SlaContract", dependent: :destroy
  has_many :ai_outcome_billing_records, class_name: "Ai::OutcomeBillingRecord", dependent: :destroy
  has_many :ai_sla_violations, class_name: "Ai::SlaViolation", dependent: :destroy

  # MCP Hosting associations (Enterprise - MCP Managed Hosting)
  has_many :mcp_hosted_servers, class_name: "Mcp::HostedServer", dependent: :destroy
  has_many :mcp_server_subscriptions, class_name: "Mcp::ServerSubscription", dependent: :destroy

  # AI Agent Marketplace associations (Enterprise - Marketplace Monetization)
  has_one :ai_publisher_account, class_name: "Ai::PublisherAccount", dependent: :destroy
  has_many :ai_marketplace_transactions, class_name: "Ai::MarketplaceTransaction", dependent: :destroy

  # AI Governance Suite associations (Enterprise - Governance & Compliance)
  has_many :ai_compliance_policies, class_name: "Ai::CompliancePolicy", dependent: :destroy
  has_many :ai_policy_violations, class_name: "Ai::PolicyViolation", dependent: :destroy
  has_many :ai_approval_chains, class_name: "Ai::ApprovalChain", dependent: :destroy
  has_many :ai_approval_requests, class_name: "Ai::ApprovalRequest", dependent: :destroy
  has_many :ai_data_classifications, class_name: "Ai::DataClassification", dependent: :destroy
  has_many :ai_data_detections, class_name: "Ai::DataDetection", dependent: :destroy
  has_many :ai_compliance_reports, class_name: "Ai::ComplianceReport", dependent: :destroy
  has_many :ai_compliance_audit_entries, class_name: "Ai::ComplianceAuditEntry", dependent: :destroy

  # Reseller Program associations (Enterprise - Reseller System)
  has_one :reseller, dependent: :destroy
  has_one :reseller_referral, class_name: "ResellerReferral", foreign_key: :referred_account_id, dependent: :destroy

  # BaaS (Billing-as-a-Service) associations (Enterprise - Multi-Tenancy)
  has_many :baas_tenants, class_name: "BaaS::Tenant", dependent: :destroy

  # Revenue Intelligence associations (Enterprise - Revenue Intelligence)
  has_many :revenue_snapshots, dependent: :destroy
  has_many :customer_health_scores, dependent: :destroy
  has_many :churn_predictions, dependent: :destroy
  has_many :revenue_forecasts, dependent: :destroy
  has_many :analytics_alerts, dependent: :destroy
end
