# frozen_string_literal: true

module SupplyChain
  class QuestionnaireTemplate < ApplicationRecord
    include Auditable

    self.table_name = "supply_chain_questionnaire_templates"

    # ============================================
    # Constants
    # ============================================
    TEMPLATE_TYPES = %w[soc2 iso27001 gdpr hipaa pci_dss custom].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :account, optional: true
    belongs_to :created_by, class_name: "User", optional: true

    has_many :questionnaire_responses, class_name: "SupplyChain::QuestionnaireResponse",
             foreign_key: :template_id, dependent: :restrict_with_error

    # ============================================
    # Validations
    # ============================================
    validates :name, presence: true
    validates :template_type, presence: true, inclusion: { in: TEMPLATE_TYPES }
    validates :version, presence: true
    validate :unique_name_within_scope

    # ============================================
    # Scopes
    # ============================================
    scope :system_templates, -> { where(is_system: true) }
    scope :custom_templates, -> { where(is_system: false) }
    scope :active, -> { where(is_active: true) }
    scope :by_type, ->(type) { where(template_type: type) }
    scope :for_account, ->(account) { where(account_id: [ account.id, nil ]).or(where(is_system: true)) }
    scope :alphabetical, -> { order(name: :asc) }

    # ============================================
    # Callbacks
    # ============================================
    before_save :sanitize_jsonb_fields

    # ============================================
    # Instance Methods
    # ============================================
    def system?
      is_system
    end

    def custom?
      !is_system
    end

    def active?
      is_active
    end

    def soc2?
      template_type == "soc2"
    end

    def iso27001?
      template_type == "iso27001"
    end

    def gdpr?
      template_type == "gdpr"
    end

    def hipaa?
      template_type == "hipaa"
    end

    def pci_dss?
      template_type == "pci_dss"
    end

    def section_count
      sections&.length || 0
    end

    def question_count
      questions&.length || 0
    end

    def questions_by_section
      return {} if sections.blank? || questions.blank?

      questions.group_by { |q| q["section_id"] }
    end

    def get_section(section_id)
      sections&.find { |s| s["id"] == section_id }
    end

    def get_question(question_id)
      questions&.find { |q| q["id"] == question_id }
    end

    def add_section(id:, name:, description: nil, weight: 1.0)
      section = {
        id: id,
        name: name,
        description: description,
        weight: weight,
        order: sections.length
      }

      self.sections = (sections + [ section ])
      save!
      section
    end

    def add_question(section_id:, text:, type: "text", required: true, **options)
      question = {
        id: SecureRandom.uuid,
        section_id: section_id,
        text: text,
        type: type,
        required: required,
        order: questions.count { |q| q["section_id"] == section_id },
        **options
      }

      self.questions = (questions + [ question ])
      save!
      question
    end

    def remove_question(question_id)
      self.questions = questions.reject { |q| q["id"] == question_id }
      save!
    end

    def activate!
      update!(is_active: true)
    end

    def deactivate!
      update!(is_active: false)
    end

    def duplicate(new_name: nil, for_account: nil)
      new_template = dup
      new_template.name = new_name || "#{name} (Copy)"
      new_template.account = for_account || account
      new_template.is_system = false
      new_template.is_active = true
      new_template.save!
      new_template
    end

    def summary
      {
        id: id,
        name: name,
        description: description,
        template_type: template_type,
        version: version,
        is_system: is_system,
        is_active: is_active,
        section_count: section_count,
        question_count: question_count,
        created_at: created_at
      }
    end

    def full_template
      {
        summary: summary,
        sections: sections,
        questions: questions
      }
    end

    # ============================================
    # Class Methods
    # ============================================
    class << self
      def create_soc2_template
        template = new(
          name: "SOC 2 Type II Security Assessment",
          description: "Standard SOC 2 Type II security questionnaire covering Trust Service Criteria",
          template_type: "soc2",
          version: "1.0",
          is_system: true,
          is_active: true
        )

        template.sections = [
          { id: "cc1", name: "Control Environment", description: "Organization and management", weight: 1.0, order: 0 },
          { id: "cc2", name: "Communication and Information", description: "Information systems", weight: 1.0, order: 1 },
          { id: "cc3", name: "Risk Assessment", description: "Risk identification and management", weight: 1.0, order: 2 },
          { id: "cc4", name: "Monitoring Activities", description: "Ongoing evaluation", weight: 1.0, order: 3 },
          { id: "cc5", name: "Control Activities", description: "Policies and procedures", weight: 1.0, order: 4 },
          { id: "cc6", name: "Logical and Physical Access", description: "Access controls", weight: 1.5, order: 5 },
          { id: "cc7", name: "System Operations", description: "System monitoring and incident response", weight: 1.5, order: 6 },
          { id: "cc8", name: "Change Management", description: "System changes", weight: 1.0, order: 7 },
          { id: "cc9", name: "Risk Mitigation", description: "Business continuity and disaster recovery", weight: 1.0, order: 8 }
        ]

        template.questions = []
        template.save!
        template
      end

      def create_iso27001_template
        template = new(
          name: "ISO 27001 Security Assessment",
          description: "ISO 27001 information security management system assessment",
          template_type: "iso27001",
          version: "1.0",
          is_system: true,
          is_active: true
        )

        template.sections = [
          { id: "a5", name: "Information Security Policies", weight: 1.0, order: 0 },
          { id: "a6", name: "Organization of Information Security", weight: 1.0, order: 1 },
          { id: "a7", name: "Human Resource Security", weight: 1.0, order: 2 },
          { id: "a8", name: "Asset Management", weight: 1.0, order: 3 },
          { id: "a9", name: "Access Control", weight: 1.5, order: 4 },
          { id: "a10", name: "Cryptography", weight: 1.0, order: 5 },
          { id: "a11", name: "Physical and Environmental Security", weight: 1.0, order: 6 },
          { id: "a12", name: "Operations Security", weight: 1.5, order: 7 },
          { id: "a13", name: "Communications Security", weight: 1.0, order: 8 },
          { id: "a14", name: "System Acquisition, Development and Maintenance", weight: 1.0, order: 9 },
          { id: "a15", name: "Supplier Relationships", weight: 1.0, order: 10 },
          { id: "a16", name: "Information Security Incident Management", weight: 1.0, order: 11 },
          { id: "a17", name: "Business Continuity Management", weight: 1.0, order: 12 },
          { id: "a18", name: "Compliance", weight: 1.0, order: 13 }
        ]

        template.questions = []
        template.save!
        template
      end
    end

    private

    def sanitize_jsonb_fields
      self.sections ||= []
      self.questions ||= []
      self.metadata ||= {}
    end

    def unique_name_within_scope
      scope = is_system ? self.class.system_templates : self.class.where(account_id: account_id)
      existing = scope.where(name: name).where.not(id: id)

      errors.add(:name, "has already been taken") if existing.exists?
    end
  end
end
