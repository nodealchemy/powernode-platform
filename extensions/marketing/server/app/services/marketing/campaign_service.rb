# frozen_string_literal: true

module Marketing
  class CampaignService
    class CampaignError < StandardError; end

    def initialize(account)
      @account = account
    end

    # CRUD Operations
    def list(filters = {})
      scope = @account.marketing_campaigns

      scope = scope.where(status: filters[:status]) if filters[:status].present?
      scope = scope.by_type(filters[:campaign_type]) if filters[:campaign_type].present?
      scope = scope.where("name ILIKE ?", "%#{filters[:search]}%") if filters[:search].present?

      scope.recent
    end

    def find(id)
      @account.marketing_campaigns.find(id)
    end

    def create(params, creator:)
      campaign = @account.marketing_campaigns.build(params)
      campaign.creator = creator
      campaign.status ||= "draft"
      campaign.save!
      campaign
    end

    def update(campaign, params)
      campaign.update!(params)
      campaign
    end

    def destroy(campaign)
      campaign.destroy!
    end

    # Status Workflow
    def schedule(campaign, scheduled_at)
      validate_status!(campaign, "draft", "schedule")
      campaign.schedule!(scheduled_at)
      campaign
    end

    def activate(campaign)
      validate_status!(campaign, %w[draft scheduled], "activate")
      campaign.activate!
      campaign
    end

    def pause(campaign)
      validate_status!(campaign, "active", "pause")
      campaign.pause!
      campaign
    end

    def resume(campaign)
      validate_status!(campaign, "paused", "resume")
      campaign.resume!
      campaign
    end

    def complete(campaign)
      validate_status!(campaign, "active", "complete")
      campaign.complete!
      campaign
    end

    def archive(campaign)
      validate_status!(campaign, %w[completed draft], "archive")
      campaign.archive!
      campaign
    end

    # Execute campaign - dispatch to appropriate channel handlers
    def execute(campaign)
      validate_status!(campaign, %w[draft scheduled], "execute")

      campaign.activate!

      # Dispatch execution based on campaign type
      dispatch_execution(campaign)

      campaign
    end

    # Clone campaign
    def clone(campaign, new_name: nil)
      cloned = campaign.dup
      cloned.name = new_name || "#{campaign.name} (Copy)"
      cloned.slug = nil
      cloned.status = "draft"
      cloned.scheduled_at = nil
      cloned.started_at = nil
      cloned.completed_at = nil
      cloned.paused_at = nil
      cloned.spent_cents = 0
      cloned.save!

      # Clone content
      campaign.campaign_contents.each do |content|
        cloned_content = content.dup
        cloned_content.campaign = cloned
        cloned_content.status = "draft"
        cloned_content.approved_at = nil
        cloned_content.approved_by = nil
        cloned_content.save!
      end

      cloned
    end

    # Aggregate statistics across all campaigns
    def statistics
      campaigns = @account.marketing_campaigns

      {
        total: campaigns.count,
        by_status: {
          draft: campaigns.draft.count,
          scheduled: campaigns.scheduled.count,
          active: campaigns.active.count,
          paused: campaigns.paused.count,
          completed: campaigns.completed.count,
          archived: campaigns.archived.count
        },
        total_budget_cents: campaigns.sum(:budget_cents),
        total_spent_cents: campaigns.sum(:spent_cents),
        active_campaigns: campaigns.active.map(&:campaign_summary)
      }
    end

    private

    def validate_status!(campaign, allowed_statuses, action)
      statuses = Array(allowed_statuses)
      return if statuses.include?(campaign.status)

      raise CampaignError,
            "Cannot #{action} campaign: must be in #{statuses.join(' or ')} status (currently #{campaign.status})"
    end

    def dispatch_execution(campaign)
      case campaign.campaign_type
      when "email"
        dispatch_email_campaign(campaign)
      when "social"
        dispatch_social_campaign(campaign)
      when "multi_channel"
        dispatch_email_campaign(campaign) if campaign.channels.include?("email")
        dispatch_social_campaign(campaign) if (campaign.channels & %w[twitter linkedin facebook instagram]).any?
      end
    end

    def dispatch_email_campaign(campaign)
      Rails.logger.info "[Marketing] Dispatching email campaign #{campaign.id}"
      # Worker job dispatch would happen here via API
    end

    def dispatch_social_campaign(campaign)
      Rails.logger.info "[Marketing] Dispatching social campaign #{campaign.id}"
      # Worker job dispatch would happen here via API
    end
  end
end
