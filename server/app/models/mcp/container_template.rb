# frozen_string_literal: true

module Mcp
  class ContainerTemplate < ApplicationRecord
    # Concerns
    include Auditable

    # Constants
    VISIBILITIES = %w[private account public].freeze
    STATUSES = %w[active deprecated archived].freeze
    DEFAULT_TIMEOUT = 3600
    DEFAULT_MEMORY_MB = 512
    DEFAULT_CPU_MILLICORES = 500

    # Associations
    belongs_to :account, optional: true  # nil = system template
    belongs_to :created_by, class_name: "User", optional: true

    has_many :container_instances, class_name: "Mcp::ContainerInstance",
                                   foreign_key: "template_id",
                                   dependent: :nullify

    # Validations
    validates :name, presence: true, length: { maximum: 255 }
    validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9\-]+\z/ }
    validates :image_name, presence: true
    validates :visibility, presence: true, inclusion: { in: VISIBILITIES }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :timeout_seconds, numericality: { greater_than: 0, less_than_or_equal_to: 86400 }
    validate :validate_security_options

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :public_templates, -> { where(visibility: "public", status: "active") }
    scope :system_templates, -> { where(account_id: nil) }
    scope :for_account, ->(account) { where(account: account).or(where(visibility: "public")).or(where(account_id: nil)) }

    # Callbacks
    before_validation :generate_slug, on: :create
    before_validation :set_defaults

    # Access control
    def self.accessible_by(account)
      where(account: account)
        .or(where(visibility: "public", status: "active"))
        .or(where(account_id: nil, status: "active"))
    end

    def accessible_by?(account)
      return true if visibility == "public" && active?
      return true if account_id.nil? && active?  # System template
      return true if account_id == account.id

      false
    end

    # Status checks
    def active?
      status == "active"
    end

    def deprecated?
      status == "deprecated"
    end

    def system_template?
      account_id.nil?
    end

    def private?
      visibility == "private"
    end

    # Lifecycle
    def deprecate!
      update!(status: "deprecated")
    end

    def archive!
      update!(status: "archived")
    end

    def activate!
      update!(status: "active")
    end

    # Full image reference
    def full_image_name
      if registry_url.present?
        "#{registry_url}/#{image_name}:#{image_tag}"
      else
        "#{image_name}:#{image_tag}"
      end
    end

    # Resource limits with defaults
    def effective_resource_limits
      {
        memory_mb: resource_limits.dig("memory_mb") || DEFAULT_MEMORY_MB,
        cpu_millicores: resource_limits.dig("cpu_millicores") || DEFAULT_CPU_MILLICORES,
        storage_bytes: resource_limits.dig("storage_bytes") || 1.gigabyte
      }
    end

    # Security configuration
    def effective_security_options
      {
        read_only_root: read_only_root,
        privileged: privileged,
        allow_network: allow_network,
        cap_drop: security_options.dig("cap_drop") || ["ALL"],
        cap_add: security_options.dig("cap_add") || [],
        no_new_privileges: security_options.dig("no_new_privileges") != false
      }
    end

    # Docker run options
    def docker_options
      opts = []
      security = effective_security_options

      opts << "--read-only" if security[:read_only_root]
      opts << "--cap-drop=ALL" if security[:cap_drop].include?("ALL")
      opts << "--security-opt=no-new-privileges:true" if security[:no_new_privileges]
      opts << "--memory=#{effective_resource_limits[:memory_mb]}m"
      opts << "--cpus=#{effective_resource_limits[:cpu_millicores] / 1000.0}"

      unless allow_network
        opts << "--network=none"
      end

      opts.join(" ")
    end

    # Execution tracking
    def record_execution!(success:)
      increment!(:execution_count)
      if success
        increment!(:success_count)
      else
        increment!(:failure_count)
      end
      touch(:last_used_at)
    end

    def success_rate
      return 0 if execution_count.zero?

      (success_count.to_f / execution_count * 100).round(2)
    end

    # Summary
    def template_summary
      {
        id: id,
        slug: slug,
        name: name,
        description: description,
        image_name: full_image_name,
        visibility: visibility,
        status: status,
        execution_count: execution_count,
        success_rate: success_rate,
        allow_network: allow_network,
        timeout_seconds: timeout_seconds
      }
    end

    def template_details
      template_summary.merge(
        environment_variables: environment_variables.keys,
        vault_secret_paths: vault_secret_paths.size,
        resource_limits: effective_resource_limits,
        security_options: effective_security_options,
        labels: labels,
        entrypoint: entrypoint,
        command_args: command_args,
        created_by: created_by&.full_name,
        created_at: created_at,
        last_used_at: last_used_at
      )
    end

    private

    def generate_slug
      return if slug.present?

      base_slug = name.parameterize
      self.slug = base_slug

      counter = 1
      while Mcp::ContainerTemplate.exists?(slug: slug)
        self.slug = "#{base_slug}-#{counter}"
        counter += 1
      end
    end

    def set_defaults
      self.timeout_seconds ||= DEFAULT_TIMEOUT
      self.max_retries ||= 3
      self.resource_limits ||= {}
      self.security_options ||= {}
      self.environment_variables ||= {}
      self.vault_secret_paths ||= []
      self.labels ||= {}
    end

    def validate_security_options
      if privileged && !account_id.nil?
        errors.add(:privileged, "can only be enabled for system templates")
      end
    end
  end
end
