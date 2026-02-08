# frozen_string_literal: true

namespace :ai do
  namespace :todo_team do
    desc "Seed the Todo App AI team (agents, team, roles, channels, memory pool)"
    task seed: :environment do
      load Rails.root.join('db', 'seeds', 'ai_todo_team_seed.rb')
    end

    desc "Initialize the Todo App Gitea repository with scaffold files"
    task init_repo: :environment do
      account = Account.find_by(name: "Powernode Admin")
      unless account
        puts "Admin account not found"
        exit 1
      end

      puts "Initializing Todo App repository on Gitea..."
      result = Ai::ProjectInitializationService.new(account: account).call

      if result[:success]
        puts "Repository created: #{result.dig(:repository, :url) || result.dig(:repository, :name)}"
        puts "Files created: #{result[:files_created].join(', ')}"
      else
        puts "Failed: #{result[:error]}"
        exit 1
      end
    end

    desc "Full setup: seed team + initialize Gitea repo"
    task setup: :environment do
      Rake::Task['ai:todo_team:seed'].invoke
      Rake::Task['ai:todo_team:init_repo'].invoke
    end
  end
end
