# frozen_string_literal: true

require "mini_magick"

module Mcp
  module NodeExecutors
    # File Transform node executor
    # Transforms files (resize, convert, optimize) and saves results
    class FileTransform < Base
      SUPPORTED_OPERATIONS = %w[
        resize
        convert
        compress
        thumbnail
        watermark
        crop
        rotate
        grayscale
        blur
      ].freeze

      protected

      def perform_execution
        log_info "Executing File Transform node"

        # Get source file
        file_object = get_source_file

        unless file_object
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError, "No source file provided for transformation"
        end

        # Validate transformation operation
        operation = configuration["operation"]
        unless SUPPORTED_OPERATIONS.include?(operation)
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "Unsupported operation: #{operation}. Supported: #{SUPPORTED_OPERATIONS.join(', ')}"
        end

        log_debug "Transforming file: #{file_object.filename} with operation: #{operation}"

        # Create file storage service
        file_service = ::FileStorageService.new(
          @orchestrator.account,
          storage_config: file_object.file_storage
        )

        # Download original file
        original_content = file_service.download_file(file_object)

        # Perform transformation
        transformed_content, new_format = perform_transformation(
          original_content,
          file_object.content_type,
          operation
        )

        # Generate filename for transformed file
        new_filename = generate_transformed_filename(file_object.filename, operation, new_format)

        # Upload transformed file if configured to save
        if configuration["save_output"] != false
          transformed_file = file_service.upload_file(
            StringIO.new(transformed_content),
            filename: new_filename,
            content_type: "image/#{new_format}",
            category: configuration["output_category"] || "workflow_output",
            description: "Transformed from #{file_object.filename} (#{operation})",
            visibility: configuration["output_visibility"] || file_object.visibility,
            metadata: {
              "workflow_run_id" => @orchestrator.workflow_run.id,
              "node_id" => @node.node_id,
              "source_file_id" => file_object.id,
              "transformation" => operation,
              "original_filename" => file_object.filename
            }.merge(configuration["metadata"] || {}),
            attachable: @orchestrator.workflow_run,
            uploaded_by_id: @orchestrator.user&.id
          )

          # Store transformed file_id in variable
          if configuration["output_variable"]
            set_variable(configuration["output_variable"], transformed_file.id)
          end

          output_file_data = {
            file_id: transformed_file.id,
            filename: transformed_file.filename,
            file_size: transformed_file.file_size,
            content_type: transformed_file.content_type,
            url: file_service.file_url(transformed_file)
          }
        else
          # Don't save, just return content
          output_file_data = {
            content: Base64.strict_encode64(transformed_content),
            filename: new_filename,
            file_size: transformed_content.bytesize,
            content_type: "image/#{new_format}"
          }

          # Store content in variable if configured
          if configuration["output_variable"]
            set_variable(configuration["output_variable"], transformed_content)
          end
        end

        log_info "File transformation completed: #{operation}"

        # Return standardized result
        {
          output: output_file_data,
          data: {
            source_file: file_object.file_summary,
            transformation: operation,
            transformation_params: configuration["params"] || {},
            original_size: file_object.file_size,
            transformed_size: transformed_content.bytesize,
            size_reduction_percent: calculate_size_reduction(file_object.file_size, transformed_content.bytesize)
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "file_transform",
            executed_at: Time.current.iso8601,
            operation: operation,
            format_changed: file_object.extension != new_format
          }
        }
      rescue ::FileStorageService::FileNotFoundError => e
        log_error "Source file not found: #{e.message}"
        raise Mcp::AiWorkflowOrchestrator::NodeExecutionError, "Source file not found: #{e.message}"
      rescue StandardError => e
        log_error "File transformation failed: #{e.message}"
        raise Mcp::AiWorkflowOrchestrator::NodeExecutionError, "File transformation failed: #{e.message}"
      end

      private

      def get_source_file
        # Get file_id from configuration or variables
        file_id = configuration["file_id"] ||
                  get_variable(configuration["file_id_variable"]) ||
                  input_data&.dig("file_id")

        return nil unless file_id

        ::FileManagement::Object.find_by(id: file_id, account: @orchestrator.account)
      end

      def perform_transformation(file_content, content_type, operation)
        # Only support image transformations for now
        unless content_type.start_with?("image/")
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "File transformations only support images, got: #{content_type}"
        end

        # Create temporary file for processing
        tempfile = Tempfile.new([ "transform", File.extname(content_type) ])
        tempfile.binmode
        tempfile.write(file_content)
        tempfile.rewind

        # Process with MiniMagick
        image = MiniMagick::Image.open(tempfile.path)

        case operation
        when "resize"
          resize_image(image)
        when "thumbnail"
          create_thumbnail(image)
        when "convert"
          convert_format(image)
        when "compress"
          compress_image(image)
        when "watermark"
          add_watermark(image)
        when "crop"
          crop_image(image)
        when "rotate"
          rotate_image(image)
        when "grayscale"
          image.colorspace("Gray")
        when "blur"
          blur_image(image)
        end

        # Return transformed content and format
        [ File.read(image.path), image.type.downcase ]
      ensure
        tempfile&.close
        tempfile&.unlink
      end

      def resize_image(image)
        width = configuration.dig("params", "width")
        height = configuration.dig("params", "height")
        maintain_aspect = configuration.dig("params", "maintain_aspect") != false

        if maintain_aspect
          image.resize "#{width}x#{height}"
        else
          image.resize "#{width}x#{height}!"
        end
      end

      def create_thumbnail(image)
        size = configuration.dig("params", "size") || 200
        image.resize "#{size}x#{size}^"
        image.gravity "center"
        image.crop "#{size}x#{size}+0+0"
      end

      def convert_format(image)
        format = configuration.dig("params", "format") || "png"
        image.format format
      end

      def compress_image(image)
        quality = configuration.dig("params", "quality") || 85
        image.quality quality.to_s
      end

      def add_watermark(image)
        text = configuration.dig("params", "text") || "Watermark"
        position = configuration.dig("params", "position") || "SouthEast"

        image.combine_options do |c|
          c.gravity position
          c.pointsize "36"
          c.fill "rgba(255,255,255,0.5)"
          c.draw "text 10,10 '#{text}'"
        end
      end

      def crop_image(image)
        width = configuration.dig("params", "width")
        height = configuration.dig("params", "height")
        x = configuration.dig("params", "x") || 0
        y = configuration.dig("params", "y") || 0

        image.crop "#{width}x#{height}+#{x}+#{y}"
      end

      def rotate_image(image)
        degrees = configuration.dig("params", "degrees") || 90
        image.rotate degrees.to_s
      end

      def blur_image(image)
        radius = configuration.dig("params", "radius") || 5
        sigma = configuration.dig("params", "sigma") || 3
        image.blur "#{radius}x#{sigma}"
      end

      def generate_transformed_filename(original_filename, operation, new_format)
        base_name = File.basename(original_filename, ".*")
        "#{base_name}_#{operation}.#{new_format}"
      end

      def calculate_size_reduction(original_size, new_size)
        return 0 if original_size.zero?

        reduction = ((original_size - new_size).to_f / original_size * 100).round(2)
        reduction.negative? ? 0 : reduction
      end
    end
  end
end
