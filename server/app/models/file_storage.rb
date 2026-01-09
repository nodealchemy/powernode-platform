# frozen_string_literal: true

# Backward compatibility alias for FileManagement::Storage
require_relative "file_management/storage"
FileStorage = FileManagement::Storage unless defined?(FileStorage)
