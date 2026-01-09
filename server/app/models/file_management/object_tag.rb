# frozen_string_literal: true

module FileManagement
  class ObjectTag < ApplicationRecord
    # Associations
    belongs_to :object, class_name: "FileManagement::Object", foreign_key: :file_object_id
    belongs_to :tag, class_name: "FileManagement::Tag", foreign_key: :file_tag_id
    belongs_to :account

    # Validations
    validates :file_object_id, uniqueness: { scope: :file_tag_id }

    # Callbacks
    after_create :increment_tag_count
    after_destroy :decrement_tag_count

    private

    def increment_tag_count
      tag.increment_files_count!
    end

    def decrement_tag_count
      tag.decrement_files_count!
    end
  end
end

# Backward compatibility alias
FileObjectTag = FileManagement::ObjectTag unless defined?(FileObjectTag)
