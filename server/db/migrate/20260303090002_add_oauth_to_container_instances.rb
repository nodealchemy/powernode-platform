# frozen_string_literal: true

class AddOauthToContainerInstances < ActiveRecord::Migration[8.0]
  def change
    add_reference :devops_container_instances, :oauth_application, type: :uuid,
                  foreign_key: true, index: true
  end
end
