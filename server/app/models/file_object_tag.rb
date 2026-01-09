# frozen_string_literal: true

# Backward compatibility alias for FileManagement::ObjectTag
require_relative "file_management/object_tag"
FileObjectTag = FileManagement::ObjectTag unless defined?(FileObjectTag)
