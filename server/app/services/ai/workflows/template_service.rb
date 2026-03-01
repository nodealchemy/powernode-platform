# frozen_string_literal: true

module Ai
  module Workflows
    # Service for managing workflow templates - creation, conversion, and instantiation
    #
    # Consolidates template-related logic from WorkflowsController and MarketplaceController:
    # - Converting workflows to templates
    # - Creating workflows from templates
    # - Template configuration and customization
    # - Template publishing and versioning
    #
    # Usage:
    #   service = Ai::Workflows::TemplateService.new(account: current_account, user: current_user)
    #   result = service.create_from_workflow(workflow, name: "My Template", is_public: true)
    #
    class TemplateService
      include TemplateCreation
      include TemplateInstantiation
      include TemplatePublishing

      attr_reader :account, :user

      # Initialize the service
      # @param account [Account] The account context
      # @param user [User] The user performing operations
      def initialize(account:, user:)
        @account = account
        @user = user
      end

      # Result wrapper for service operations
      class Result
        attr_reader :success, :data

        def initialize(success:, data: {})
          @success = success
          @data = data
        end

        def self.success(data = {})
          new(success: true, data: data)
        end

        def self.failure(data = {})
          new(success: false, data: data)
        end

        def success?
          @success
        end

        def failure?
          !@success
        end

        def method_missing(method, *args, &block)
          if data.key?(method)
            data[method]
          else
            super
          end
        end

        def respond_to_missing?(method, include_private = false)
          data.key?(method) || super
        end
      end

      # Custom error class
      class OwnershipError < StandardError; end
    end
  end
end
