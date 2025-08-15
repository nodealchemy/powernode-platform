class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Set up UUIDv7 generation for new records
  before_create :generate_uuid7_id, if: -> { id.blank? }

  private

  def generate_uuid7_id
    self.id = UUID7.generate
  end
end
