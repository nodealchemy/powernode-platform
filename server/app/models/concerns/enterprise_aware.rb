# frozen_string_literal: true

module EnterpriseAware
  extend ActiveSupport::Concern

  class_methods do
    def enterprise?
      defined?(PowernodeEnterprise::Engine)
    end
  end

  def enterprise?
    self.class.enterprise?
  end
end
