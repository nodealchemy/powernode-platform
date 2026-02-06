# frozen_string_literal: true

module Devops
  module StepHandlers
    class SbomGenerateHandler < Base
      SUPPORTED_FORMATS = %w[spdx cyclonedx].freeze
      DEFAULT_FORMAT = "cyclonedx"
      DEFAULT_TOOL = "syft"

      def execute(config:, context:, previous_outputs: {})
        logs = []
        logs << log_info("Starting SBOM generation")

        workspace = previous_outputs.dig("checkout", :workspace) || config["workspace"]
        raise StandardError, "No workspace available for SBOM generation" unless workspace

        format = config["format"] || DEFAULT_FORMAT
        tool = config["tool"] || DEFAULT_TOOL
        output_file = config["output_file"] || "sbom.#{format == 'spdx' ? 'spdx.json' : 'json'}"
        output_path = File.join(workspace, output_file)

        unless SUPPORTED_FORMATS.include?(format)
          raise StandardError, "Unsupported SBOM format: #{format}. Supported: #{SUPPORTED_FORMATS.join(', ')}"
        end

        logs << log_info("Generating SBOM", tool: tool, format: format, output: output_file)

        command = build_command(tool: tool, format: format, workspace: workspace, output_path: output_path, config: config)
        result = execute_shell_command(command, working_directory: workspace, timeout: config["timeout"]&.to_i || 600)

        unless result[:success]
          logs << log_error("SBOM generation failed", error: result[:error])
          raise StandardError, "SBOM generation failed: #{result[:error]}"
        end

        logs << log_info("SBOM generated successfully", output: output_file)

        sbom_metadata = parse_sbom_metadata(output_path)
        logs << log_info("SBOM contains #{sbom_metadata[:component_count]} components")

        {
          outputs: {
            sbom_path: output_path,
            sbom_format: format,
            tool: tool,
            component_count: sbom_metadata[:component_count],
            generated_at: Time.current.iso8601
          },
          logs: logs.join("\n")
        }
      end

      private

      def build_command(tool:, format:, workspace:, output_path:, config:)
        case tool
        when "syft"
          cmd = "syft #{workspace}"
          cmd += " -o #{format == 'spdx' ? 'spdx-json' : 'cyclonedx-json'}"
          cmd += " --file #{output_path}"
          cmd += " --exclude #{config['exclude']}" if config["exclude"]
          cmd
        when "cdxgen"
          cmd = "cdxgen -o #{output_path}"
          cmd += " --spec-version #{config['spec_version'] || '1.5'}"
          cmd += " -t #{config['project_type']}" if config["project_type"]
          cmd += " #{workspace}"
          cmd
        else
          raise StandardError, "Unsupported SBOM tool: #{tool}"
        end
      end

      def parse_sbom_metadata(path)
        return { component_count: 0 } unless File.exist?(path)

        data = JSON.parse(File.read(path))

        component_count = if data["components"]
                            data["components"].size
                          elsif data["packages"]
                            data["packages"].size
                          else
                            0
                          end

        { component_count: component_count }
      rescue JSON::ParserError, Errno::ENOENT
        { component_count: 0 }
      end
    end
  end
end
