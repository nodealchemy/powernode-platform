# frozen_string_literal: true

module System
  class NodePlatform < BaseRecord
    include System::Base

    # Associations
    belongs_to :account
    belongs_to :node_architecture, class_name: 'System::NodeArchitecture'
    has_many :node_templates, class_name: 'System::NodeTemplate', dependent: :restrict_with_error
    # has_many :node_modules will be added in Release 3

    # Validations
    validates :name, presence: true, uniqueness: { scope: :account_id }
  end
end
