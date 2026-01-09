# frozen_string_literal: true

# Backward compatibility alias for FileManagement::Object
require_relative "file_management/object"
FileObject = FileManagement::Object unless defined?(FileObject)
