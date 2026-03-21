# frozen_string_literal: true

module System
  class NodeModuleCategory < BaseRecord
    include System::Base

    # === Associations ===
    belongs_to :account
    belongs_to :parent, class_name: 'System::NodeModuleCategory', optional: true
    has_many :children, class_name: 'System::NodeModuleCategory', foreign_key: :parent_id, dependent: :nullify
    has_many :node_modules, class_name: 'System::NodeModule', foreign_key: :category_id, dependent: :nullify

    # === Validations ===
    validates :name, presence: true, uniqueness: { scope: :account_id, case_sensitive: false }
    validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    # === Scopes ===
    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }
    scope :public_categories, -> { where(public: true) }
    scope :private_categories, -> { where(public: false) }
    scope :root_categories, -> { where(parent_id: nil) }
    scope :by_position, -> { order(position: :asc) }
    scope :by_name, -> { order(name: :asc) }

    # === Methods ===
    def root?
      parent_id.nil?
    end

    def has_children?
      children.exists?
    end

    def depth
      return 0 if root?
      parent.depth + 1
    end

    def ancestors
      return [] if root?
      [parent] + parent.ancestors
    end

    def descendants
      children.flat_map { |child| [child] + child.descendants }
    end

    def module_count
      node_modules.count + descendants.sum(&:module_count)
    end
  end
end
