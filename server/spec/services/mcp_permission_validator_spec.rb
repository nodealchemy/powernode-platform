# frozen_string_literal: true

require 'rails_helper'

RSpec.describe McpPermissionValidator, type: :service do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, account: account, permissions: [ 'system.admin', 'ai.workflows.read' ]) }
  let(:account_user) { create(:user, account: account, permissions: [ 'ai.workflows.read' ]) }
  let(:public_user) { create(:user, account: account, permissions: []) }
  let(:mcp_server) { create(:mcp_server, account: account) }

  describe '#authorized?' do
    context 'with public permission level' do
      let(:tool) do
        create(:mcp_tool,
               mcp_server: mcp_server,
               permission_level: 'public',
               required_permissions: [],
               allowed_scopes: {})
      end

      it 'allows any user' do
        validator = described_class.new(tool: tool, user: public_user, account: account)
        expect(validator.authorized?).to be true
      end
    end

    context 'with account permission level' do
      let(:tool) do
        create(:mcp_tool,
               mcp_server: mcp_server,
               permission_level: 'account',
               required_permissions: [],
               allowed_scopes: {})
      end

      it 'allows account members' do
        validator = described_class.new(tool: tool, user: account_user, account: account)
        expect(validator.authorized?).to be true
      end

      it 'denies users from different accounts' do
        other_account = create(:account)
        other_user = create(:user, account: other_account)
        validator = described_class.new(tool: tool, user: other_user, account: account)
        expect(validator.authorized?).to be false
      end
    end

    context 'with admin permission level' do
      let(:tool) do
        create(:mcp_tool,
               mcp_server: mcp_server,
               permission_level: 'admin',
               required_permissions: [],
               allowed_scopes: {})
      end

      it 'allows admin users' do
        validator = described_class.new(tool: tool, user: admin_user, account: account)
        expect(validator.authorized?).to be true
      end

      it 'denies non-admin users' do
        validator = described_class.new(tool: tool, user: account_user, account: account)
        expect(validator.authorized?).to be false
      end
    end

    context 'with required permissions' do
      let(:tool) do
        create(:mcp_tool,
               mcp_server: mcp_server,
               permission_level: 'public',
               required_permissions: [ 'ai.workflows.read', 'ai.agents.execute' ],
               allowed_scopes: {})
      end

      it 'allows users with all required permissions' do
        user = create(:user, account: account, permissions: [ 'ai.workflows.read', 'ai.agents.execute' ])
        validator = described_class.new(tool: tool, user: user, account: account)
        expect(validator.authorized?).to be true
      end

      it 'denies users missing some permissions' do
        user = create(:user, account: account, permissions: [ 'ai.workflows.read' ])
        validator = described_class.new(tool: tool, user: user, account: account)
        expect(validator.authorized?).to be false
      end
    end

    context 'with allowed scopes' do
      let(:tool) do
        create(:mcp_tool,
               mcp_server: mcp_server,
               permission_level: 'public',
               required_permissions: [],
               allowed_scopes: {
                 'file_access' => [ 'read_files', 'list_directories' ],
                 'network' => [ 'http_get' ]
               })
      end

      it 'validates scope structure' do
        validator = described_class.new(tool: tool, user: public_user, account: account)
        expect(validator.authorized?).to be true
      end

      it 'rejects invalid scope categories' do
        tool.update(allowed_scopes: { 'invalid_category' => [ 'something' ] })
        validator = described_class.new(tool: tool, user: public_user, account: account)
        expect(validator.authorized?).to be false
      end
    end
  end

  describe '#authorization_result' do
    let(:tool) do
      create(:mcp_tool,
             mcp_server: mcp_server,
             permission_level: 'account',
             required_permissions: [ 'ai.workflows.read' ],
             allowed_scopes: { 'file_access' => [ 'read_files' ] })
    end

    it 'returns detailed authorization information' do
      validator = described_class.new(tool: tool, user: account_user, account: account)
      result = validator.authorization_result

      expect(result).to include(:authorized, :errors, :tool, :user)
      expect(result[:tool]).to include(:name, :permission_level, :required_permissions, :allowed_scopes)
      expect(result[:user]).to include(:permission_level, :permissions)
    end

    it 'includes error details when authorization fails' do
      user = create(:user, account: account, permissions: [])
      validator = described_class.new(tool: tool, user: user, account: account)
      result = validator.authorization_result

      expect(result[:authorized]).to be false
      expect(result[:errors]).not_to be_empty
      expect(result[:errors].first).to include(:type, :message, :missing, :required)
    end
  end

  describe '#scope_permitted?' do
    let(:tool) do
      create(:mcp_tool,
             mcp_server: mcp_server,
             allowed_scopes: {
               'file_access' => [ 'read_files', 'write_files' ],
               'network' => [ 'http_get' ]
             })
    end

    it 'returns true for permitted scopes' do
      validator = described_class.new(tool: tool, user: public_user, account: account)
      expect(validator.scope_permitted?(:file_access, :read_files)).to be true
      expect(validator.scope_permitted?(:file_access, :write_files)).to be true
      expect(validator.scope_permitted?(:network, :http_get)).to be true
    end

    it 'returns false for non-permitted scopes' do
      validator = described_class.new(tool: tool, user: public_user, account: account)
      expect(validator.scope_permitted?(:file_access, :delete_files)).to be false
      expect(validator.scope_permitted?(:network, :http_post)).to be false
    end

    it 'returns true when no scopes are defined (permissive)' do
      tool.update(allowed_scopes: {})
      validator = described_class.new(tool: tool, user: public_user, account: account)
      expect(validator.scope_permitted?(:file_access, :read_files)).to be true
    end
  end

  describe '#has_permission?' do
    it 'checks if user has a specific permission' do
      validator = described_class.new(tool: create(:mcp_tool, mcp_server: mcp_server),
                                     user: admin_user,
                                     account: account)

      expect(validator.has_permission?('system.admin')).to be true
      expect(validator.has_permission?('nonexistent.permission')).to be false
    end
  end

  describe 'TOOL_PERMISSION_SCOPES' do
    it 'defines all required scope categories' do
      expect(McpPermissionValidator::TOOL_PERMISSION_SCOPES.keys).to include(
        :file_access,
        :network,
        :data,
        :system,
        :ai
      )
    end

    it 'defines permissions for each category' do
      expect(McpPermissionValidator::TOOL_PERMISSION_SCOPES[:file_access]).to include(
        :read_files, :write_files, :delete_files, :list_directories
      )

      expect(McpPermissionValidator::TOOL_PERMISSION_SCOPES[:network]).to include(
        :http_get, :http_post, :external_api, :email_send, :webhook_call
      )

      expect(McpPermissionValidator::TOOL_PERMISSION_SCOPES[:data]).to include(
        :read_user_data, :read_account_data, :read_credentials, :read_pii
      )

      expect(McpPermissionValidator::TOOL_PERMISSION_SCOPES[:system]).to include(
        :execute_commands, :environment_access, :process_spawn
      )

      expect(McpPermissionValidator::TOOL_PERMISSION_SCOPES[:ai]).to include(
        :call_other_agents, :modify_workflow, :access_conversation_history
      )
    end
  end
end
