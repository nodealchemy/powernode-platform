# frozen_string_literal: true

module Ai
  module Campaigns
    # The one answer to "may this user read or change campaigns and campaign proposals in
    # THIS account?". Both REST doors gate every action on it, and the services behind the
    # mutating ones (CampaignDriver, Ai::CampaignProposal) ask it again, so every door
    # inherits the check.
    #
    # The permission is answered for the account whose campaign or proposal the call
    # touches, from the user's OWN roles there. An account-switch session carries
    # permissions DELEGATED from another account (Authentication#has_permission? answers
    # from that delegation), while the campaign doors resolve records in the user's own
    # account; a door that asked has_permission? therefore acted on the own account under
    # another account's grant. A delegation is never consulted here, and a record in any
    # account other than the user's is refused.
    module Authorization
      MANAGE_PERMISSION = "ai.campaigns.manage"
      READ_PERMISSION = "ai.campaigns.read"

      class Refused < StandardError; end

      # A caller with no human user names its principal instead of passing nil
      # (IMP-a658fc220367). A record principal (an Ai::Agent, or an instance principal's
      # node instance: anything carrying account_id) must belong to the account touched. A
      # system principal is an in-process caller with no record to compare, so it must be
      # one DECLARED here; an undeclared name is refused.
      SystemPrincipal = Data.define(:name)
      DISCOVERY = SystemPrincipal.new(name: "campaign_discovery")
      INTERNAL = SystemPrincipal.new(name: "internal_tool_call")
      SYSTEM_PRINCIPALS = [ DISCOVERY, INTERNAL ].freeze

      module_function

      def permitted?(user:, account:, permission: MANAGE_PERMISSION)
        return false if user.nil? || account.nil?
        return false unless user.account_id == account.id

        user.has_permission?(permission)
      end

      def authorize!(user:, account:, permission: MANAGE_PERMISSION)
        return if permitted?(user: user, account: account, permission: permission)

        who = user ? "user #{user.id}" : "a caller with no user"
        raise Refused, "#{who} does not hold '#{permission}' in account #{account&.id}"
      end

      # For services an agent or instance principal also reaches. A call that names a user
      # is asked for the permission. A call with no user must name its principal, and the
      # principal is asserted rather than trusted to have been bound by some door.
      def authorize_actor!(user:, account:, permission: MANAGE_PERMISSION, principal: nil)
        return authorize!(user: user, account: account, permission: permission) if user
        raise Refused, "a caller with no user must name its principal (account #{account&.id})" if principal.nil?

        if principal.is_a?(SystemPrincipal)
          # By identity: a Data value rebuilt with a declared name compares equal.
          return if account && SYSTEM_PRINCIPALS.any? { |declared| declared.equal?(principal) }

          raise Refused, "system principal #{principal.name.inspect} is not a declared campaign caller"
        end

        # These carry account_id too but are not principals: a user belongs in user: (where
        # it is asked for the permission), and a campaign or proposal of the account touched
        # would match by construction.
        if principal.is_a?(::User) || principal.is_a?(::Ai::Campaign) || principal.is_a?(::Ai::CampaignProposal)
          raise Refused, "#{principal.class.name} is not a campaign principal; pass a user as user:"
        end

        return if account && principal.respond_to?(:account_id) && principal.account_id == account.id

        raise Refused, "#{principal.class.name} principal #{principal.try(:id)} is not bound to account #{account&.id}"
      end
    end
  end
end
