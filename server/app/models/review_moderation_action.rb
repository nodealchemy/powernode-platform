# frozen_string_literal: true

# Backward compatibility alias for Review::ModerationAction
require_relative "review/moderation_action"
ReviewModerationAction = Review::ModerationAction unless defined?(ReviewModerationAction)
