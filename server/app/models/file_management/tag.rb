# frozen_string_literal: true

module FileManagement
  class Tag < ApplicationRecord
    include Auditable

    # Associations
    belongs_to :account
    has_many :object_tags, class_name: "FileManagement::ObjectTag", foreign_key: :file_tag_id, dependent: :destroy
    has_many :objects, class_name: "FileManagement::Object", through: :object_tags, source: :object

    # Validations
    validates :name, presence: true, length: { maximum: 100 }
    validates :name, uniqueness: { scope: :account_id, case_sensitive: false }
    validates :color, format: { with: /\A#[0-9A-Fa-f]{6}\z/, allow_blank: true, message: "must be a valid hex color" }
    validates :files_count, numericality: { greater_than_or_equal_to: 0 }

    # Scopes
    scope :by_name, -> { order(:name) }
    scope :popular, -> { where("files_count > 0").order(files_count: :desc) }
    scope :unused, -> { where(files_count: 0) }
    scope :recent, -> { order(created_at: :desc) }
    scope :with_color, -> { where.not(color: nil) }
    scope :search, ->(query) { where("name ILIKE ?", "%#{query}%") }

    # Callbacks
    before_validation :normalize_name
    before_validation :generate_default_color, if: -> { color.blank? }

    # Methods
    def increment_files_count!
      increment!(:files_count)
    end

    def decrement_files_count!
      decrement!(:files_count) if files_count > 0
    end

    def unused?
      files_count.zero?
    end

    def tag_summary
      {
        id: id,
        name: name,
        color: color,
        description: description,
        files_count: files_count,
        created_at: created_at.iso8601
      }
    end

    private

    def normalize_name
      self.name = name.strip.downcase if name.present?
    end

    def generate_default_color
      hue = rand(360)
      self.color = "##{"%06x" % hsv_to_rgb(hue, 0.3, 0.9)}"
    end

    def hsv_to_rgb(h, s, v)
      h_i = (h / 60.0).to_i
      f = (h / 60.0) - h_i
      p = v * (1 - s)
      q = v * (1 - f * s)
      t = v * (1 - (1 - f) * s)

      r, g, b = case h_i
      when 0 then [ v, t, p ]
      when 1 then [ q, v, p ]
      when 2 then [ p, v, t ]
      when 3 then [ p, q, v ]
      when 4 then [ t, p, v ]
      else [ v, p, q ]
      end

      [ (r * 255).to_i, (g * 255).to_i, (b * 255).to_i ].map { |x| x.to_s(16).rjust(2, "0") }.join.to_i(16)
    end
  end
end
