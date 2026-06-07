# frozen_string_literal: true

FactoryBot.define do
  # Ai::DataSource — a configured external data provider (REST/custom protocol).
  # UUIDv7 PKs are assigned by the DB default; the slug is auto-generated from
  # the name on create when not supplied.
  factory :ai_data_source, class: "Ai::DataSource" do
    account
    sequence(:name) { |n| "Data Source #{n}" }
    source_type { "custom" }
    protocol { "rest" }
    auth_scheme { "none" }
    api_base_url { "https://api.example.com" }
    is_active { true }
    requires_auth { false }
    priority_order { 1000 }
    health_status { "unknown" }
    auth_config { {} }
    rate_limits { {} }
    configuration { {} }
    default_parameters { {} }
    metadata { {} }
    capabilities { [] }

    trait :inactive do
      is_active { false }
    end

    trait :requires_auth do
      requires_auth { true }
      auth_scheme { "api_key" }
    end

    trait :bearer do
      auth_scheme { "bearer" }
      requires_auth { true }
    end

    trait :aws_sigv4 do
      auth_scheme { "aws_sigv4" }
      requires_auth { true }
      auth_config { { "region" => "us-east-1", "service" => "execute-api" } }
    end

    trait :hmac do
      auth_scheme { "hmac" }
      requires_auth { true }
    end

    trait :custom_protocol do
      protocol { "custom" }
    end

    trait :graphql_protocol do
      protocol { "graphql" }
    end
  end

  # Ai::DataSourceEndpoint — a single addressable operation on a data source,
  # carrying the request templates (path/query/body) and response format.
  factory :ai_data_source_endpoint, class: "Ai::DataSourceEndpoint" do
    association :data_source, factory: :ai_data_source
    sequence(:name) { |n| "Endpoint #{n}" }
    http_method { "GET" }
    path_template { "/v1/items" }
    response_format { "json" }
    expected_content_type { "application/json" }
    query_template { {} }
    body_template { {} }
    response_mapping { {} }
    response_schema { {} }
    metadata { {} }

    trait :post do
      http_method { "POST" }
      body_template { { "query" => "{q}" } }
    end

    trait :with_path_params do
      path_template { "/v1/stations/{station_id}/observations" }
    end

    trait :with_query_template do
      query_template { { "limit" => "{limit}", "format" => "json" } }
    end

    trait :json do
      response_format { "json" }
      expected_content_type { "application/json" }
    end

    trait :ndjson do
      response_format { "ndjson" }
      expected_content_type { "application/x-ndjson" }
    end

    trait :xml do
      response_format { "xml" }
      expected_content_type { "application/xml" }
    end

    trait :csv do
      response_format { "csv" }
      expected_content_type { "text/csv" }
    end

    # Pins a JSON records_path so the decoder digs into a nested array.
    trait :nested_records do
      response_mapping { { "records_path" => "data.items" } }
    end

    trait :monitorable do
      monitorable { true }
    end

    # A minimal JSON Schema so QueryService runs schema validation and records
    # provenance[:schema_valid] as true/false rather than nil (unknown).
    trait :with_schema do
      response_schema do
        {
          "type" => "array",
          "items" => {
            "type" => "object",
            "required" => %w[city],
            "properties" => {
              "city" => { "type" => "string" },
              "temp" => { "type" => %w[string number] }
            }
          }
        }
      end
    end
  end

  # Ai::DataSourceExpectation — a data-quality rule evaluated by QualityService
  # over an endpoint's canonical records. rule_type must be one of RULE_TYPES and
  # severity one of SEVERITIES; only ERROR-severity failures fail the batch.
  factory :ai_data_source_expectation, class: "Ai::DataSourceExpectation" do
    association :endpoint, factory: :ai_data_source_endpoint
    sequence(:name) { |n| "Expectation #{n}" }
    rule_type { "min_records" }
    severity { "warn" }
    config { { "min" => 1 } }
    is_active { true }

    trait :error do
      severity { "error" }
    end

    trait :inactive do
      is_active { false }
    end

    trait :required_fields do
      rule_type { "required_fields" }
      config { { "fields" => %w[id] } }
    end
  end

  # Ai::DataSourceCredential — secret material for a source (encrypted at rest
  # via Rails 8 `encrypts`). The first credential auto-sets itself default.
  factory :ai_data_source_credential, class: "Ai::DataSourceCredential" do
    account
    data_source { association(:ai_data_source, account: account) }
    sequence(:name) { |n| "Credential #{n}" }
    is_active { true }
    is_default { true }
    encrypted_api_key { "test-api-key" }

    trait :with_secret do
      encrypted_api_secret { "test-api-secret" }
    end

    trait :vaulted do
      vault_path { "secret/data/ai/data_sources/test" }
      migrated_to_vault_at { Time.current }
    end
  end
end
