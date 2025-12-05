# frozen_string_literal: true

class FileObjectTag < ApplicationRecord
  # Authentication & Authorization

  # Associations
  belongs_to :file_object
  belongs_to :file_tag
  belongs_to :account

  # Validations
  validates :file_object_id, uniqueness: { scope: :file_tag_id }

  # Callbacks
  after_create :increment_tag_count
  after_destroy :decrement_tag_count

  private

  def increment_tag_count
    file_tag.increment_files_count!
  end

  def decrement_tag_count
    file_tag.decrement_files_count!
  end
end
