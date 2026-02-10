# frozen_string_literal: true

module Ai
  module Providers
    module Sync
      module Generic
        extend ActiveSupport::Concern

        class_methods do
          private

          def sync_generic_models(provider)
            # Generic fallback for unknown providers
            provider.update(supported_models: [
              {
                "name" => "Default Model",
                "id" => "default",
                "context_length" => 4096,
                "description" => "Default model for #{provider.name}"
              }
            ])
          end
        end
      end
    end
  end
end
