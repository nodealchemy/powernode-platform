# frozen_string_literal: true

module Ai
  class ProjectInitializationService
    attr_reader :account, :repo_name, :description, :organization, :private

    def initialize(account:, repo_name: 'todo-app', description: nil, organization: nil, private: true)
      @account = account
      @repo_name = repo_name
      @description = description || 'Full-stack Todo/Task application built by an AI agent team'
      @organization = organization
      @private = private
    end

    def call
      credential = find_gitea_credential
      return { success: false, error: 'No active Gitea credential found' } unless credential

      client = Devops::Git::ApiClient.for(credential)

      repo = create_repository(client)
      return repo unless repo[:success] != false

      # Extract owner from API response — credential name may not match Gitea username
      owner = repo.dig("owner", "login") || credential.credentials['username'] || credential.name
      files = create_initial_files(client, owner)

      {
        success: true,
        repository: {
          name: repo_name,
          url: repo.dig(:clone_url) || repo.dig('clone_url'),
          default_branch: 'master'
        },
        files_created: files
      }
    end

    private

    def find_gitea_credential
      gitea_provider = Devops::GitProvider.find_by(provider_type: 'gitea')
      return nil unless gitea_provider

      account.git_provider_credentials
             .where(git_provider_id: gitea_provider.id, is_active: true)
             .order(is_default: :desc, created_at: :desc)
             .first
    end

    def create_repository(client)
      options = {
        description: description,
        private: self.private,
        auto_init: true,
        default_branch: 'master'
      }

      if organization.present?
        client.create_org_repository(organization, repo_name, **options)
      else
        client.create_repository(repo_name, **options)
      end
    end

    def create_initial_files(client, owner)
      files = []

      readme_content = <<~MD
        # Todo App

        A full-stack Todo/Task application built by an AI agent team.

        ## Tech Stack

        - **Backend**: Rails 8 API, PostgreSQL, UUIDv7 primary keys, JWT auth
        - **Frontend**: React 18, TypeScript, Tailwind CSS
        - **Testing**: RSpec (backend), Jest + React Testing Library (frontend)
        - **DevOps**: Gitea CI/CD, Docker

        ## Team

        | Role | Agent | Provider | Model |
        |------|-------|----------|-------|
        | Team Lead | Todo Team Lead | Anthropic | claude-sonnet-4 |
        | Backend Dev | Todo Backend Developer | Anthropic | claude-haiku-4.5 |
        | Frontend Dev | Todo Frontend Developer | X.AI | grok-3-mini-fast |
        | QA Engineer | Todo QA Engineer | OpenAI | gpt-4o-mini |
        | DevOps & Docs | Todo DevOps & Docs | OpenAI | gpt-4o-mini |

        ## Getting Started

        ```bash
        # Backend
        cd server && bundle install && rails db:setup && rails s

        # Frontend
        cd frontend && npm install && npm start
        ```

        ## Project Structure

        ```
        todo-app/
        ├── server/          # Rails API backend
        ├── frontend/        # React TypeScript frontend
        ├── docs/            # Project documentation
        └── docker-compose.yml
        ```
      MD

      gitignore_content = <<~GI
        # Ruby / Rails
        *.gem
        *.rbc
        .bundle
        .config
        coverage
        log/*.log
        tmp/
        vendor/bundle
        .byebug_history

        # Node / React
        node_modules/
        build/
        .env
        .env.local
        .env.*.local
        npm-debug.log*
        yarn-debug.log*
        yarn-error.log*

        # IDE
        .idea/
        .vscode/
        *.swp
        *.swo
        *~

        # OS
        .DS_Store
        Thumbs.db
      GI

      architecture_content = <<~MD
        # Architecture

        ## API Endpoints

        ### Todos
        | Method | Path | Description |
        |--------|------|-------------|
        | GET | /api/v1/todos | List all todos |
        | POST | /api/v1/todos | Create a todo |
        | GET | /api/v1/todos/:id | Get a todo |
        | PATCH | /api/v1/todos/:id | Update a todo |
        | DELETE | /api/v1/todos/:id | Delete a todo |

        ## Data Model

        ### Todo
        | Column | Type | Notes |
        |--------|------|-------|
        | id | uuid | UUIDv7 primary key |
        | title | string | Required, max 255 |
        | description | text | Optional |
        | status | enum | pending, in_progress, completed |
        | priority | enum | low, medium, high |
        | due_date | datetime | Optional |
        | account_id | uuid | Foreign key |
        | user_id | uuid | Foreign key (creator) |
        | created_at | datetime | |
        | updated_at | datetime | |

        ## Component Tree

        ```
        App
        ├── TodoListPage
        │   ├── TodoFilters
        │   ├── TodoList
        │   │   └── TodoItem
        │   └── TodoPagination
        ├── TodoDetailPage
        │   └── TodoForm
        └── TodoCreatePage
            └── TodoForm
        ```
      MD

      tasks_content = <<~MD
        # Task Breakdown

        ## Phase 1: Backend API
        - [ ] Create Todo model with migration
        - [ ] Create TodosController with CRUD endpoints
        - [ ] Add request validation and error handling
        - [ ] Add pagination and filtering

        ## Phase 2: Frontend UI
        - [ ] Create TodoList component
        - [ ] Create TodoItem component
        - [ ] Create TodoForm component (create/edit)
        - [ ] Add filtering and search UI
        - [ ] Wire up API calls with fetch/axios

        ## Phase 3: Testing
        - [ ] Write RSpec request specs for TodosController
        - [ ] Write model specs for Todo
        - [ ] Write Jest tests for TodoList
        - [ ] Write Jest tests for TodoForm

        ## Phase 4: DevOps
        - [ ] Create Dockerfile for backend
        - [ ] Create Dockerfile for frontend
        - [ ] Create docker-compose.yml
        - [ ] Set up Gitea CI pipeline
      MD

      [
        { path: 'README.md', content: readme_content, message: 'docs: add project README' },
        { path: '.gitignore', content: gitignore_content, message: 'chore: add .gitignore' },
        { path: 'docs/ARCHITECTURE.md', content: architecture_content, message: 'docs: add architecture overview' },
        { path: 'docs/TASKS.md', content: tasks_content, message: 'docs: add initial task breakdown' }
      ].each do |file|
        result = client.create_file(owner, repo_name, file[:path], file[:content], message: file[:message])
        files << file[:path] if result[:success] != false
      end

      files
    end
  end
end
