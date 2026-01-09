# frozen_string_literal: true

# Backward compatibility alias for Review::HelpfulnessVote
require_relative "review/helpfulness_vote"
ReviewHelpfulnessVote = Review::HelpfulnessVote unless defined?(ReviewHelpfulnessVote)
