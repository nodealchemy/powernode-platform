# frozen_string_literal: true

require "spec_helper"

# Core-purity guard (IMP-7305ac6b6a75): billing is not a core concern.
#
# server/lib/tasks/billing.rake was dead code — zero invokers anywhere in the repo,
# and every task raised NameError because it referenced billing job/model constants
# that are not defined in core (they are owned and scheduled outside core entirely).
# This guards against re-introducing a billing rake task into core. Deliberately
# Rails-free (file inspection only) so it stays fast.
RSpec.describe "core lib/tasks billing purity" do
  core_tasks_dir = File.expand_path("../../../lib/tasks", __dir__)

  it "ships no billing rake task in core (billing is owned outside core)" do
    billing_rakes = Dir[File.join(core_tasks_dir, "*billing*.rake")]
    expect(billing_rakes).to be_empty,
           "core must not ship billing rake tasks — billing is owned outside core; found: #{billing_rakes.inspect}"
  end
end
