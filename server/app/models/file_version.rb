# frozen_string_literal: true

# Backward compatibility alias for FileManagement::Version
require_relative "file_management/version"
FileVersion = FileManagement::Version unless defined?(FileVersion)
