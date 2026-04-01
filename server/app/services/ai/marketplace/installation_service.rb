# frozen_string_literal: true

module Ai
  module Marketplace
    # Service for managing template installations and subscriptions
    #
    # NOTE: AI Workflow Templates have been removed from the platform.
    # This service is retained as a stub to prevent controller errors.
    #
    class InstallationService
      attr_reader :account, :user

      class InstallationError < StandardError; end

      def initialize(account:, user:)
        @account = account
        @user = user
      end

      def install(template_id:, custom_configuration: {}, installation_notes: nil)
        error_result("AI Workflow Templates have been removed")
      end

      def uninstall(subscription_id:, delete_workflow: false)
        error_result("AI Workflow Templates have been removed")
      end

      def list_installations(options = {})
        {
          installations: [],
          pagination: {
            current_page: 1,
            per_page: 25,
            total_pages: 0,
            total_count: 0
          }
        }
      end

      def get_installation(subscription_id)
        error_result("AI Workflow Templates have been removed")
      end

      def check_for_updates
        {
          updates_available: [],
          total_count: 0
        }
      end

      def apply_update(subscription_id:, preserve_customizations: true)
        error_result("AI Workflow Templates have been removed")
      end

      def apply_all_updates(preserve_customizations: true)
        {
          total_attempted: 0,
          successful: 0,
          failed: 0,
          details: []
        }
      end

      def rate_template(template_id:, rating:, feedback: {})
        error_result("AI Workflow Templates have been removed")
      end

      private

      def error_result(message)
        { success: false, error: message }
      end
    end
  end
end
