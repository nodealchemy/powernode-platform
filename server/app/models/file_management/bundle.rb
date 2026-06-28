# frozen_string_literal: true

module FileManagement
  # A media asset bundle groups a content production's related assets — a video's
  # ordered scenes plus its voiceover/music, or a document's sections — as one
  # addressable project. Produced by a content_production Ai::Mission; the finished
  # render is referenced as the bundle's primary_object, and a later increment
  # shares the bundle as an expiring download link.
  #
  # Membership lives on FileManagement::Object (bundle_id + bundle_position +
  # bundle_role), so a single file belongs to at most one bundle and scenes carry
  # an explicit sequence for stitching.
  class Bundle < ApplicationRecord
    include Auditable

    BUNDLE_TYPES = %w[video_project document image_album audio_album mixed].freeze
    STATUSES = %w[draft assembling ready archived].freeze

    belongs_to :account
    belongs_to :created_by, class_name: "User", foreign_key: "created_by_id"
    belongs_to :mission, class_name: "Ai::Mission", foreign_key: "mission_id", optional: true
    belongs_to :primary_object, class_name: "FileManagement::Object", foreign_key: "primary_object_id", optional: true

    has_many :objects,
             -> { order(Arel.sql("bundle_position ASC NULLS LAST, created_at ASC")) },
             class_name: "FileManagement::Object",
             foreign_key: "bundle_id",
             inverse_of: :bundle,
             dependent: :nullify

    validates :name, presence: true, length: { maximum: 255 }
    validates :bundle_type, presence: true, inclusion: { in: BUNDLE_TYPES }
    validates :status, presence: true, inclusion: { in: STATUSES }

    attribute :metadata, :json, default: -> { {} }

    scope :for_account, ->(account_id) { where(account_id: account_id) }
    scope :by_status, ->(status) { where(status: status) }
    scope :by_type, ->(type) { where(bundle_type: type) }
    scope :ready, -> { where(status: "ready") }
    scope :recent, -> { order(created_at: :desc) }

    # The ordered scene assets (video clips / images) to stitch in sequence.
    def scenes
      objects.where(bundle_role: "scene")
    end

    # The audio overlays — voiceover and background music.
    def audio_tracks
      objects.where(bundle_role: %w[voiceover music])
    end

    def voiceover
      objects.where(bundle_role: "voiceover").first
    end

    def music
      objects.where(bundle_role: "music").first
    end

    # Attach an object to this bundle with a role and an optional explicit
    # position (defaults to the next slot in that role's sequence). Idempotent on
    # the object — moving an already-attached object re-roles/repositions it.
    def add_object!(object, role:, position: nil)
      role = role.to_s
      unless FileManagement::Object::BUNDLE_ROLES.include?(role)
        raise ArgumentError, "unknown bundle role: #{role.inspect}"
      end

      position ||= objects.where(bundle_role: role).maximum(:bundle_position).to_i + 1
      object.update!(bundle: self, bundle_role: role, bundle_position: position)
      object
    end

    def object_count
      objects.count
    end

    def bundle_summary
      {
        id: id,
        name: name,
        bundle_type: bundle_type,
        status: status,
        mission_id: mission_id,
        primary_object_id: primary_object_id,
        object_count: object_count,
        scene_count: scenes.count,
        created_at: created_at&.iso8601
      }
    end
  end
end
