# frozen_string_literal: true

require "rails_helper"

# IMP-01a08b8e. The :user factory's role traits clear the user's roles and then
# call User#add_role(name), which returns FALSE for a name that is not a role —
# it does not raise. Two traits named roles that do not exist (`billing_admin`,
# registered by the business extension as `business.billing_admin`; and
# `system_admin`, which exists nowhere), so each yielded a user with ZERO roles.
# A spec built on one gets a refusal from every gate for the wrong reason, and
# its "the gate refuses" examples pass whether or not the gate works.
#
# role_name_literal_spec cannot see this: it scans app/ and lib/, not spec/.
# And a literal scan would only catch the spelling; this builds every trait and
# checks what it actually produces, so it also covers a trait that names a real
# role through a variable, or one a later edit breaks some other way.
RSpec.describe "User factory role traits", type: :lint do
  let(:account) { create(:account) }
  # The authority, as in role_name_literal_spec: all_roles, so a role an
  # extension registers at engine init counts as real.
  let(:known_role_keys) { ::Permissions.all_roles.keys.map(&:to_s).to_set }

  let(:trait_names) do
    names = FactoryBot.factories[:user].definition.defined_traits.map(&:name).map(&:to_s).sort
    # Guard against a vacuous pass if the internals this reads ever change shape.
    expect(names).to include("owner", "member")
    names
  end

  it "leaves no trait yielding a user with zero roles" do
    create(:user, account: account) # take the first-user owner default out of play

    zero_role = trait_names.select do |trait|
      create(:user, trait.to_sym, account: account).reload.roles.empty?
    end

    expect(zero_role).to be_empty, <<~MSG
      These :user factory traits produce a user with NO roles: #{zero_role.join(', ')}.
      A zero-role actor is refused by every gate, so a spec's "refused" examples
      pass for that reason alone. Name a role that exists (#{known_role_keys.to_a.sort.first(5).join(', ')}, ...)
      or, for a genuinely permissionless actor, use `permissions: []` explicitly.
    MSG
  end

  it "gives each role-named trait exactly that role" do
    role_traits = trait_names.select { |t| known_role_keys.include?(t) }
    expect(role_traits).to include("owner", "admin", "member")

    role_traits.each do |trait|
      user = create(:user, trait.to_sym, account: account).reload
      expect(user.roles.map(&:name)).to eq([ trait ]), "trait :#{trait} produced #{user.roles.map(&:name).inspect}"
    end
  end

  # THE OTHER ARM. The traits raise when their role is missing rather than
  # returning a zero-role user; without this example, a trait that went back to
  # `add_role(name)` alone would still pass the two examples above for as long
  # as its role happens to exist.
  it "raises, rather than yielding a zero-role user, when a trait's role is missing" do
    allow(Role).to receive(:find_by).and_call_original
    allow(Role).to receive(:find_by).with(name: "member").and_return(nil)

    expect { create(:user, :member, account: account) }.to raise_error(ArgumentError, /member/)
  end
end
