class CreatePages < ActiveRecord::Migration[8.0]
  def change
    create_table :pages, id: false do |t|
      t.string :id, primary_key: true, null: false, limit: 36
      t.string :title, null: false, limit: 200
      t.string :slug, null: false, limit: 150
      t.text :content, null: false
      t.string :meta_description, limit: 300
      t.text :meta_keywords, limit: 500
      t.string :status, null: false, default: 'draft', limit: 20
      t.string :author_id, null: false, limit: 36
      t.datetime :published_at

      t.timestamps null: false

      t.foreign_key :users, column: :author_id
      t.index [:slug], unique: true
      t.index [:status]
      t.index [:published_at]
      t.index [:author_id]
      t.index [:created_at]
      t.index [:status, :published_at], where: "status = 'published'"
      t.index [:status, :author_id]
    end
  end
end
