# frozen_string_literal: true

module BusinessAware
  extend ActiveSupport::Concern

  class_methods do
    def business?
      Powernode::ExtensionRegistry.loaded?("business")
    end
  end

  def business?
    self.class.business?
  end
end
