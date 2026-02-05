# frozen_string_literal: true

module Mcp
  class ContainerTemplate < ApplicationRecord
    self.table_name = "mcp_container_templates"

    # Concerns
    include Auditable

    # Constants
    VISIBILITIES = %w[private account public].freeze
    STATUSES = %w[active deprecated archived].freeze
    CATEGORIES = %w[ci-cd testing security devops ai-agent data-processing monitoring utility].freeze
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
    validates :name, uniqueness: { scope: :account_id }
    validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9\-]+\z/ }
    validates :image_name, presence: true
    validates :visibility, presence: true, inclusion: { in: VISIBILITIES }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :timeout_seconds, numericality: { greater_than: 0, less_than_or_equal_to: 86400 }
    validates :memory_mb, numericality: { greater_than_or_equal_to: 64, less_than_or_equal_to: 8192 }, allow_nil: true
    validates :cpu_millicores, numericality: { greater_than_or_equal_to: 100, less_than_or_equal_to: 4000 }, allow_nil: true
    validates :category, inclusion: { in: CATEGORIES }, allow_blank: true
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

    # Security configuration
    def effective_security_options
      {
        read_only_root: read_only_root,
        privileged: privileged,
        network_access: network_access,
        cap_drop: security_options.dig("cap_drop") || [ "ALL" ],
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
      opts << "--memory=#{memory_mb || DEFAULT_MEMORY_MB}m"
      opts << "--cpus=#{(cpu_millicores || DEFAULT_CPU_MILLICORES) / 1000.0}"

      unless network_access
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
        category: category,
        memory_mb: memory_mb,
        cpu_millicores: cpu_millicores,
        execution_count: execution_count,
        success_rate: success_rate,
        network_access: network_access,
        timeout_seconds: timeout_seconds
      }
    end

    def template_details
      template_summary.merge(
        environment_variables: environment_variables,
        vault_secret_paths: vault_secret_paths.size,
        memory_mb: memory_mb,
        cpu_millicores: cpu_millicores,
        sandbox_mode: sandbox_mode,
        network_access: network_access,
        input_schema: input_schema,
        output_schema: output_schema,
        allowed_egress_domains: allowed_egress_domains,
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
      return if name.blank?

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
      self.memory_mb ||= DEFAULT_MEMORY_MB
      self.cpu_millicores ||= DEFAULT_CPU_MILLICORES
      self.resource_limits ||= {}
      self.security_options ||= {}
      self.environment_variables ||= {}
      self.vault_secret_paths ||= []
      self.labels ||= {}
      self.input_schema ||= {}
      self.output_schema ||= {}
      self.allowed_egress_domains ||= []
    end

    def validate_security_options
      if privileged && !account_id.nil?
        errors.add(:privileged, "can only be enabled for system templates")
      end
    end
  end
end
