# frozen_string_literal: true

class AddPageContentCategoryToFileObjects < ActiveRecord::Migration[8.0]
  def up
    # Remove old constraint and add new one with page_content included
    remove_check_constraint :file_objects, name: 'file_objects_category_check'
    add_check_constraint :file_objects,
                         "category IN ('user_upload', 'workflow_output', 'ai_generated', 'temp', 'system', 'import', 'page_content')",
                         name: 'file_objects_category_check'
  end

  def down
    remove_check_constraint :file_objects, name: 'file_objects_category_check'
    add_check_constraint :file_objects,
                         "category IN ('user_upload', 'workflow_output', 'ai_generated', 'temp', 'system', 'import')",
                         name: 'file_objects_category_check'
  end
end
