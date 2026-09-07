# frozen_string_literal: true

require "rails_helper"

# IMP-e85001682ade — Role#name compared against a literal that names no role.
#
# Role#name holds the canonical lowercase KEY ("owner"); Role#display_name holds
# the human form ("Account Owner"). Four sites compared `name` against a display
# form or an invented dotted string, so the comparison was false for every role
# that exists:
#
#   Accounts::DelegationService  role.name == "Owner"                 x3
#   Account::Delegation          role&.name == "Admin" || == "Owner"
#   Account#broadcast_customer_change  name IN ("system.admin","account.manager")
#
# WHY A LINT AND NOT JUST THE FIXES. Three of those were harmless — a capability
# that always answers false, a broadcast that reaches nobody — and one was an
# AUTHORIZATION HOLE, because it was a REFUSAL that never refused: "Cannot
# delegate Owner role" let the owner role be delegated. The defect is invisible
# by construction (a false comparison looks exactly like a passing guard) and
# recurs whenever someone types a role name from memory. It needs a detector,
# not four patches.
#
# COMPARED AGAINST THE KEYS, and against all_roles rather than ROLES: an
# extension may register roles at engine-init (config/permissions.rb #all_roles
# merges @extension_roles), and a core lint that ignored them would fail on a
# legitimate extension role name.
RSpec.describe "Role#name literals name a real role", type: :lint do
  # The authority. Not a hardcoded list — that would be the same defect one
  # level up.
  let(:known_role_keys) { ::Permissions.all_roles.keys.map(&:to_s).to_set }

  let(:app_root) { File.expand_path("../../app", __dir__) }
  let(:lib_root) { File.expand_path("../../lib", __dir__) }

  let(:ruby_sources) do
    files = (Dir.glob(File.join(app_root, "**", "*.rb")) + Dir.glob(File.join(lib_root, "**", "*.rb"))).sort
    expect(files).not_to be_empty,
      "scanned no Ruby sources under #{app_root} — this lint would pass vacuously"
    files
  end

  # Quote-agnostic throughout: .rubocop.yml inherits rubocop-rails-omakase,
  # which does not enforce double quotes, so a single-quoted literal is exactly
  # as likely and was invisible to the first version of this lint.
  Q = /["']/.freeze

  # RECEIVER-CONSTRAINED, and this matters more than it looks. An unanchored
  # /\.name\s*==\s*"…"/ matches ANY receiver — the first `adapter.name ==
  # "apt"` or `provider.name == "openai"` added under app/ would fail this gate
  # with the message "no such role key", and a lint that cries wolf gets
  # deleted. Restricted to receivers that are a role: `role`, `@role`,
  # `user_role`, `roles.first`, `Role`, etc.
  ROLE_RECEIVER = /(?:^|[^\w.])(?:[\w@]*_?[Rr]ole[\w]*)/.freeze
  COMPARISON_RX = /#{ROLE_RECEIVER}(?:&\.|\.)name\s*[=!]=\s*#{Q}([A-Za-z][\w.]*)#{Q}/.freeze

  # The SQL spellings. `roles: { name: … }` is the join form; `find_by`/`where`
  # with a bare `name:` on a Role scope is the other live spelling in this tree
  # and was missed by the first version.
  SQL_SCALAR_RX = /roles:\s*\{\s*name:\s*#{Q}([A-Za-z][\w.]*)#{Q}/.freeze
  SQL_ARRAY_RX  = /roles:\s*\{\s*name:\s*(?:%w\[([^\]]*)\]|\[([^\]]*)\])/.freeze
  ROLE_LOOKUP_RX = /\bRole(?:\.\w+)*\.(?:find_by|find_by!|where)\(\s*name:\s*#{Q}([A-Za-z][\w.]*)#{Q}/.freeze

  # A `#`-to-end-of-line strip is not enough: a `#` inside a string literal
  # earlier on the line would truncate real code. Only blank a comment that
  # starts the line (after whitespace), which is where every false positive in
  # this tree actually lives.
  def strip_comments(src)
    src.gsub(/^\s*#.*$/, "")
  end

  it "compares Role#name only against keys that exist" do
    violations = []

    ruby_sources.each do |path|
      rel = path.delete_prefix("#{File.expand_path('../..', __dir__)}/")
      src = strip_comments(File.read(path))

      src.scan(COMPARISON_RX).flatten.each do |literal|
        next if known_role_keys.include?(literal)
        violations << "#{rel}: `.name == #{literal.inspect}` — no such role key"
      end

      src.scan(SQL_SCALAR_RX).flatten.each do |literal|
        next if known_role_keys.include?(literal)
        violations << "#{rel}: `roles: { name: #{literal.inspect} }` — no such role key"
      end

      src.scan(ROLE_LOOKUP_RX).flatten.each do |literal|
        next if known_role_keys.include?(literal)
        violations << "#{rel}: `Role.find_by(name: #{literal.inspect})` — no such role key"
      end

      src.scan(SQL_ARRAY_RX).each do |percent_w, bracketed|
        names = percent_w ? percent_w.split : bracketed.to_s.scan(/"([^"]*)"/).flatten
        names.reject { |n| known_role_keys.include?(n) }.each do |literal|
          violations << "#{rel}: `roles: { name: [... #{literal.inspect} ...] }` — no such role key"
        end
      end
    end

    expect(violations).to be_empty, <<~MSG
      Role#name is compared against #{violations.size} literal(s) that name no role:

      #{violations.join("\n")}

      Role#name holds the canonical KEY (#{known_role_keys.to_a.sort.first(4).join(', ')}, ...);
      the human form lives in Role#display_name. A comparison against a display
      form or an invented dotted name is false for every row, which is silent —
      and when the comparison guards a REFUSAL it fails OPEN. That is exactly
      how "Cannot delegate Owner role" came to never refuse anything.

      Use the canonical key (Role::OWNER exists for the commonest one), or
      display_name if you genuinely meant the human string.
    MSG
  end

  # THE DETECTOR MUST DETECT. Without this, a regex that silently stopped
  # matching would leave the example above green forever — the failure mode is
  # not hypothetical, it is what the scanned code did.
  it "flags each of the shapes it claims to catch, in both quote styles" do
    sample = <<~RUBY_SRC
      if role&.name == "Owner"
      end
      if @user_role.name != 'Admin'
      end
      User.joins(:roles).where(roles: { name: "system.admin" })
      User.joins(:roles).where(roles: { name: 'account.manager' })
      User.joins(:roles).where(roles: { name: [ "account.manager", "owner" ] })
      Role.find_by(name: "Owner")
      Role.global.where(name: 'account.owner')
    RUBY_SRC

    expect(sample.scan(COMPARISON_RX).flatten).to contain_exactly("Owner", "Admin")
    expect(sample.scan(SQL_SCALAR_RX).flatten).to contain_exactly("system.admin", "account.manager")
    expect(sample.scan(ROLE_LOOKUP_RX).flatten).to contain_exactly("Owner", "account.owner")

    array_names = sample.scan(SQL_ARRAY_RX).flat_map { |pw, br| pw ? pw.split : br.to_s.scan(/["']([^"']*)["']/).flatten }
    expect(array_names).to include("account.manager", "owner")
    # ...and the live key in that array is NOT reported, so the lint narrows to
    # the dead entry rather than condemning the whole call site.
    expect(array_names.reject { |n| known_role_keys.include?(n) }).to eq([ "account.manager" ])
  end

  # THE FALSE-POSITIVE ARM, which is what keeps this lint alive. An unanchored
  # `.name ==` matches every receiver in the app; the first adapter, provider or
  # file compared by name would fail the gate with "no such role key", and a
  # gate that cries wolf gets deleted rather than obeyed.
  it "ignores a name comparison on something that is not a role" do
    sample = <<~RUBY_SRC
      adapter.name == "apt"
      provider.name == 'openai'
      uploaded_file.name == "manifest.json"
      Module.const_get(x).name == "System::Task"
    RUBY_SRC

    expect(sample.scan(COMPARISON_RX).flatten).to be_empty
  end

  it "does not mistake a comment for code" do
    expect(strip_comments(%(  # role.name == "Owner"\n))).not_to match(COMPARISON_RX)
    # A `#` inside a string must NOT truncate the line — that would hide real
    # comparisons rather than merely tolerate them.
    expect(strip_comments(%(x = "a#b"; role.name == "Owner"\n))).to match(COMPARISON_RX)
  end
end
