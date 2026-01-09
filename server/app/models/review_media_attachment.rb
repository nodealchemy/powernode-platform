# frozen_string_literal: true

# Backward compatibility alias for Review::MediaAttachment
require_relative "review/media_attachment"
ReviewMediaAttachment = Review::MediaAttachment unless defined?(ReviewMediaAttachment)
