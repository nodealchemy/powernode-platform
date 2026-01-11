# frozen_string_literal: true

# Concern for models that can be published to the marketplace
# Include in: Ai::WorkflowTemplate, Devops::PipelineTemplate, Devops::IntegrationTemplate, Shared::PromptTemplate
#
# Required columns on the model:
#   - is_marketplace_published: boolean, default: false
#   - marketplace_status: string (pending, approved, rejected)
#   - marketplace_submitted_at: datetime
#   - marketplace_approved_at: datetime
#   - marketplace_rejection_reason: text
#   - account_id: uuid (association to publisher account)
#
module MarketplacePublishable
  extend ActiveSupport::Concern

  MARKETPLACE_STATUSES = %w[draft pending approved rejected].freeze

  included do
    # Scopes for marketplace queries
    scope :marketplace_published, -> { where(is_marketplace_published: true, marketplace_status: "approved") }
    scope :marketplace_pending, -> { where(is_marketplace_published: true, marketplace_status: "pending") }
    scope :marketplace_rejected, -> { where(is_marketplace_published: true, marketplace_status: "rejected") }
    scope :marketplace_draft, -> { where(is_marketplace_published: false).or(where(marketplace_status: "draft")) }

    # Scope to get all items published by an account
    scope :published_by_account, ->(account_id) {
      where(account_id: account_id, is_marketplace_published: true)
    }
  end

  # Check if user can publish this item to the marketplace
  def can_publish_to_marketplace?(user)
    return false unless user&.account

    # Check if user has marketplace.publish permission (via plan or role)
    return false unless user.has_permission?("marketplace.publish")

    # Check if account is within publish limit
    within_publish_limit?(user.account)
  end

  # Submit this template to the marketplace for review
  def submit_to_marketplace!(user)
    raise MarketplacePublishError, "No publishing permission" unless can_publish_to_marketplace?(user)
    raise MarketplacePublishError, "Already submitted" if marketplace_pending?
    raise MarketplacePublishError, "Already published" if marketplace_approved?

    transaction do
      update!(
        is_marketplace_published: true,
        marketplace_status: "pending",
        marketplace_submitted_at: Time.current,
        marketplace_rejection_reason: nil
      )
    end
  end

  # Admin approves the marketplace submission
  def approve_for_marketplace!(approved_by: nil)
    raise MarketplacePublishError, "Not pending review" unless marketplace_pending?

    transaction do
      update!(
        marketplace_status: "approved",
        marketplace_approved_at: Time.current
      )
    end
  end

  # Admin rejects the marketplace submission
  def reject_from_marketplace!(reason, rejected_by: nil)
    raise MarketplacePublishError, "Not pending review" unless marketplace_pending?

    transaction do
      update!(
        marketplace_status: "rejected",
        marketplace_rejection_reason: reason
      )
    end
  end

  # Publisher withdraws from marketplace
  def withdraw_from_marketplace!
    return false unless is_marketplace_published?

    transaction do
      update!(
        is_marketplace_published: false,
        marketplace_status: "draft",
        marketplace_submitted_at: nil,
        marketplace_approved_at: nil,
        marketplace_rejection_reason: nil
      )
    end
    true
  end

  # Resubmit after rejection
  def resubmit_to_marketplace!(user)
    raise MarketplacePublishError, "Not rejected" unless marketplace_rejected?
    raise MarketplacePublishError, "No publishing permission" unless can_publish_to_marketplace?(user)

    transaction do
      update!(
        marketplace_status: "pending",
        marketplace_submitted_at: Time.current,
        marketplace_rejection_reason: nil
      )
    end
  end

  # Status check methods
  def marketplace_draft?
    !is_marketplace_published? || marketplace_status == "draft"
  end

  def marketplace_pending?
    is_marketplace_published? && marketplace_status == "pending"
  end

  def marketplace_approved?
    is_marketplace_published? && marketplace_status == "approved"
  end

  def marketplace_rejected?
    is_marketplace_published? && marketplace_status == "rejected"
  end

  def marketplace_visible?
    marketplace_approved?
  end

  # Get the marketplace template type for this item
  def marketplace_template_type
    case self.class.name
    when "Ai::WorkflowTemplate"
      "workflow_template"
    when "Devops::PipelineTemplate"
      "pipeline_template"
    when "Devops::IntegrationTemplate"
      "integration_template"
    when "Shared::PromptTemplate"
      "prompt_template"
    else
      "unknown"
    end
  end

  private

  def within_publish_limit?(account)
    return true unless account.subscription&.plan

    plan = account.subscription.plan
    return true unless plan.marketplace_publish_enabled?
    return true if plan.marketplace_publish_unlimited?

    limit = plan.marketplace_publish_limit
    current_count = published_templates_count_for(account)
    current_count < limit
  end

  def published_templates_count_for(account)
    count = 0

    # Count across all publishable template types
    count += Ai::WorkflowTemplate.published_by_account(account.id).count if defined?(Ai::WorkflowTemplate)
    count += Devops::PipelineTemplate.published_by_account(account.id).count if defined?(Devops::PipelineTemplate)
    count += Devops::IntegrationTemplate.published_by_account(account.id).count if defined?(Devops::IntegrationTemplate)
    count += Shared::PromptTemplate.published_by_account(account.id).count if defined?(Shared::PromptTemplate)

    count
  end
end

# Custom error class for marketplace publishing errors
class MarketplacePublishError < StandardError; end
