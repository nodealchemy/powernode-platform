# frozen_string_literal: true

# Backward compatibility alias for FileManagement::ProcessingJob
require_relative "file_management/processing_job"
FileProcessingJob = FileManagement::ProcessingJob unless defined?(FileProcessingJob)
