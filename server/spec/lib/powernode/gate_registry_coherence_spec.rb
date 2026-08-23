# frozen_string_literal: true

require "rails_helper"
require "ripper"
require "tempfile"

# IMP-bc4cae11fe19 — the coherence guard for Powernode::GateRegistry, modelled
# on the system extension's action-category guard
# (extensions/system/server/spec/services/sdwan/executors/action_category_coherence_spec.rb).
#
# The registry records which SPECIES each human-approval gate mechanism is
# (:policy — may this CLASS of action run; :workflow — checkpoint inside ONE
# operation). A registry nothing enforces drifts within a week — the week
# before this landed minted ~90 gated actions and two gating seams — so this
# file holds core to the invariant:
#
#     every core class that touches a GATING PRIMITIVE is either a registered
#     gate mechanism or a recorded non-gate use, TOTALLY — anything else reds.
#
# The primitives are what any gate mechanism in this platform must bottom out
# in to gate anything:
#
#   * POLICY RESOLUTION    — Ai::InterventionPolicyService (the only reader of
#                            Ai::InterventionPolicy rows)
#   * OBLIGATION MINTING   — Ai::ApprovalChain.find_or_strengthen! and
#                            #create_request! (the only way to put something in
#                            front of an approver)
#
# A new gating seam that consults neither cannot resolve operator policy nor
# park anything on a human, so scanning the primitives reaches every mechanism
# — including one whose class name says nothing about gating. LEXED with
# Ripper, not grepped: a commented-out or string-literal mention is not a gate,
# and a guard that reds on comments gets deleted, which is worse than drift.
#
# SCOPE — the SOURCE SCAN is core only (server/app). Extension mechanisms
# (FleetAutonomyService#gate_action!, System::AdaptationGate, the
# StorageMigration approve/cutover checkpoints) register themselves at boot and
# need a sibling guard in the extension repo; this file cannot lex a tree it
# does not ship with. The registry-integrity examples (species vocabulary,
# entry-point existence) deliberately cover EVERY in-process entry, extension
# ones included once their engine is loaded — an extension may declare into
# core's registry, so core validates what was declared.
#
# KNOWN HOLES, recorded rather than pretended away:
#   * a primitive reached through a string-composed name
#     ("Ai::" + name).constantize, or a method name built at runtime, is
#     invisible to any lexer (name-keyed dispatch is invisible to a reference
#     grep). Symbol-form dispatch (public_send(:create_request!, ...)) IS
#     counted — see the scanner oracle below.
#   * Ai::InterventionPolicy ROWS could in principle be read directly
#     (account.ai_intervention_policies.where(...)) without naming the
#     resolution service const this file scans for; today the service is the
#     only reader, but nothing here enforces that direction.
RSpec.describe "Powernode::GateRegistry coherence", type: :lib do
  let(:app_root) { Rails.root.join("app") }

  # Token spellings of the gating primitives. The prefilter below is a raw
  # substring check and may only produce false positives — every hit is then
  # confirmed live by the lexer, so a comment or a string cannot red the guard,
  # and nothing the prefilter admits is trusted without lexing.
  let(:policy_primitive_consts) { %w[InterventionPolicyService].freeze }
  # create_approval_request!/build_approval_request are the belongs_to builders
  # Ai::DeferredOperation's approval_request association generates — a mint that
  # names neither chain primitive. (Ai::AutonomyGate's private method of the
  # same name is lexically indistinguishable; it is a registered mechanism, so
  # the census is satisfied either way.)
  let(:minting_primitive_idents) do
    %w[create_request! find_or_strengthen! create_approval_request! build_approval_request].freeze
  end
  let(:primitive_substrings) { policy_primitive_consts + minting_primitive_idents }

  # Non-gate uses of the primitives, RECORDED with their reason — the same
  # recorded-intent shape as the reference guard's composition_only list. A new
  # entry here is a reviewed decision that a primitive-touching class gates
  # nothing; an unregistered gate site has no line to write here that reads
  # honestly.
  let(:recorded_non_gate_uses) do
    {
      "app/services/ai/intervention_policy_service.rb" =>
        "IS the policy-resolution primitive",
      "app/models/ai/approval_chain.rb" =>
        "DEFINES the obligation-minting primitives",
      "app/controllers/api/v1/ai/intervention_policies_controller.rb" =>
        "CRUD over the policy rows plus a dry-run /resolve endpoint; gates nothing",
      "app/services/ai/agent_outreach_service.rb" =>
        "resolves policy to route/suppress NOTIFICATIONS (block drops the message); " \
        "parks nothing on an approver"
    }
  end

  # ---- Ripper scan -----------------------------------------------------------

  # Live (executable) primitive references in one file: constants via on_const,
  # method calls via on_ident. Comments and string content never lex as either,
  # so only code that can RUN counts. Symbol literals (:create_request!) COUNT
  # deliberately: public_send(:create_request!, ...) is a live gate call, and
  # excluding symbols would bless exactly that evasion. The cost is a
  # respond_to?/method(...) mention demanding registration or a recorded
  # reason — which is the guard's design, not a false positive.
  def live_primitive_refs(path)
    Ripper.lex(File.read(path)).filter_map do |(_pos, type, tok, _state)|
      case type
      when :on_const then tok if policy_primitive_consts.include?(tok)
      when :on_ident then tok if minting_primitive_idents.include?(tok)
      end
    end.uniq
  end

  # Every core file with a live primitive reference. Prefilter by substring
  # (false positives only), confirm with the lexer.
  let(:primitive_files) do
    Dir[app_root.join("**/*.rb").to_s].sort.each_with_object({}) do |path, acc|
      raw = File.read(path)
      next unless primitive_substrings.any? { |s| raw.include?(s) }

      refs = live_primitive_refs(path)
      acc[Pathname.new(path).relative_path_from(Rails.root).to_s] = refs if refs.any?
    end
  end

  let(:core_entries) { Powernode::GateRegistry.core_entries }

  # Source file of each registered core mechanism, resolved from the constant
  # itself (never guessed from the name) so a moved file cannot desynchronise
  # the guard from the registry.
  let(:mechanism_files) do
    core_entries.to_h do |entry|
      entry.mechanism.constantize # force the autoload, else const_source_location
      # reports Zeitwerk's autoload shim (zeitwerk/cref.rb) instead of the source
      location = Object.const_source_location(entry.mechanism)
      raise "registered mechanism #{entry.mechanism} has no source location" if location.nil?

      [ Pathname.new(location.first).relative_path_from(Rails.root).to_s, entry ]
    end
  end

  # ---- The invariant ---------------------------------------------------------

  it "registers every core class that touches a gating primitive, or records why it is not a gate" do
    unaccounted = primitive_files.keys - mechanism_files.keys - recorded_non_gate_uses.keys

    expect(unaccounted).to be_empty,
                           "#{unaccounted.size} core file(s) touch a gating primitive " \
                           "(#{unaccounted.map { |f| "#{f} [#{primitive_files[f].join(', ')}]" }.join('; ')}) " \
                           "but are neither registered in Powernode::GateRegistry nor recorded here as a " \
                           "non-gate use — declare the mechanism's species, or record the reason it gates nothing"
  end

  it "keeps the recorded non-gate list disjoint from the registry and free of stale entries" do
    expect(recorded_non_gate_uses.keys & mechanism_files.keys).to be_empty,
                                                                  "a file cannot be both a registered gate mechanism and a recorded non-gate use"

    stale = recorded_non_gate_uses.keys.reject { |f| primitive_files.key?(f) }
    expect(stale).to be_empty,
                     "recorded non-gate entries no longer touch any gating primitive (or the file is gone) — " \
                     "remove them so the list stays a census, not a fossil: #{stale.join(', ')}"
  end

  it "backs every registered core mechanism with a primitive reference or a declared delegation it actually makes" do
    mechanism_files.each do |file, entry|
      if entry.delegates_to
        expect(Powernode::GateRegistry.registered?(entry.delegates_to))
          .to be(true), "#{entry.mechanism} delegates_to #{entry.delegates_to}, which is not registered"

        delegate_const = entry.delegates_to.split("::").last
        consts = Ripper.lex(File.read(Rails.root.join(file)))
                       .select { |(_p, type, _t, _s)| type == :on_const }.map { |t| t[2] }
        expect(consts).to include(delegate_const),
                          "#{entry.mechanism} declares delegates_to #{entry.delegates_to} but its source " \
                          "never names #{delegate_const} — the declared delegation is fiction"
      else
        expect(primitive_files).to have_key(file),
                                   "#{entry.mechanism} is registered as a gate mechanism but #{file} touches no " \
                                   "gating primitive — either it delegates (declare delegates_to) or it is not a gate"
      end
    end
  end

  it "declares a valid species and real entry points on every registered mechanism" do
    expect(Powernode::GateRegistry::SPECIES).to contain_exactly(:policy, :workflow)

    Powernode::GateRegistry.entries.each do |entry|
      expect(Powernode::GateRegistry::SPECIES).to include(entry.species),
                                                  "#{entry.mechanism} declares unknown species #{entry.species.inspect}"

      klass = entry.mechanism.constantize
      entry.entry_points.each do |ep|
        defined = klass.respond_to?(ep) ||
                  (klass.respond_to?(:method_defined?) &&
                   (klass.method_defined?(ep) || klass.private_method_defined?(ep)))
        expect(defined).to be(true),
                           "#{entry.mechanism} declares entry point ##{ep}, which does not exist — " \
                           "the registry names a gate nobody can call"
      end
    end
  end

  # Review finding (round 1) — the minting primitives are the only sanctioned
  # way to put something in front of an approver, but Ruby does not enforce
  # that: writing Ai::ApprovalRequest rows directly mints an approver-facing
  # row while lexing neither primitive ident. This census closes that bypass:
  # the ONLY core file allowed to pair the ApprovalRequest const (or its
  # associations) with a writer anywhere in the dotted chain is the chain
  # model that defines create_request!. The belongs_to builders are covered by
  # the PRIMARY census above (they are in minting_primitive_idents).
  # `let`, not constants — a bare constant assigned inside a describe block
  # lands on Object (the duplicate-constant clobber the reference guard warns
  # about).
  let(:mint_writer_idents) do
    %w[
      create create! new build first_or_create first_or_create!
      find_or_create_by find_or_create_by! create_or_find_by create_or_find_by!
      find_or_initialize_by insert insert! insert_all insert_all! upsert upsert_all
    ].freeze
  end

  let(:mint_receivers) do
    { const: %w[ApprovalRequest], ident: %w[ai_approval_requests approval_requests] }.freeze
  end

  let(:group_openers) { %i[on_lparen on_lbracket on_lbrace on_embexpr_beg].freeze }
  let(:group_closers) { %i[on_rparen on_rbracket on_rbrace on_embexpr_end].freeze }

  # True iff the source pairs an ApprovalRequest receiver with a writer method
  # reachable through its dotted chain — `X.create!`, `X::create!`, `X&.create!`,
  # `X.where(...).first_or_create!`, `X << row` all count; readers (`X.map`,
  # `X.find_by`) do not. Chain-walked with paren-depth tracking so an argument
  # list cannot hide or fake a writer at the chain's own level.
  def direct_mint?(raw)
    tokens = Ripper.lex(raw).reject { |(_p, type, _t, _s)| %i[on_sp on_nl on_ignored_nl on_comment].include?(type) }

    tokens.each_with_index.any? do |(_pos, type, tok, _state), idx|
      receiver = (type == :on_const && mint_receivers[:const].include?(tok)) ||
                 (type == :on_ident && mint_receivers[:ident].include?(tok))
      receiver && chain_reaches_writer?(tokens, idx + 1)
    end
  end

  def chain_reaches_writer?(tokens, start)
    j = start
    while j < tokens.size
      type, val = tokens[j][1], tokens[j][2]
      if group_openers.include?(type)
        depth = 1
        j += 1
        while j < tokens.size && depth.positive?
          depth += 1 if group_openers.include?(tokens[j][1])
          depth -= 1 if group_closers.include?(tokens[j][1])
          j += 1
        end
      elsif type == :on_period || (type == :on_op && [ "::", "&." ].include?(val))
        j += 1
      elsif type == :on_op && val == "<<"
        return true
      elsif type == :on_ident
        return true if mint_writer_idents.include?(val)

        j += 1
      elsif type == :on_const
        j += 1
      else
        return false
      end
    end
    false
  end

  it "mints approver-facing rows only through the chain primitives, never directly" do
    minting_owners = [ "app/models/ai/approval_chain.rb" ]

    hits = Dir[app_root.join("**/*.rb").to_s].sort.filter_map do |path|
      raw = File.read(path)
      next unless raw.include?("ApprovalRequest") || raw.include?("approval_requests")

      Pathname.new(path).relative_path_from(Rails.root).to_s if direct_mint?(raw)
    end

    offenders = hits - minting_owners
    expect(offenders).to be_empty,
                         "core file(s) create Ai::ApprovalRequest rows directly, bypassing the chain " \
                         "primitives this guard scans for — route through ApprovalChain#create_request! " \
                         "(or register the new mechanism AND teach this census): #{offenders.join(', ')}"

    # The allowlist must stay LOAD-BEARING: approval_chain.rb's own association
    # write must trip the matcher, or a refactor of it leaves this example
    # green vacuously — the census-not-fossil rule recorded_non_gate_uses
    # already lives by.
    expect(minting_owners - hits).to be_empty,
                                     "minting_owners entries no longer trip the direct-mint matcher — " \
                                     "remove them or the census is vacuous: #{(minting_owners - hits).join(', ')}"
  end

  # The direct-mint matcher's own oracle — each evasion shape round 2 named,
  # plus the reader shapes that must stay ignored.
  it "sees a direct mint whatever shape its chain takes, and flags no reader" do
    [
      'Ai::ApprovalRequest.create!(account: a)',
      'Ai::ApprovalRequest::create!(account: a)',
      'approval_requests&.create!(account: a)',
      'Ai::ApprovalRequest.where(status: "pending").first_or_create!',
      'account.ai_approval_requests.insert_all(rows)',
      'chain.approval_requests << request',
      "Ai::ApprovalRequest\n  .create!(account: a)"
    ].each do |shape|
      expect(direct_mint?(shape)).to be(true), "mint shape not caught: #{shape.inspect}"
    end

    [
      'approval_requests.map(&:id)',
      'Ai::ApprovalRequest.where(status: "pending").count',
      'approval_requests.find_by(id: x)',
      '# Ai::ApprovalRequest.create!(account: a)',
      'msg = "Ai::ApprovalRequest.create! is forbidden"',
      'errors.build(field)'
    ].each do |shape|
      expect(direct_mint?(shape)).to be(false), "reader shape falsely flagged: #{shape.inspect}"
    end
  end

  # ---- The scanner's own oracle ---------------------------------------------
  # Everything above trusts live_primitive_refs; a scanner that quietly returns
  # nothing is indistinguishable from a clean tree. Each shape a drifting or
  # spoofing site could take is exercised against constructed source.
  it "sees a live primitive whatever shape it takes, and is not fooled by dead ones" do
    scan = lambda do |source|
      Tempfile.create([ "gate_scan", ".rb" ]) do |f|
        f.write(source)
        f.flush
        live_primitive_refs(f.path)
      end
    end

    expect(scan.call('svc = ::Ai::InterventionPolicyService.new(account: a)')).to eq(%w[InterventionPolicyService])
    expect(scan.call("chain.create_request!(source_type: t)")).to eq(%w[create_request!])
    expect(scan.call("Ai::ApprovalChain.find_or_strengthen!(account: a)")).to eq(%w[find_or_strengthen!])
    expect(scan.call("x = klass.public_send(:create_request!, a)")).to eq(%w[create_request!]) # symbol dispatch is live
    expect(scan.call("# chain.create_request!(source_type: t)")).to eq([])
    expect(scan.call('msg = "InterventionPolicyService rejected it"')).to eq([])
  end

  # ---- Vacuity floors --------------------------------------------------------
  # Every example above is a "reject the bad ones" shape, which empty inputs
  # satisfy. Floors are the current counts, so a scan that silently reads
  # nothing cannot go green.
  it "reads real inputs on every surface it claims to guard" do
    expect(primitive_files.size).to be >= 11
    expect(mechanism_files.size).to eq(core_entries.size) # two mechanisms sharing a file would silently drop a reverse check
    expect(core_entries.size).to be >= 8
    expect(Powernode::GateRegistry.for_species(:policy).size).to be >= 4
    expect(Powernode::GateRegistry.for_species(:workflow).size).to be >= 4
    expect(recorded_non_gate_uses.keys).to all(satisfy("exist on disk") { |f| Rails.root.join(f).file? })
  end
end
