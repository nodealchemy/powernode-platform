# frozen_string_literal: true

# Concern for handling UUIDv7 primary keys
module UuidGenerator
  extend ActiveSupport::Concern

  included do
    self.primary_key = "id"

    # Override the default UUID generation to use UUIDv7
    before_create :generate_uuid_v7, if: -> { id.blank? }
  end

  module ClassMethods
    def find_by_uuid(uuid_string)
      find_by(id: uuid_string)
    end

    def generate_uuid_v7
      UUID7.generate
    end
  end

  private

  def generate_uuid_v7
    return unless respond_to?(:id=)
    return unless self.class.column_names.include?("id")

    if id.blank?
      self.id = UUID7.generate
    end
  end
end
