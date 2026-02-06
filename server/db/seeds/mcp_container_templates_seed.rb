# frozen_string_literal: true

# Seed MCP server container templates (system-level, account_id: nil)
# These define sandboxed container configurations for running MCP servers

Rails.logger.info "[Seeds] Loading MCP Server Container Templates..."

MCP_SERVER_TEMPLATES = [
  {
    name: "Slack MCP Server",
    slug: "mcp-slack",
    description: "Containerized Slack MCP server for channel messaging, search, and user management.",
    image_name: "node",
    image_tag: "20-slim",
    entrypoint: "npx",
    command_args: ["-y", "@anthropic/mcp-server-slack"],
    memory_mb: 256,
    cpu_millicores: 500,
    timeout_seconds: 86400,
    allowed_egress_domains: ["slack.com", "*.slack.com", "api.slack.com", "files.slack.com"],
    vault_secret_paths: ["secret/mcp/slack"],
    environment_variables: { "NODE_ENV" => "production" },
    input_schema: {
      "SLACK_BOT_TOKEN" => { "type" => "string", "required" => true, "description" => "Slack Bot User OAuth Token" },
      "SLACK_TEAM_ID" => { "type" => "string", "required" => true, "description" => "Slack Workspace Team ID" }
    }
  },
  {
    name: "Notion MCP Server",
    slug: "mcp-notion",
    description: "Containerized Notion MCP server for page and database operations.",
    image_name: "node",
    image_tag: "20-slim",
    entrypoint: "npx",
    command_args: ["-y", "@notionhq/mcp-server"],
    memory_mb: 256,
    cpu_millicores: 500,
    timeout_seconds: 86400,
    allowed_egress_domains: ["api.notion.com", "*.notion.com"],
    vault_secret_paths: ["secret/mcp/notion"],
    environment_variables: { "NODE_ENV" => "production" },
    input_schema: {
      "NOTION_API_KEY" => { "type" => "string", "required" => true, "description" => "Notion Integration API Key" }
    }
  },
  {
    name: "Linear MCP Server",
    slug: "mcp-linear",
    description: "Containerized Linear MCP server for issue tracking and project management.",
    image_name: "node",
    image_tag: "20-slim",
    entrypoint: "npx",
    command_args: ["-y", "@anthropic/mcp-server-linear"],
    memory_mb: 256,
    cpu_millicores: 500,
    timeout_seconds: 86400,
    allowed_egress_domains: ["api.linear.app", "*.linear.app"],
    vault_secret_paths: ["secret/mcp/linear"],
    environment_variables: { "NODE_ENV" => "production" },
    input_schema: {
      "LINEAR_API_KEY" => { "type" => "string", "required" => true, "description" => "Linear API Key" }
    }
  },
  {
    name: "Figma MCP Server",
    slug: "mcp-figma",
    description: "Containerized Figma MCP server for design file access and component inspection.",
    image_name: "node",
    image_tag: "20-slim",
    entrypoint: "npx",
    command_args: ["-y", "figma-developer/figma-mcp"],
    memory_mb: 256,
    cpu_millicores: 500,
    timeout_seconds: 86400,
    allowed_egress_domains: ["api.figma.com", "*.figma.com"],
    vault_secret_paths: ["secret/mcp/figma"],
    environment_variables: { "NODE_ENV" => "production" },
    input_schema: {
      "FIGMA_ACCESS_TOKEN" => { "type" => "string", "required" => true, "description" => "Figma Personal Access Token" }
    }
  },
  {
    name: "HubSpot MCP Server",
    slug: "mcp-hubspot",
    description: "Containerized HubSpot MCP server for CRM contacts, deals, and marketing.",
    image_name: "node",
    image_tag: "20-slim",
    entrypoint: "npx",
    command_args: ["-y", "@anthropic/mcp-server-hubspot"],
    memory_mb: 256,
    cpu_millicores: 500,
    timeout_seconds: 86400,
    allowed_egress_domains: ["api.hubapi.com", "api.hubspot.com", "*.hubspot.com"],
    vault_secret_paths: ["secret/mcp/hubspot"],
    environment_variables: { "NODE_ENV" => "production" },
    input_schema: {
      "HUBSPOT_ACCESS_TOKEN" => { "type" => "string", "required" => true, "description" => "HubSpot Private App Access Token" }
    }
  },
  {
    name: "Atlassian MCP Server",
    slug: "mcp-atlassian",
    description: "Containerized Atlassian MCP server for Jira issues, Confluence pages, and project management.",
    image_name: "node",
    image_tag: "20-slim",
    entrypoint: "npx",
    command_args: ["-y", "@anthropic/mcp-server-atlassian"],
    memory_mb: 256,
    cpu_millicores: 500,
    timeout_seconds: 86400,
    allowed_egress_domains: ["*.atlassian.net", "*.atlassian.com", "*.jira.com"],
    vault_secret_paths: ["secret/mcp/atlassian"],
    environment_variables: { "NODE_ENV" => "production" },
    input_schema: {
      "ATLASSIAN_API_TOKEN" => { "type" => "string", "required" => true, "description" => "Atlassian API Token" },
      "ATLASSIAN_URL" => { "type" => "string", "required" => true, "description" => "Atlassian instance URL (e.g., https://yourteam.atlassian.net)" }
    }
  },
  {
    name: "Asana MCP Server",
    slug: "mcp-asana",
    description: "Containerized Asana MCP server for task and project management.",
    image_name: "node",
    image_tag: "20-slim",
    entrypoint: "npx",
    command_args: ["-y", "@anthropic/mcp-server-asana"],
    memory_mb: 256,
    cpu_millicores: 500,
    timeout_seconds: 86400,
    allowed_egress_domains: ["app.asana.com", "*.asana.com"],
    vault_secret_paths: ["secret/mcp/asana"],
    environment_variables: { "NODE_ENV" => "production" },
    input_schema: {
      "ASANA_ACCESS_TOKEN" => { "type" => "string", "required" => true, "description" => "Asana Personal Access Token" }
    }
  },
  {
    name: "Intercom MCP Server",
    slug: "mcp-intercom",
    description: "Containerized Intercom MCP server for customer messaging and support.",
    image_name: "node",
    image_tag: "20-slim",
    entrypoint: "npx",
    command_args: ["-y", "@anthropic/mcp-server-intercom"],
    memory_mb: 256,
    cpu_millicores: 500,
    timeout_seconds: 86400,
    allowed_egress_domains: ["api.intercom.io", "*.intercom.com"],
    vault_secret_paths: ["secret/mcp/intercom"],
    environment_variables: { "NODE_ENV" => "production" },
    input_schema: {
      "INTERCOM_ACCESS_TOKEN" => { "type" => "string", "required" => true, "description" => "Intercom Access Token" }
    }
  },
  {
    name: "Snowflake MCP Server",
    slug: "mcp-snowflake",
    description: "Containerized Snowflake MCP server for data warehouse queries and analytics.",
    image_name: "node",
    image_tag: "20-slim",
    entrypoint: "npx",
    command_args: ["-y", "@anthropic/mcp-server-snowflake"],
    memory_mb: 512,
    cpu_millicores: 500,
    timeout_seconds: 86400,
    allowed_egress_domains: ["*.snowflakecomputing.com"],
    vault_secret_paths: ["secret/mcp/snowflake"],
    environment_variables: { "NODE_ENV" => "production" },
    input_schema: {
      "SNOWFLAKE_ACCOUNT" => { "type" => "string", "required" => true, "description" => "Snowflake Account Identifier" },
      "SNOWFLAKE_USER" => { "type" => "string", "required" => true, "description" => "Snowflake Username" },
      "SNOWFLAKE_PASSWORD" => { "type" => "string", "required" => true, "description" => "Snowflake Password" }
    }
  },
  {
    name: "BigQuery MCP Server",
    slug: "mcp-bigquery",
    description: "Containerized BigQuery MCP server for Google Cloud data warehouse access.",
    image_name: "node",
    image_tag: "20-slim",
    entrypoint: "npx",
    command_args: ["-y", "@anthropic/mcp-server-bigquery"],
    memory_mb: 512,
    cpu_millicores: 500,
    timeout_seconds: 86400,
    allowed_egress_domains: ["*.googleapis.com", "*.google.com", "accounts.google.com"],
    vault_secret_paths: ["secret/mcp/bigquery"],
    environment_variables: { "NODE_ENV" => "production" },
    input_schema: {
      "GOOGLE_APPLICATION_CREDENTIALS" => { "type" => "string", "required" => true, "description" => "Path to Google Service Account JSON key" }
    }
  },
  {
    name: "MS365 MCP Server",
    slug: "mcp-ms365",
    description: "Containerized Microsoft 365 MCP server for Outlook, Teams, and OneDrive access.",
    image_name: "node",
    image_tag: "20-slim",
    entrypoint: "npx",
    command_args: ["-y", "@anthropic/mcp-server-microsoft365"],
    memory_mb: 256,
    cpu_millicores: 500,
    timeout_seconds: 86400,
    allowed_egress_domains: ["*.microsoft.com", "*.office.com", "graph.microsoft.com", "login.microsoftonline.com"],
    vault_secret_paths: ["secret/mcp/ms365"],
    environment_variables: { "NODE_ENV" => "production" },
    input_schema: {
      "MS365_CLIENT_ID" => { "type" => "string", "required" => true, "description" => "Azure AD Application Client ID" },
      "MS365_CLIENT_SECRET" => { "type" => "string", "required" => true, "description" => "Azure AD Application Client Secret" }
    }
  },
  {
    name: "Box MCP Server",
    slug: "mcp-box",
    description: "Containerized Box MCP server for cloud file storage and collaboration.",
    image_name: "node",
    image_tag: "20-slim",
    entrypoint: "npx",
    command_args: ["-y", "@anthropic/mcp-server-box"],
    memory_mb: 256,
    cpu_millicores: 500,
    timeout_seconds: 86400,
    allowed_egress_domains: ["api.box.com", "*.box.com", "upload.box.com"],
    vault_secret_paths: ["secret/mcp/box"],
    environment_variables: { "NODE_ENV" => "production" },
    input_schema: {
      "BOX_CLIENT_ID" => { "type" => "string", "required" => true, "description" => "Box Application Client ID" },
      "BOX_CLIENT_SECRET" => { "type" => "string", "required" => true, "description" => "Box Application Client Secret" }
    }
  },
  {
    name: "Amplitude MCP Server",
    slug: "mcp-amplitude",
    description: "Containerized Amplitude MCP server for product analytics and user behavior data.",
    image_name: "node",
    image_tag: "20-slim",
    entrypoint: "npx",
    command_args: ["-y", "amplitude/mcp-server"],
    memory_mb: 256,
    cpu_millicores: 500,
    timeout_seconds: 86400,
    allowed_egress_domains: ["*.amplitude.com", "api.amplitude.com"],
    vault_secret_paths: ["secret/mcp/amplitude"],
    environment_variables: { "NODE_ENV" => "production" },
    input_schema: {
      "AMPLITUDE_API_KEY" => { "type" => "string", "required" => true, "description" => "Amplitude API Key" }
    }
  },
  {
    name: "Canva MCP Server",
    slug: "mcp-canva",
    description: "Containerized Canva MCP server for design creation and template management.",
    image_name: "node",
    image_tag: "20-slim",
    entrypoint: "npx",
    command_args: ["-y", "canva/mcp-server-canva"],
    memory_mb: 256,
    cpu_millicores: 500,
    timeout_seconds: 86400,
    allowed_egress_domains: ["api.canva.com", "*.canva.com"],
    vault_secret_paths: ["secret/mcp/canva"],
    environment_variables: { "NODE_ENV" => "production" },
    input_schema: {
      "CANVA_ACCESS_TOKEN" => { "type" => "string", "required" => true, "description" => "Canva API Access Token" }
    }
  },
  {
    name: "Databricks MCP Server",
    slug: "mcp-databricks",
    description: "Containerized Databricks MCP server for lakehouse analytics, SQL warehouses, and ML.",
    image_name: "python",
    image_tag: "3.12-slim",
    entrypoint: "uvx",
    command_args: ["databricks-mcp-server"],
    memory_mb: 512,
    cpu_millicores: 500,
    timeout_seconds: 86400,
    allowed_egress_domains: ["*.databricks.com", "*.cloud.databricks.com", "*.azuredatabricks.net"],
    vault_secret_paths: ["secret/mcp/databricks"],
    environment_variables: { "PYTHONUNBUFFERED" => "1" },
    input_schema: {
      "DATABRICKS_HOST" => { "type" => "string", "required" => true, "description" => "Databricks workspace URL" },
      "DATABRICKS_TOKEN" => { "type" => "string", "required" => true, "description" => "Databricks Personal Access Token" }
    }
  }
].freeze

