# frozen_string_literal: true

module Ai
  module DataSources
    # Thin orchestrator the controller uses to run a governed external fetch for a
    # data-source endpoint. Keeps the QueryService wiring (agent/user context) out
    # of the controller so DataSourcesController stays under the size budget.
    #
    # Returns the QueryService FetchEnvelope verbatim — the controller renders it
    # through render_success/render_error based on the envelope :success flag.
    class EndpointQueryRunner
      def initialize(data_source:, endpoint:, params: {}, agent: nil, user: nil)
        @data_source = data_source
        @endpoint = endpoint
        @params = (params || {}).to_h
        @agent = agent
        @user = user
      end

      # @return [Hash] FetchEnvelope (see Ai::DataSources::QueryService)
      def call
        Ai::DataSources::QueryService.new(
          data_source: @data_source,
          endpoint: @endpoint,
          params: @params,
          agent: @agent,
          user: @user
        ).call
      end
    end
  end
end
