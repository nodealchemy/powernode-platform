# frozen_string_literal: true

module Ai
  module McpApps
    class RendererService
      include Ai::Concerns::AccountScoped

      # Default CSP directives for sandboxed MCP apps
      DEFAULT_CSP = {
        "default-src" => "'self'",
        "script-src" => "'none'",
        "style-src" => "'unsafe-inline'",
        "img-src" => "'self' data:",
        "connect-src" => "'none'",
        "frame-src" => "'none'"
      }.freeze

      # Default iframe sandbox attributes
      DEFAULT_SANDBOX = {
        "allow-scripts" => false,
        "allow-same-origin" => false,
        "allow-forms" => true,
        "allow-popups" => false,
        "allow-modals" => false
      }.freeze

      # Dangerous HTML tags to strip
      DANGEROUS_TAGS = %w[script iframe object embed applet].freeze

      # ==========================================
      # CRUD Operations
      # ==========================================

      def list_apps(filters = {})
        scope = Ai::McpApp.where(account_id: @account.id)
        scope = scope.where(status: filters[:status]) if filters[:status].present?
        scope = scope.by_type(filters[:app_type]) if filters[:app_type].present?
        scope = scope.where("name ILIKE ?", "%#{filters[:search]}%") if filters[:search].present?
        scope.recent
      end

      def get_app(app_id)
        Ai::McpApp.where(account_id: @account.id).find(app_id)
      end

      def create_app(params)
        Rails.logger.info "[MCP Apps] Creating app: #{params[:name]}"

        app = Ai::McpApp.new(
          account: @account,
          name: params[:name],
          description: params[:description],
          app_type: params[:app_type] || "custom",
          status: params[:status] || "draft",
          html_content: sanitize_html(params[:html_content]),
          csp_policy: params[:csp_policy] || {},
          sandbox_config: params[:sandbox_config] || {},
          input_schema: params[:input_schema] || {},
          output_schema: params[:output_schema] || {},
          metadata: params[:metadata] || {},
          version: params[:version] || "1.0.0",
          created_by_id: params[:created_by_id]
        )

        app.save!
        Rails.logger.info "[MCP Apps] App created: #{app.id}"
        app
      end

      def update_app(app_id, params)
        app = get_app(app_id)

        update_attrs = {}
        update_attrs[:name] = params[:name] if params.key?(:name)
        update_attrs[:description] = params[:description] if params.key?(:description)
        update_attrs[:app_type] = params[:app_type] if params.key?(:app_type)
        update_attrs[:status] = params[:status] if params.key?(:status)
        update_attrs[:html_content] = sanitize_html(params[:html_content]) if params.key?(:html_content)
        update_attrs[:csp_policy] = params[:csp_policy] if params.key?(:csp_policy)
        update_attrs[:sandbox_config] = params[:sandbox_config] if params.key?(:sandbox_config)
        update_attrs[:input_schema] = params[:input_schema] if params.key?(:input_schema)
        update_attrs[:output_schema] = params[:output_schema] if params.key?(:output_schema)
        update_attrs[:metadata] = params[:metadata] if params.key?(:metadata)
        update_attrs[:version] = params[:version] if params.key?(:version)

        app.update!(update_attrs)
        Rails.logger.info "[MCP Apps] App updated: #{app.id}"
        app
      end

      def delete_app(app_id)
        app = get_app(app_id)
        app.destroy!
        Rails.logger.info "[MCP Apps] App deleted: #{app_id}"
        true
      end

      # ==========================================
      # Rendering
      # ==========================================

      def render_app(mcp_app:, context: {}, session: nil)
        Rails.logger.info "[MCP Apps] Rendering app: #{mcp_app.id}"

        instance = Ai::McpAppInstance.create!(
          mcp_app: mcp_app,
          account: @account,
          session: session,
          status: "running",
          input_data: context,
          started_at: Time.current
        )

        html = prepare_html(mcp_app, context)
        csp_header = build_csp_header(mcp_app.csp_policy)

        {
          html: html,
          instance: instance,
          csp_headers: csp_header,
          sandbox_attrs: build_sandbox_attrs(mcp_app.sandbox_config)
        }
      end

      # ==========================================
      # Input Processing
      # ==========================================

      def process_user_input(instance_id:, input_data:)
        instance = Ai::McpAppInstance
          .where(account_id: @account.id)
          .find(instance_id)

        mcp_app = instance.mcp_app

        # Validate input against schema if defined
        if mcp_app.input_schema.present?
          validation_result = validate_input(input_data, mcp_app.input_schema)
          unless validation_result[:valid]
            return {
              response: { error: "Invalid input", details: validation_result[:errors] },
              state_update: nil
            }
          end
        end

        # Update instance with input and compute output
        instance.update!(
          input_data: input_data,
          state: (instance.state || {}).merge("last_input" => input_data)
        )

        state_update = { "last_input_at" => Time.current.iso8601 }
        output = { received: true, input_data: input_data }

        instance.complete!(output)

        {
          response: output,
          state_update: state_update
        }
      end

      private

      # ==========================================
      # HTML Processing
      # ==========================================

      def prepare_html(mcp_app, context)
        html = mcp_app.html_content || ""

        # Template variable interpolation (simple {{variable}} replacement)
        context.each do |key, value|
          html = html.gsub("{{#{key}}}", sanitize_value(value.to_s))
        end

        sanitize_html(html)
      end

      def sanitize_html(html)
        return "" if html.blank?

        sanitized = html.dup
        DANGEROUS_TAGS.each do |tag|
          sanitized.gsub!(/<#{tag}[^>]*>.*?<\/#{tag}>/mi, "")
          sanitized.gsub!(/<#{tag}[^>]*\/?>/mi, "")
        end

        # Remove on* event handlers
        sanitized.gsub!(/\s+on\w+\s*=\s*["'][^"']*["']/i, "")
        sanitized.gsub!(/\s+on\w+\s*=\s*[^\s>]*/i, "")

        sanitized
      end

      def sanitize_value(value)
        value.to_s
          .gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub(">", "&gt;")
          .gsub('"', "&quot;")
          .gsub("'", "&#x27;")
      end

      # ==========================================
      # CSP & Sandbox
      # ==========================================

      def build_csp_header(csp_policy)
        merged = DEFAULT_CSP.merge(csp_policy || {})

        merged.map { |directive, value| "#{directive} #{value}" }.join("; ")
      end

      def build_sandbox_attrs(sandbox_config)
        merged = DEFAULT_SANDBOX.merge(sandbox_config || {})

        attrs = []
        merged.each do |attr, enabled|
          attrs << attr if enabled
        end

        attrs.join(" ")
      end

      # ==========================================
      # Input Validation
      # ==========================================

      def validate_input(input, schema)
        errors = []

        # Basic JSON Schema-like validation
        if schema["required"].is_a?(Array)
          schema["required"].each do |field|
            errors << "Missing required field: #{field}" unless input.key?(field) || input.key?(field.to_sym)
          end
        end

        if schema["properties"].is_a?(Hash)
          schema["properties"].each do |field, field_schema|
            value = input[field] || input[field.to_sym]
            next if value.nil?

            expected_type = field_schema["type"]
            if expected_type.present? && !type_matches?(value, expected_type)
              errors << "Field '#{field}' expected type #{expected_type}, got #{value.class.name.downcase}"
            end
          end
        end

        { valid: errors.empty?, errors: errors }
      end

      def type_matches?(value, expected_type)
        case expected_type
        when "string" then value.is_a?(String)
        when "number", "integer" then value.is_a?(Numeric)
        when "boolean" then value.is_a?(TrueClass) || value.is_a?(FalseClass)
        when "array" then value.is_a?(Array)
        when "object" then value.is_a?(Hash)
        else true
        end
      end
    end
  end
end
