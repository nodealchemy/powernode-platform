# frozen_string_literal: true

class CreateAiDataSourceEndpoints < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_data_source_endpoints, id: :uuid do |t|
      t.references :ai_data_source, type: :uuid, null: false, index: true,
                   foreign_key: { to_table: :ai_data_sources }
      t.string :name, null: false, limit: 255
      t.string :slug, null: false, limit: 100
      t.string :http_method, null: false, default: "GET", limit: 10
      t.string :path_template, limit: 1000
      t.jsonb :query_template, null: false, default: {}
      t.jsonb :body_template, null: false, default: {}
      t.string :response_format, limit: 50
      t.string :expected_content_type, limit: 255
      t.jsonb :response_mapping, null: false, default: {}
      t.jsonb :response_schema, null: false, default: {}
      t.integer :cache_ttl_seconds
      t.string :etag, limit: 500
      t.string :last_modified, limit: 255
      t.boolean :monitorable, null: false, default: false
      t.string :change_detection, limit: 50
      t.jsonb :metadata, null: false, default: {}
      t.timestamps

      t.index [:ai_data_source_id, :slug], unique: true,
              name: "index_ai_data_source_endpoints_unique_slug"
    end
  end
end
