# frozen_string_literal: true

module Marketing
  class CampaignEmailList < ApplicationRecord
    # Associations
    belongs_to :campaign, class_name: "Marketing::Campaign", foreign_key: "campaign_id"
    belongs_to :email_list, class_name: "Marketing::EmailList", foreign_key: "email_list_id"

    # Validations
    validates :email_list_id, uniqueness: { scope: :campaign_id }
  end
end
