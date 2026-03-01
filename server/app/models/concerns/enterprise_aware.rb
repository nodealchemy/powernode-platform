# frozen_string_literal: true

module EnterpriseAware
  extend ActiveSupport::Concern

  class_methods do
    def enterprise?
      Powernode::ExtensionRegistry.loaded?("enterprise")
    end
  end

  def enterprise?
    self.class.enterprise?
  end
end
