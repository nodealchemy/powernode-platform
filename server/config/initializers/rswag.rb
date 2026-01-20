# frozen_string_literal: true

Rswag::Api.configure do |config|
  # Specify a root folder where Swagger JSON files are located.
  # This is used by the Swagger middleware to serve requests for API descriptions.
  # NOTE: If you're using rswag-specs to generate Swagger, you'll need to ensure
  # that it's configured to generate files in the same folder.
  config.openapi_root = Rails.root.join("swagger").to_s
end

Rswag::Ui.configure do |config|
  # List the Swagger endpoints to be served by swagger-ui.
  # The openapi_endpoint function takes two arguments:
  #   1. A path to the Swagger JSON file (relative to openapi_root configured above)
  #   2. A title for the endpoint (displayed in the dropdown menu)
  config.openapi_endpoint "/api-docs/v1/swagger.yaml", "Powernode API V1"

  # Add Basic Auth in case the openapi spec is configured with basic auth
  # config.basic_auth_enabled = true
  # config.basic_auth_credentials "username", "password"

  # Optional configuration to customize the UI appearance
  config.config_object["docExpansion"] = "none"
  config.config_object["filter"] = true
  config.config_object["displayRequestDuration"] = true
  config.config_object["defaultModelsExpandDepth"] = 1
end
