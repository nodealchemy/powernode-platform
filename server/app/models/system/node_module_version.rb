# frozen_string_literal: true

module System
  # Stores historical versions of node modules for rollback capability
  # Each version captures the complete state of a module at a point in time
  class NodeModuleVersion < BaseRecord
    # === Associations ===
    belongs_to :node_module, class_name: 'System::NodeModule'
    belongs_to :created_by, class_name: 'User', optional: true

    # === Validations ===
    validates :version_number, presence: true,
                               numericality: { only_integer: true, greater_than: 0 },
                               uniqueness: { scope: :node_module_id }
    validates :node_module, presence: true

    # === Scopes ===
    scope :ordered, -> { order(version_number: :desc) }
    scope :by_version, -> { order(version_number: :asc) }
    scope :latest_first, -> { order(version_number: :desc) }
    scope :with_data_file, -> { where.not(data_file_name: nil) }

    # === Callbacks ===
    before_validation :set_version_number, on: :create

    # === Methods ===

    # Check if this version has a data file attached
    def has_data_file?
      data_file_name.present?
    end

    # Check if this is the current version for its module
    def current?
      node_module&.current_version_id == id
    end

    # Check if this is the latest version
    def latest?
      node_module&.versions&.maximum(:version_number) == version_number
    end

    # Get the previous version
    def previous_version
      return nil unless node_module

      node_module.versions.where('version_number < ?', version_number).order(version_number: :desc).first
    end

    # Get the next version
    def next_version
      return nil unless node_module

      node_module.versions.where('version_number > ?', version_number).order(version_number: :asc).first
    end

    # Verify data file integrity using checksum
    def verify_checksum(file_content)
      return false unless data_checksum.present?

      Digest::SHA256.hexdigest(file_content) == data_checksum
    end

    # Generate summary of what changed in this version
    def change_summary
      changelog.presence || "Version #{version_number}"
    end

    private

    def set_version_number
      return if version_number.present?

      max_version = node_module&.versions&.maximum(:version_number) || 0
      self.version_number = max_version + 1
    end
  end
end