template_count = 0
MCP_SERVER_TEMPLATES.each do |data|
  template = Devops::ContainerTemplate.find_or_initialize_by(slug: data[:slug])
  template.assign_attributes(
    account_id: nil,
    name: data[:name],
    description: data[:description],
    image_name: data[:image_name],
    image_tag: data[:image_tag],
    entrypoint: data[:entrypoint],
    command_args: data[:command_args],
    category: "mcp-server",
    visibility: "public",
    status: "active",
    memory_mb: data[:memory_mb],
    cpu_millicores: data[:cpu_millicores],
    timeout_seconds: data[:timeout_seconds],
    sandbox_mode: true,
    network_access: true,
    read_only_root: true,
    privileged: false,
    security_options: {
      "read_only_root" => true,
      "cap_drop" => ["ALL"],
      "no_new_privileges" => true
    },
    allowed_egress_domains: data[:allowed_egress_domains],
    vault_secret_paths: data[:vault_secret_paths],
    environment_variables: data[:environment_variables],
    input_schema: data[:input_schema],
    output_schema: {},
    labels: { "runner" => "powernode-mcp", "type" => "mcp-server" }
  )
  template.save!
  template_count += 1
end

Rails.logger.info "[Seeds] MCP Container Templates: #{template_count} created/updated"
