# frozen_string_literal: true

# Backward compatibility alias for FileManagement::Tag
require_relative "file_management/tag"
FileTag = FileManagement::Tag unless defined?(FileTag)
