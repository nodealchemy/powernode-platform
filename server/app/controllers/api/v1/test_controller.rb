# frozen_string_literal: true

module Api
  module V1
    # Test controller for E2E testing support
    # Only available in development and test environments
    class TestController < ApplicationController
      skip_before_action :authenticate_user!
      before_action :ensure_test_environment

      # POST /api/v1/test/reset
      # Resets test data for E2E testing
      def reset
        # Clear any test-specific caches
        Rails.cache.clear if Rails.cache.respond_to?(:clear)

        render_success(
          message: 'Test environment reset successfully',
          data: { timestamp: Time.current.iso8601 }
        )
      end

      # POST /api/v1/test/seed
      # Seeds test data for E2E testing
      def seed
        # Load cypress test users if available
        seed_file = Rails.root.join('db/seeds/cypress_test_users.rb')
        load(seed_file) if File.exist?(seed_file)

        render_success(
          message: 'Test data seeded successfully',
          data: { timestamp: Time.current.iso8601 }
        )
      end

      private

      def ensure_test_environment
        return if Rails.env.development? || Rails.env.test?

        render_error(
          'Test endpoints are only available in development and test environments',
          :forbidden
        )
      end
    end
  end
end
