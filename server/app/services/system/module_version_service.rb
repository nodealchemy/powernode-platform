# frozen_string_literal: true

module System
  # Service for managing module versioning operations
  # Handles version creation, rollback, and comparison
  class ModuleVersionService
    class VersionError < StandardError; end
    class LockError < VersionError; end
    class RollbackError < VersionError; end

    attr_reader :node_module, :current_user

    def initialize(node_module, current_user: nil)
      @node_module = node_module
      @current_user = current_user
    end

    # Create a new version of the module, capturing current state
    # @param changelog [String] optional description of changes
    # @param user [User] optional user who created this version
    # @return [System::NodeModuleVersion] the created version
    def create_version(changelog: nil, user: nil)
      raise LockError, 'Module is locked and cannot be versioned' if node_module.locked?

      user ||= current_user

      ActiveRecord::Base.transaction do
        version = node_module.versions.create!(
          changelog: changelog,
          created_by: user,
          mask: node_module.mask || {},
          file_spec: node_module.file_spec || {},
          package_spec: node_module.package_spec || {},
          config: node_module.config || {},
          data_file_name: node_module.data_file_name,
          data_checksum: node_module.data_checksum,
          data_file_size: node_module.data_file_size
        )

        node_module.update!(
          current_version: version,
          current_version_number: version.version_number
        )

        version
      end
    end

    # Create initial version when module is first created
    # @return [System::NodeModuleVersion] the initial version
    def create_initial_version
      return if node_module.versions.exists?

      create_version(changelog: 'Initial version')
    end

    # Rollback to a specific version
    # @param version [System::NodeModuleVersion] the version to rollback to
    # @param changelog [String] optional description for the rollback
    # @return [System::NodeModuleVersion] new version created from rollback
    def rollback_to(version, changelog: nil)
      raise LockError, 'Module is locked and cannot be modified' if node_module.locked?
      raise RollbackError, 'Version does not belong to this module' unless version.node_module_id == node_module.id

      changelog ||= "Rollback to version #{version.version_number}"

      ActiveRecord::Base.transaction do
        # Skip auto-versioning during rollback
        node_module.instance_variable_set(:@skip_auto_version, true)

        # Restore module state from version
        node_module.update!(
          mask: version.mask,
          file_spec: version.file_spec,
          package_spec: version.package_spec,
          config: version.config,
          data_file_name: version.data_file_name,
          data_checksum: version.data_checksum,
          data_file_size: version.data_file_size
        )

        node_module.instance_variable_set(:@skip_auto_version, false)

        # Create new version recording the rollback
        create_version(changelog: changelog)
      end
    end

    # Rollback to the previous version
    # @return [System::NodeModuleVersion] new version created from rollback
    def rollback_to_previous
      current = node_module.current_version
      raise RollbackError, 'No current version to rollback from' unless current

      previous = current.previous_version
      raise RollbackError, 'No previous version available' unless previous

      rollback_to(previous, changelog: "Rollback to version #{previous.version_number}")
    end

    # Lock the module to prevent further changes
    # @return [Boolean] true if locked successfully
    def lock!
      raise LockError, 'Module is already locked' if node_module.locked?

      node_module.update!(lock_spec: true)
    end

    # Unlock the module to allow changes (admin only typically)
    # @return [Boolean] true if unlocked successfully
    def unlock!
      raise LockError, 'Module is not locked' unless node_module.locked?

      node_module.update!(lock_spec: false)
    end

    # Compare two versions and return differences
    # @param version_a [System::NodeModuleVersion] first version
    # @param version_b [System::NodeModuleVersion] second version
    # @return [Hash] differences between versions
    def compare_versions(version_a, version_b)
      {
        version_numbers: [version_a.version_number, version_b.version_number],
        mask_diff: diff_json(version_a.mask, version_b.mask),
        file_spec_diff: diff_json(version_a.file_spec, version_b.file_spec),
        package_spec_diff: diff_json(version_a.package_spec, version_b.package_spec),
        config_diff: diff_json(version_a.config, version_b.config),
        data_file_changed: version_a.data_checksum != version_b.data_checksum
      }
    end

    # Get version history with summary information
    # @param limit [Integer] maximum number of versions to return
    # @return [Array<Hash>] version history with summaries
    def version_history(limit: 20)
      node_module.versions.ordered.limit(limit).map do |version|
        {
          id: version.id,
          version_number: version.version_number,
          changelog: version.changelog,
          created_by: version.created_by&.email,
          created_at: version.created_at,
          is_current: version.current?,
          has_data_file: version.has_data_file?
        }
      end
    end

    private

    def diff_json(hash_a, hash_b)
      hash_a ||= {}
      hash_b ||= {}

      all_keys = (hash_a.keys + hash_b.keys).uniq

      changes = {}
      all_keys.each do |key|
        val_a = hash_a[key]
        val_b = hash_b[key]
        next if val_a == val_b

        changes[key] = {
          from: val_a,
          to: val_b
        }
      end

      changes
    end
  end
end
