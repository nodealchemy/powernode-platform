# frozen_string_literal: true

module System
  class PuppetResource < BaseRecord
    include System::Base

    RESOURCE_TYPES = %w[file package service exec user group cron mount host notify class define custom].freeze

    # == Associations
    belongs_to :puppet_module, class_name: 'System::PuppetModule',
               foreign_key: :puppet_module_id, inverse_of: :puppet_resources

    # == Delegations
    delegate :account, to: :puppet_module
    delegate :account_id, to: :puppet_module

    # == Validations
    validates :name, presence: true,
              uniqueness: { scope: :puppet_module_id, message: 'must be unique within puppet module' },
              length: { maximum: 255 }
    validates :resource_type, presence: true, inclusion: { in: RESOURCE_TYPES }
    validates :title, length: { maximum: 500 }, allow_blank: true
    validates :path, length: { maximum: 1000 }, allow_blank: true

    # == Scopes
    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }
    scope :exported, -> { where(exported: true) }
    scope :not_exported, -> { where(exported: false) }
    scope :by_type, ->(type) { where(resource_type: type) }
    scope :files, -> { by_type('file') }
    scope :packages, -> { by_type('package') }
    scope :services, -> { by_type('service') }
    scope :execs, -> { by_type('exec') }
    scope :users, -> { by_type('user') }
    scope :groups, -> { by_type('group') }
    scope :crons, -> { by_type('cron') }
    scope :mounts, -> { by_type('mount') }
    scope :hosts, -> { by_type('host') }
    scope :notifies, -> { by_type('notify') }
    scope :classes, -> { by_type('class') }
    scope :defines, -> { by_type('define') }
    scope :custom, -> { by_type('custom') }
    scope :search, ->(query) {
      where('name ILIKE :q OR description ILIKE :q OR title ILIKE :q', q: "%#{query}%")
    }

    # == Instance Methods
    def enable!
      update!(enabled: true)
    end

    def disable!
      update!(enabled: false)
    end

    def export!
      update!(exported: true)
    end

    def unexport!
      update!(exported: false)
    end

    def puppet_title
      title.presence || name
    end

    def resource_identifier
      "#{resource_type.capitalize}['#{puppet_title}']"
    end

    def file?
      resource_type == 'file'
    end

    def package?
      resource_type == 'package'
    end

    def service?
      resource_type == 'service'
    end

    def exec?
      resource_type == 'exec'
    end

    def user?
      resource_type == 'user'
    end

    def group?
      resource_type == 'group'
    end

    def cron?
      resource_type == 'cron'
    end

    def mount?
      resource_type == 'mount'
    end

    def host?
      resource_type == 'host'
    end

    def notify?
      resource_type == 'notify'
    end

    def puppet_class?
      resource_type == 'class'
    end

    def define?
      resource_type == 'define'
    end

    def custom?
      resource_type == 'custom'
    end

    def parameter(key)
      parameters[key.to_s]
    end

    def set_parameter(key, value)
      self.parameters = parameters.merge(key.to_s => value)
    end

    def remove_parameter(key)
      self.parameters = parameters.except(key.to_s)
    end

    def config_value(key)
      config[key.to_s]
    end

    def set_config(key, value)
      self.config = config.merge(key.to_s => value)
    end

    # Generate Puppet DSL representation
    def to_puppet_dsl
      lines = []

      prefix = exported ? '@@' : ''
      lines << "#{prefix}#{resource_type} { '#{puppet_title}':"

      parameters.each do |key, value|
        formatted_value = format_puppet_value(value)
        lines << "  #{key} => #{formatted_value},"
      end

      lines << '}'
      lines.join("\n")
    end

    private

    def format_puppet_value(value)
      case value
      when String
        "'#{value}'"
      when TrueClass, FalseClass
        value.to_s
      when Array
        "[#{value.map { |v| format_puppet_value(v) }.join(', ')}]"
      when Hash
        "{ #{value.map { |k, v| "'#{k}' => #{format_puppet_value(v)}" }.join(', ')} }"
      else
        value.to_s
      end
    end
  end
end
