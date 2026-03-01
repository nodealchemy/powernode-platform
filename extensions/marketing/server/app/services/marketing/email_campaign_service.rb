# frozen_string_literal: true

module Marketing
  class EmailCampaignService
    class EmailError < StandardError; end

    BATCH_SIZE = 100

    def initialize(campaign)
      @campaign = campaign
    end

    # Prepare recipients from all linked email lists
    def prepare_recipients
      lists = @campaign.email_lists.includes(:email_subscribers)
      subscribers = collect_unique_subscribers(lists)

      {
        total_recipients: subscribers.count,
        by_list: lists.map { |l| { id: l.id, name: l.name, count: l.active_subscribers.count } },
        ready: subscribers.count > 0
      }
    end

    # Dispatch email sending in batches (stub for worker integration)
    def dispatch_batch_send
      recipients = collect_unique_subscribers(@campaign.email_lists)

      raise EmailError, "No recipients found" if recipients.empty?

      content = @campaign.campaign_contents.by_channel("email").approved.first
      raise EmailError, "No approved email content found" unless content

      batch_count = (recipients.count.to_f / BATCH_SIZE).ceil

      Rails.logger.info "[Marketing::Email] Dispatching #{batch_count} batches for campaign #{@campaign.id}"

      # In production, this would enqueue worker jobs for each batch
      {
        campaign_id: @campaign.id,
        total_recipients: recipients.count,
        batch_size: BATCH_SIZE,
        batch_count: batch_count,
        content_id: content.id,
        dispatched: true
      }
    end

    # Handle bounce notification
    def handle_bounce(email:, bounce_type: "hard")
      subscribers = find_subscribers_by_email(email)

      subscribers.each do |subscriber|
        subscriber.record_bounce!
        Rails.logger.info "[Marketing::Email] Recorded #{bounce_type} bounce for #{email} in list #{subscriber.email_list_id}"
      end

      # Record metric
      record_bounce_metric(subscribers.count)

      { processed: subscribers.count, bounce_type: bounce_type }
    end

    # Handle unsubscribe request
    def handle_unsubscribe(email:, list_id: nil)
      subscribers = if list_id
                      Marketing::EmailSubscriber
                        .joins(:email_list)
                        .where(email: email.downcase, marketing_email_lists: { id: list_id })
                    else
                      find_subscribers_by_email(email)
                    end

      subscribers.each do |subscriber|
        subscriber.unsubscribe!
        Rails.logger.info "[Marketing::Email] Unsubscribed #{email} from list #{subscriber.email_list_id}"
      end

      # Record metric
      record_unsubscribe_metric(subscribers.count)

      { processed: subscribers.count }
    end

    # Import subscribers to a list
    def import_subscribers(email_list, subscribers_data)
      imported = 0
      skipped = 0
      errors = []

      subscribers_data.each do |data|
        subscriber = email_list.email_subscribers.find_or_initialize_by(email: data[:email]&.downcase&.strip)

        if subscriber.new_record?
          subscriber.assign_attributes(
            first_name: data[:first_name],
            last_name: data[:last_name],
            source: data[:source] || "import",
            status: email_list.double_opt_in? ? "pending" : "subscribed",
            subscribed_at: email_list.double_opt_in? ? nil : Time.current,
            custom_fields: data[:custom_fields] || {},
            tags: data[:tags] || []
          )

          if subscriber.save
            imported += 1
          else
            errors << { email: data[:email], errors: subscriber.errors.full_messages }
          end
        else
          skipped += 1
        end
      end

      email_list.update_subscriber_count!

      { imported: imported, skipped: skipped, errors: errors }
    end

    private

    def collect_unique_subscribers(lists)
      emails = Set.new
      subscribers = []

      lists.each do |list|
        list.active_subscribers.each do |sub|
          unless emails.include?(sub.email)
            emails.add(sub.email)
            subscribers << sub
          end
        end
      end

      subscribers
    end

    def find_subscribers_by_email(email)
      Marketing::EmailSubscriber
        .joins(email_list: :campaigns)
        .where(email: email.downcase, marketing_campaigns: { id: @campaign.id })
    end

    def record_bounce_metric(count)
      metric = current_metric
      return unless metric

      metric.increment!(:bounces, count)
    end

    def record_unsubscribe_metric(count)
      metric = current_metric
      return unless metric

      metric.increment!(:unsubscribes, count)
    end

    def current_metric
      @campaign.campaign_metrics.find_or_create_by(
        channel: "email",
        metric_date: Date.current
      )
    end
  end
end
