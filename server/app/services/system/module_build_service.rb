# frozen_string_literal: true

module System
  # Service for building node modules
  # Handles compilation, packaging, and artifact generation
  class ModuleBuildService
    class BuildError < StandardError; end

    BUILD_STAGES = %w[prepare validate compile package finalize].freeze

    # Build a module
    #
    # @param node_module [System::NodeModule] The module to build
    # @param options [Hash] Build options
    # @return [Hash] Result with :success, :build_id, :artifacts, :error
    def self.build(node_module:, options: {})
      new.build(node_module: node_module, options: options)
    end

    def build(node_module:, options: {})
      validate_module!(node_module)

      unless node_module.enabled?
        return { success: false, error: "Module is disabled" }
      end

      Rails.logger.info("[ModuleBuildService] Building module #{node_module.name}")

      build_id = generate_build_id
      build_dir = prepare_build_directory(node_module, build_id)

      begin
        results = {}

        BUILD_STAGES.each do |stage|
          Rails.logger.info("[ModuleBuildService] Stage: #{stage}")
          result = send("stage_#{stage}", node_module, build_dir, options)

          unless result[:success]
            cleanup_build(build_dir)
            return { success: false, error: "Build failed at #{stage}: #{result[:error]}", stage: stage }
          end

          results[stage] = result
        end

        # Update module with build info
        update_module_build_info(node_module, build_id, results)

        {
          success: true,
          build_id: build_id,
          artifacts: results[:package][:artifacts],
          duration: calculate_duration(results)
        }
      rescue StandardError => e
        Rails.logger.error("[ModuleBuildService] Build failed: #{e.message}")
        cleanup_build(build_dir)
        { success: false, error: e.message }
      end
    end

    private

    def validate_module!(node_module)
      raise ArgumentError, "Module required" unless node_module
      raise ArgumentError, "Module must be a System::NodeModule" unless node_module.is_a?(::System::NodeModule)
    end

    def generate_build_id
      "build-#{Time.current.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(4)}"
    end

    def prepare_build_directory(node_module, build_id)
      dir = File.join(Rails.root, "tmp", "builds", node_module.id.to_s, build_id)
      FileUtils.mkdir_p(dir)
      FileUtils.mkdir_p(File.join(dir, "src"))
      FileUtils.mkdir_p(File.join(dir, "output"))
      FileUtils.mkdir_p(File.join(dir, "artifacts"))
      dir
    end

    def cleanup_build(build_dir)
      FileUtils.rm_rf(build_dir) if build_dir && File.exist?(build_dir)
    rescue StandardError => e
      Rails.logger.warn("[ModuleBuildService] Cleanup failed: #{e.message}")
    end

    # Stage: Prepare - Set up build environment
    def stage_prepare(node_module, build_dir, options)
      Rails.logger.info("[ModuleBuildService] Preparing build environment")

      start_time = Time.current

      # Copy module source files
      if node_module.data.present?
        # Extract or copy module data to src directory
        src_dir = File.join(build_dir, "src")

        # In production, would handle:
        # - Extracting tarball/zip archives
        # - Copying files from FileObject storage
        # - Setting up symlinks for dependencies

        Rails.logger.info("[ModuleBuildService] Would extract module data to #{src_dir}")
      end

      # Resolve dependencies
      dependencies = resolve_dependencies(node_module)

      {
        success: true,
        duration: Time.current - start_time,
        dependencies: dependencies.map(&:name)
      }
    end

    # Stage: Validate - Check module configuration
    def stage_validate(node_module, build_dir, options)
      Rails.logger.info("[ModuleBuildService] Validating module configuration")

      start_time = Time.current
      errors = []

      # Validate file_spec
      if node_module.file_spec.present?
        unless valid_file_spec?(node_module.file_spec)
          errors << "Invalid file_spec configuration"
        end
      end

      # Validate mask configuration
      if node_module.mask.present?
        unless valid_mask?(node_module.mask)
          errors << "Invalid mask configuration"
        end
      end

      # Check dependencies are available
      missing_deps = check_missing_dependencies(node_module)
      if missing_deps.any?
        errors << "Missing dependencies: #{missing_deps.join(', ')}"
      end

      if errors.any?
        { success: false, error: errors.join("; ") }
      else
        { success: true, duration: Time.current - start_time }
      end
    end

    # Stage: Compile - Process module files
    def stage_compile(node_module, build_dir, options)
      Rails.logger.info("[ModuleBuildService] Compiling module")

      start_time = Time.current
      output_dir = File.join(build_dir, "output")

      # Process based on module variety
      case node_module.variety
      when "config"
        compile_config_module(node_module, build_dir, output_dir, options)
      when "instance"
        compile_instance_module(node_module, build_dir, output_dir, options)
      when "subscription"
        compile_subscription_module(node_module, build_dir, output_dir, options)
      else
        compile_generic_module(node_module, build_dir, output_dir, options)
      end

      {
        success: true,
        duration: Time.current - start_time,
        output_dir: output_dir
      }
    end

    # Stage: Package - Create distributable artifacts
    def stage_package(node_module, build_dir, options)
      Rails.logger.info("[ModuleBuildService] Packaging module artifacts")

      start_time = Time.current
      artifacts_dir = File.join(build_dir, "artifacts")
      output_dir = File.join(build_dir, "output")
      artifacts = []

      # Create tarball
      tarball_name = "#{node_module.name.parameterize}-#{timestamp}.tar.gz"
      tarball_path = File.join(artifacts_dir, tarball_name)

      # In production: tar -czf #{tarball_path} -C #{output_dir} .
      Rails.logger.info("[ModuleBuildService] Would create #{tarball_path}")
      artifacts << { type: "tarball", path: tarball_path, name: tarball_name }

      # Create checksum file
      checksum_name = "#{tarball_name}.sha256"
      checksum_path = File.join(artifacts_dir, checksum_name)
      Rails.logger.info("[ModuleBuildService] Would create #{checksum_path}")
      artifacts << { type: "checksum", path: checksum_path, name: checksum_name }

      # Create manifest
      manifest = generate_manifest(node_module, artifacts)
      manifest_path = File.join(artifacts_dir, "manifest.json")
      File.write(manifest_path, manifest.to_json)
      artifacts << { type: "manifest", path: manifest_path, name: "manifest.json" }

      {
        success: true,
        duration: Time.current - start_time,
        artifacts: artifacts
      }
    end

    # Stage: Finalize - Clean up and record results
    def stage_finalize(node_module, build_dir, options)
      Rails.logger.info("[ModuleBuildService] Finalizing build")

      start_time = Time.current

      # Move artifacts to permanent storage
      artifacts_dir = File.join(build_dir, "artifacts")
      storage_dir = module_storage_directory(node_module)
      FileUtils.mkdir_p(storage_dir)

      # In production, would:
      # - Move artifacts to FileObject storage
      # - Update module attachment
      # - Clean up build directory (or archive for debugging)

      Rails.logger.info("[ModuleBuildService] Would move artifacts to #{storage_dir}")

      {
        success: true,
        duration: Time.current - start_time,
        storage_dir: storage_dir
      }
    end

    def resolve_dependencies(node_module)
      # Get direct dependencies
      dependencies = []

      node_module.module_dependencies.includes(:dependency).each do |mod_dep|
        dependencies << mod_dep.dependency if mod_dep.dependency
      end

      # Resolve transitive dependencies (topological sort)
      resolved = []
      visited = Set.new

      resolve_recursive(dependencies, resolved, visited)

      resolved
    end

    def resolve_recursive(modules, resolved, visited)
      modules.each do |mod|
        next if visited.include?(mod.id)

        visited.add(mod.id)

        # Resolve this module's dependencies first
        deps = mod.module_dependencies.includes(:dependency).map(&:dependency).compact
        resolve_recursive(deps, resolved, visited)

        resolved << mod unless resolved.include?(mod)
      end
    end

    def check_missing_dependencies(node_module)
      missing = []

      node_module.module_dependencies.includes(:dependency).each do |mod_dep|
        if mod_dep.dependency.nil? || !mod_dep.dependency.enabled?
          missing << mod_dep.dependency_id
        end
      end

      missing
    end

    def valid_file_spec?(file_spec)
      return true if file_spec.blank?

      # Validate file_spec structure
      file_spec.is_a?(Hash)
    end

    def valid_mask?(mask)
      return true if mask.blank?

      # Validate mask structure
      mask.is_a?(Hash)
    end

    def compile_config_module(node_module, build_dir, output_dir, options)
      Rails.logger.info("[ModuleBuildService] Compiling config module")
      # Process configuration templates
    end

    def compile_instance_module(node_module, build_dir, output_dir, options)
      Rails.logger.info("[ModuleBuildService] Compiling instance module")
      # Process instance-specific files
    end

    def compile_subscription_module(node_module, build_dir, output_dir, options)
      Rails.logger.info("[ModuleBuildService] Compiling subscription module")
      # Process subscription files
    end

    def compile_generic_module(node_module, build_dir, output_dir, options)
      Rails.logger.info("[ModuleBuildService] Compiling generic module")
      # Default compilation
    end

    def generate_manifest(node_module, artifacts)
      {
        name: node_module.name,
        version: timestamp,
        variety: node_module.variety,
        priority: node_module.priority,
        built_at: Time.current.iso8601,
        artifacts: artifacts.map { |a| { type: a[:type], name: a[:name] } },
        dependencies: node_module.module_dependencies.includes(:dependency).map do |dep|
          { name: dep.dependency&.name, id: dep.dependency_id }
        end
      }
    end

    def update_module_build_info(node_module, build_id, results)
      # Update module config with build info
      config = node_module.config || {}
      config["last_build"] = {
        "build_id" => build_id,
        "built_at" => Time.current.iso8601,
        "success" => true
      }

      node_module.update!(config: config)
    end

    def calculate_duration(results)
      results.values.sum { |r| r[:duration] || 0 }
    end

    def module_storage_directory(node_module)
      File.join(Rails.root, "storage", "modules", node_module.account_id.to_s, node_module.id.to_s)
    end

    def timestamp
      Time.current.strftime("%Y%m%d%H%M%S")
    end
  end
end
