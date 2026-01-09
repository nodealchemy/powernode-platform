# frozen_string_literal: true

# Backward compatibility alias for FileManagement::Share
require_relative "file_management/share"
FileShare = FileManagement::Share unless defined?(FileShare)
