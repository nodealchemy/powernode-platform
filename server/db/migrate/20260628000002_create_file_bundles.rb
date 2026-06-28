# frozen_string_literal: true

# Media asset bundles — group a content production's related assets (a video's
# ordered scenes plus its voiceover/music, or a document's sections) as one
# addressable project. Produced by a content_production Ai::Mission; the finished
# render is the bundle's primary_object, and a later increment shares the bundle.
class CreateFileBundles < ActiveRecord::Migration[8.0]
  def change
    create_table :file_bundles, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.uuid :account_id, null: false
      t.uuid :created_by_id, null: false # User who created the bundle
      t.uuid :mission_id                 # producing content_production mission (optional)
      t.uuid :primary_object_id          # the finished/rendered artifact (optional)

      t.string :name, null: false
      t.string :bundle_type, null: false, default: "mixed"  # video_project|document|image_album|audio_album|mixed
      t.string :status, null: false, default: "draft"       # draft|assembling|ready|archived

      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :file_bundles, [:account_id, :status]
    add_index :file_bundles, :account_id
    add_index :file_bundles, :mission_id
    add_index :file_bundles, :primary_object_id

    # Membership lives on the file object: which bundle it belongs to, its ordering
    # within the bundle (scene sequence), and its role (scene|voiceover|music|...).
    add_column :file_objects, :bundle_id, :uuid
    add_column :file_objects, :bundle_position, :integer
    add_column :file_objects, :bundle_role, :string
    add_index :file_objects, :bundle_id
    add_index :file_objects, [:bundle_id, :bundle_position]
  end
end
