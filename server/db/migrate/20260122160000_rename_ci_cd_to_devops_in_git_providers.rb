# frozen_string_literal: true

class RenameCiCdToDevopsInGitProviders < ActiveRecord::Migration[8.0]
  def change
    rename_column :git_providers, :supports_ci_cd, :supports_devops
    rename_column :git_providers, :ci_cd_config, :devops_config
  end
end
