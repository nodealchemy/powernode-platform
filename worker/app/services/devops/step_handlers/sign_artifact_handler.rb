# frozen_string_literal: true

module Devops
  module StepHandlers
    class SignArtifactHandler < Base
      SUPPORTED_SIGNERS = %w[cosign gpg].freeze
      DEFAULT_SIGNER = "cosign"

      def execute(config:, context:, previous_outputs: {})
        logs = []
        logs << log_info("Starting artifact signing")

        artifact_path = resolve_artifact_path(config, previous_outputs)
        raise StandardError, "No artifact path specified or available" unless artifact_path

        signer = config["signer"] || DEFAULT_SIGNER
        unless SUPPORTED_SIGNERS.include?(signer)
          raise StandardError, "Unsupported signer: #{signer}. Supported: #{SUPPORTED_SIGNERS.join(', ')}"
        end

        logs << log_info("Signing artifact", path: artifact_path, signer: signer)

        result = case signer
                 when "cosign"
                   sign_with_cosign(artifact_path, config, logs)
                 when "gpg"
                   sign_with_gpg(artifact_path, config, logs)
                 end

        unless result[:success]
          logs << log_error("Artifact signing failed", error: result[:error])
          raise StandardError, "Artifact signing failed: #{result[:error]}"
        end

        logs << log_info("Artifact signed successfully")

        {
          outputs: {
            artifact_path: artifact_path,
            signature_path: result[:signature_path],
            signer: signer,
            signed_at: Time.current.iso8601,
            verification_command: result[:verification_command]
          },
          logs: logs.join("\n")
        }
      end

      private

      def resolve_artifact_path(config, previous_outputs)
        config["artifact_path"] ||
          previous_outputs.dig("build", :artifact_path) ||
          previous_outputs.dig("upload_artifact", :uploaded_path)
      end

      def sign_with_cosign(artifact_path, config, logs)
        keyless = config["keyless"] != false

        cmd = if keyless
                logs << log_info("Using keyless signing (Sigstore/Fulcio)")
                "COSIGN_EXPERIMENTAL=1 cosign sign --yes #{artifact_path}"
              else
                key_path = config["key_path"]
                raise StandardError, "cosign key_path required for keyed signing" unless key_path

                "cosign sign --key #{key_path} #{artifact_path}"
              end

        cmd += " --annotations #{format_annotations(config['annotations'])}" if config["annotations"]

        result = execute_shell_command(cmd, timeout: config["timeout"]&.to_i || 300)

        {
          success: result[:success],
          error: result[:error],
          signature_path: "#{artifact_path}.sig",
          verification_command: keyless ? "cosign verify #{artifact_path}" : "cosign verify --key #{config['key_path']} #{artifact_path}"
        }
      end

      def sign_with_gpg(artifact_path, config, logs)
        key_id = config["gpg_key_id"]
        raise StandardError, "gpg_key_id required for GPG signing" unless key_id

        signature_path = "#{artifact_path}.asc"
        cmd = "gpg --armor --detach-sign --default-key #{key_id} --output #{signature_path} #{artifact_path}"

        logs << log_info("Signing with GPG key", key_id: key_id)
        result = execute_shell_command(cmd, timeout: config["timeout"]&.to_i || 120)

        {
          success: result[:success],
          error: result[:error],
          signature_path: signature_path,
          verification_command: "gpg --verify #{signature_path} #{artifact_path}"
        }
      end

      def format_annotations(annotations)
        return "" unless annotations.is_a?(Hash)

        annotations.map { |k, v| "#{k}=#{v}" }.join(",")
      end
    end
  end
end
