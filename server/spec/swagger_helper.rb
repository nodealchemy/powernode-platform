# frozen_string_literal: true

require "rails_helper"

RSpec.configure do |config|
  # Specify a root folder where Swagger JSON files are generated
  # NOTE: If you're using the rswag-api to serve API descriptions, you'll need
  # to ensure that it's configured to serve Swagger from the same folder
  config.openapi_root = Rails.root.join("swagger").to_s

  # Define one or more Swagger documents and provide global metadata for each one
  # When you run the 'rswag:specs:swaggerize' rake task, the complete Swagger will
  # be generated at the provided relative path under openapi_root
  config.openapi_specs = {
    "v1/swagger.yaml" => {
      openapi: "3.0.1",
      info: {
        title: "Powernode API",
        version: "v1",
        description: "API documentation for the Powernode subscription management platform.",
        contact: {
          name: "Powernode Support",
          email: "support@powernode.io"
        },
        license: {
          name: "Proprietary"
        }
      },
      paths: {},
      servers: [
        {
          url: "{protocol}://{host}",
          variables: {
            protocol: {
              default: Rails.env.production? ? "https" : "http"
            },
            host: {
              default: Rails.env.production? ? "api.powernode.io" : "localhost:3000"
            }
          }
        }
      ],
      components: {
        securitySchemes: {
          bearer_auth: {
            type: :http,
            scheme: :bearer,
            bearerFormat: "JWT",
            description: "JWT token authentication. Obtain a token via POST /api/v1/auth/login"
          },
          api_key: {
            type: :apiKey,
            name: "X-API-Key",
            in: :header,
            description: "API key authentication for external integrations"
          }
        },
        schemas: {
          Error: {
            type: :object,
            properties: {
              success: { type: :boolean, example: false },
              error: { type: :string, example: "Error message" },
              code: { type: :string, example: "ERROR_CODE" },
              details: { type: :object }
            },
            required: %w[success error]
          },
          Pagination: {
            type: :object,
            properties: {
              current_page: { type: :integer, example: 1 },
              per_page: { type: :integer, example: 25 },
              total_pages: { type: :integer, example: 10 },
              total_count: { type: :integer, example: 250 }
            }
          },
          Reseller: {
            type: :object,
            properties: {
              id: { type: :string, format: :uuid },
              company_name: { type: :string },
              referral_code: { type: :string },
              tier: { type: :string, enum: %w[bronze silver gold platinum] },
              status: { type: :string, enum: %w[pending approved active suspended terminated] },
              commission_percentage: { type: :number },
              lifetime_earnings: { type: :number },
              pending_payout: { type: :number },
              total_referrals: { type: :integer },
              active_referrals: { type: :integer },
              created_at: { type: :string, format: "date-time" },
              activated_at: { type: :string, format: "date-time", nullable: true }
            }
          },
          UsageEvent: {
            type: :object,
            properties: {
              id: { type: :string, format: :uuid },
              event_id: { type: :string },
              meter_slug: { type: :string },
              quantity: { type: :number },
              timestamp: { type: :string, format: "date-time" },
              source: { type: :string, enum: %w[api webhook system import internal] },
              is_processed: { type: :boolean },
              properties: { type: :object }
            }
          },
          UsageMeter: {
            type: :object,
            properties: {
              id: { type: :string, format: :uuid },
              name: { type: :string },
              slug: { type: :string },
              unit_name: { type: :string },
              aggregation_type: { type: :string, enum: %w[sum max count last average] },
              billing_model: { type: :string, enum: %w[tiered volume package flat per_unit] },
              reset_period: { type: :string, enum: %w[never daily weekly monthly yearly billing_period] },
              is_active: { type: :boolean },
              is_billable: { type: :boolean }
            }
          },
          AnalyticsTier: {
            type: :object,
            properties: {
              id: { type: :string, format: :uuid },
              name: { type: :string },
              slug: { type: :string, enum: %w[free starter pro enterprise] },
              monthly_price: { type: :number },
              retention_days: { type: :integer },
              cohort_months: { type: :integer },
              csv_export: { type: :boolean },
              api_access: { type: :boolean },
              forecasting: { type: :boolean },
              custom_reports: { type: :boolean },
              api_calls_per_day: { type: :integer }
            }
          },
          WebhookEndpoint: {
            type: :object,
            properties: {
              id: { type: :string, format: :uuid },
              url: { type: :string, format: :uri },
              status: { type: :string, enum: %w[active inactive] },
              tier: { type: :string, enum: %w[free pro enterprise] },
              event_types: { type: :array, items: { type: :string } },
              success_count: { type: :integer },
              failure_count: { type: :integer },
              daily_count: { type: :integer },
              daily_limit: { type: :integer }
            }
          }
        }
      },
      security: [
        { bearer_auth: [] }
      ],
      tags: [
        { name: "Authentication", description: "User authentication and session management" },
        { name: "Accounts", description: "Account management operations" },
        { name: "Users", description: "User management operations" },
        { name: "Subscriptions", description: "Subscription lifecycle management" },
        { name: "Billing", description: "Billing and payment operations" },
        { name: "Invoices", description: "Invoice management" },
        { name: "Plans", description: "Subscription plan management" },
        { name: "Resellers", description: "Reseller program and partner management" },
        { name: "Usage", description: "Usage tracking and metering" },
        { name: "Analytics", description: "Revenue analytics and reporting" },
        { name: "Analytics Tiers", description: "Analytics tier management" },
        { name: "Webhooks", description: "Webhook endpoint management" },
        { name: "API Keys", description: "API key management" },
        { name: "AI", description: "AI agent and workflow operations" }
      ]
    }
  }

  # Specify the format of the output Swagger file when running 'rswag:specs:swaggerize'.
  # The openapi_format can be either :json or :yaml. Defaults to :json.
  config.openapi_format = :yaml
end
