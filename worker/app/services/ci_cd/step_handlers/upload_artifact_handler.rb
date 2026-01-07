# frozen_string_literal: true

module CiCd
  module StepHandlers
    # Handles artifact upload steps
    class UploadArtifactHandler < Base
      # Execute upload artifact step
      # @param config [Hash] Step configuration
      # @param context [Hash] Execution context
      # @param previous_outputs [Hash] Outputs from previous steps
      # @return [Hash] Result with :outputs and :logs keys
      def execute(config:, context:, previous_outputs: {})
        logs = []
        logs << log_info("Starting upload artifact step")

        workspace = previous_outputs.dig("checkout", :workspace) || Dir.pwd
        artifact_name = config["artifact_name"] || "build-artifacts"
        path_pattern = config["path"] || "."
        retention_days = config["retention_days"] || 30

        # Resolve the path pattern
        artifact_paths = resolve_paths(workspace, path_pattern)

        if artifact_paths.empty?
          logs << log_warn("No files found matching pattern", pattern: path_pattern)

          return {
            outputs: {
              artifact_name: artifact_name,
              files_uploaded: 0
            },
            logs: logs.join("\n")
          }
        end

        logs << log_info("Found files to upload", count: artifact_paths.count)

        # Create artifact archive
        archive_path = create_archive(workspace, artifact_paths, artifact_name)

        logs << log_info("Created archive", size: File.size(archive_path))

        # Upload to storage via API
        upload_result = upload_artifact(
          archive_path: archive_path,
          artifact_name: artifact_name,
          pipeline_run_id: context.dig(:pipeline_run, :id),
          retention_days: retention_days
        )

        logs << log_info("Artifact uploaded",
                         artifact_id: upload_result["id"],
                         size: upload_result["size"])

        # Clean up temp archive
        FileUtils.rm_f(archive_path)

        {
          outputs: {
            artifact_id: upload_result["id"],
            artifact_name: artifact_name,
            artifact_url: upload_result["download_url"],
            files_uploaded: artifact_paths.count,
            size_bytes: upload_result["size"]
          },
          logs: logs.join("\n")
        }
      end

      private

      def resolve_paths(workspace, pattern)
        # Handle glob patterns
        if pattern.include?("*")
          full_pattern = File.join(workspace, pattern)
          Dir.glob(full_pattern)
        else
          full_path = File.join(workspace, pattern)
          if File.exist?(full_path)
            if File.directory?(full_path)
              # Get all files in directory
              Dir.glob(File.join(full_path, "**", "*")).reject { |p| File.directory?(p) }
            else
              [full_path]
            end
          else
            []
          end
        end
      end

      def create_archive(workspace, paths, artifact_name)
        archive_path = File.join(Dir.tmpdir, "#{artifact_name}-#{SecureRandom.hex(8)}.tar.gz")

        # Create relative paths for the archive
        relative_paths = paths.map do |path|
          Pathname.new(path).relative_path_from(Pathname.new(workspace)).to_s
        end

        # Create tar.gz archive
        result = execute_shell_command(
          "tar -czf #{archive_path} #{relative_paths.map { |p| "'#{p}'" }.join(' ')}",
          working_directory: workspace
        )

        unless result[:success]
          raise StandardError, "Failed to create archive: #{result[:error]}"
        end

        archive_path
      end

      def upload_artifact(archive_path:, artifact_name:, pipeline_run_id:, retention_days:)
        # Read file and encode
        file_content = File.read(archive_path)
        file_size = File.size(archive_path)

        response = api_client.post("/api/v1/internal/ci_cd/artifacts", {
          artifact: {
            name: artifact_name,
            pipeline_run_id: pipeline_run_id,
            retention_days: retention_days,
            content_type: "application/gzip",
            size: file_size,
            content_base64: Base64.strict_encode64(file_content)
          }
        })

        response.dig("data", "artifact") || response.dig("data")
      end
    end
  end
end
