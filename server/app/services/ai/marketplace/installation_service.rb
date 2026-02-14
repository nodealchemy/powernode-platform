# frozen_string_literal: true

module Ai
  module Marketplace
    # Service for managing template installations and subscriptions
    #
    # Provides installation management including:
    # - Template installation with workflow creation
    # - Installation tracking and history
    # - Update checking and application
    # - Uninstallation
    # - Rating management
    #
    # Usage:
    #   service = Ai::Marketplace::InstallationService.new(account: current_account, user: current_user)
    #   result = service.install(template_id: 'uuid', custom_configuration: {})
    #
    class InstallationService
      include InstallWorkflow
      include UpdateAndUninstall
      include RatingAndSerialization

      attr_reader :account, :user

      class InstallationError < StandardError; end

      def initialize(account:, user:)
        @account = account
        @user = user
      end

      private

      def error_result(message)
        { success: false, error: message }
      end
    end
  end
end
