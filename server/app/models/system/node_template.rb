# frozen_string_literal: true

module System
  class NodeTemplate < BaseRecord
    include System::Base

    # Associations
    belongs_to :account
    belongs_to :node_platform, class_name: 'System::NodePlatform'
    has_many :nodes, class_name: 'System::Node', dependent: :restrict_with_error

    # Module associations (Release 3)
    has_many :template_modules, class_name: 'System::TemplateModule', dependent: :destroy
    has_many :node_modules, through: :template_modules

    # Validations
    validates :name, presence: true, uniqueness: { scope: :account_id }

    # Config accessors
    store_accessor :config
  end
end
