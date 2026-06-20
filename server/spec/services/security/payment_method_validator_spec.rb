# frozen_string_literal: true

# Characterization spec for Security::PaymentMethodValidator.
#
# CHARACTERIZATION ONLY: these examples document the validator's CURRENT behavior
# (risk scoring, recommendation thresholds, and the boolean validity flags each
# sub-check returns), not what it "should" do. See the NOTE comments for behaviors
# that are surprising but pinned as-is — including a significant gap: this validator
# performs NO real card validation (no Luhn, no expiry enforcement, no CVV-format
# check); it only reasons over provider-supplied risk metadata.
#
# SAFETY:
#   * No network. The only "external" surfaces the validator touches are:
#       - account.payment_methods / account.payments (ActiveRecord relations)
#       - Account.joins(...) (device-velocity query)
#       - AuditLog.log_action (audit sink)
#       - detect_country_from_ip / vpn_or_proxy_detected? / suspicious_device?
#         (in-process stubs in the service; no I/O)
#     Every one of these is STUBBED below so no DB-relation/network call is made
#     for the data-source-driven branches, and the audit write is intercepted.
#   * Card numbers: only the well-known PUBLIC test PANs appear anywhere in this
#     file (Visa 4242424242424242, invalid-Luhn 4242424242424241, Amex test
#     378282246310005). These are vendor test numbers, never a real PAN. The
#     validator itself never inspects the PAN — they are present only to make the
#     fixtures realistic and to document that they flow through untouched.
#   * Nothing here prints, logs, or otherwise emits card data or secrets.

require "rails_helper"

RSpec.describe Security::PaymentMethodValidator do
  # Well-known PUBLIC test card numbers (vendor test PANs — NOT real cards).
  VISA_TEST_PAN          = "4242424242424242"  # valid Luhn
  VISA_TEST_PAN_BAD_LUHN = "4242424242424241"  # fails Luhn
  AMEX_TEST_PAN          = "378282246310005"   # valid Luhn

  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }

  # A fully "clean" card payload: domestic, credit funding, all provider checks
  # passing, no provider risk_level. Drives the all-green path.
  def clean_card_data(overrides = {})
    {
      "type" => "card",
      "provider" => "stripe",
      "card" => {
        "number" => VISA_TEST_PAN,   # present only for realism; validator ignores it
        "brand" => "visa",
        "country" => "US",
        "funding" => "credit",
        "checks" => {
          "cvc_check" => "pass",
          "address_line1_check" => "pass",
          "address_postal_code_check" => "pass"
        }
      }
    }.deep_merge(overrides)
  end

  # Fake AR-relation-ish doubles so the velocity / history branches are driven by
  # stubbed counts rather than real queries. Each responds to the exact chain the
  # validator builds.
  #
  # NOTE (validation gap): Account declares NO `has_many :payment_methods` and NO
  # `has_many :payments` association, even though those tables exist. So
  # `account.payment_methods` / `account.payments` raise NoMethodError on a real
  # account. We therefore stub these entry points inside
  # `without_partial_double_verification` (rspec-mocks would otherwise refuse to
  # stub a method the object doesn't define — which is itself confirmation of the
  # missing associations). No DB relation is built and no query runs.
  def stub_payment_methods(recent_24h: 0, recent_1h: 0)
    rel = double("payment_methods_relation")
    # account.payment_methods.where("created_at > ?", 24.hours.ago).count
    # and account.payment_methods.where("created_at > ?", 1.hour.ago).count
    allow(rel).to receive(:where) do |_clause, cutoff|
      scoped = double("scoped_payment_methods")
      # 24.hours.ago is "older" (smaller Time) than 1.hour.ago.
      count = cutoff <= 1.hour.ago + 1.second && cutoff >= 1.hour.ago - 1.second ? recent_1h : recent_24h
      allow(scoped).to receive(:count).and_return(count)
      scoped
    end
    without_partial_double_verification do
      allow(account).to receive(:payment_methods).and_return(rel)
    end
  end

  def stub_payments(failed: 0, total: 0)
    rel = double("payments_relation")
    failed_rel = double("failed_payments_relation")
    allow(failed_rel).to receive(:count).and_return(failed)
    allow(rel).to receive(:where).with(status: "failed").and_return(failed_rel)
    allow(rel).to receive(:count).and_return(total)
    without_partial_double_verification do
      allow(account).to receive(:payments).and_return(rel)
    end
  end

  # Device-velocity uses a class-level Account.joins(...) chain.
  def stub_device_velocity(count: 0)
    chain = double("account_join_chain")
    allow(chain).to receive(:where).and_return(chain)
    allow(chain).to receive(:count).and_return(count)
    allow(Account).to receive(:joins).with(:users).and_return(chain)
  end

  # Default the data-source surfaces to benign values, and neutralize the audit
  # sink (its real signature differs from how the validator calls it — see NOTE
  # in the #validate describe block).
  before do
    stub_payment_methods(recent_24h: 0, recent_1h: 0)
    stub_payments(failed: 0, total: 0)
    stub_device_velocity(count: 0)
    allow(AuditLog).to receive(:log_action).and_return(true)
  end

  def build(payment_method_data:, request_metadata: {})
    described_class.new(
      account: account,
      user: user,
      payment_method_data: payment_method_data,
      request_metadata: request_metadata
    )
  end

  # Convenience to reach a private sub-check in isolation.
  def run_check(validator, name)
    validator.send(name)
  end

  # A freshly factory-built account has created_at == now, so check_account_history
  # always adds "new_account" (+25). For tests that want a baseline-clean account,
  # age it past the 1-day "new account" window.
  def age_account!(age = 90.days.ago)
    allow(account).to receive(:created_at).and_return(age)
  end

  describe "#validate (orchestrator)" do
    it "returns the aggregate result hash and an 'approve' recommendation for a clean card" do
      age_account! # otherwise the brand-new factory account adds +25 (new_account)
      result = build(payment_method_data: clean_card_data).validate

      expect(result).to include(
        :overall_risk_score,
        :risk_factors,
        :validations,
        :recommendation,
        :requires_additional_verification
      )
      expect(result[:overall_risk_score]).to eq(0)
      expect(result[:risk_factors]).to eq([])
      expect(result[:recommendation]).to eq("approve")
      expect(result[:requires_additional_verification]).to be(false)
      # All six sub-validations ran.
      expect(result[:validations].keys).to contain_exactly(
        :card_validation, :velocity_check, :geolocation_check,
        :device_fingerprint, :account_history, :provider_validation
      )
    end

    it "swallows the audit-write failure and still returns a result (VALIDATION GAP)" do
      # NOTE (validation gap): log_validation_results calls
      #   AuditLog.log_action(action:, resource_type:, account:, user:, new_values:, source:, metadata:)
      # but the real AuditLog.log_action signature requires a `resource:` record
      # (NOT `resource_type:`). The mismatched keywords raise ArgumentError, which is
      # caught by log_validation_results' own `rescue StandardError` — so the payment
      # validation audit trail is silently dropped in production. We pin that here:
      # the audit attempt fails, but validate completes normally and returns a result.
      age_account!

      # Let the real (un-stubbed) AuditLog.log_action run so its signature mismatch
      # raises for real, exercising the swallow path. It must NOT create any record.
      allow(AuditLog).to receive(:log_action).and_call_original

      expect {
        result = build(payment_method_data: clean_card_data).validate
        expect(result[:recommendation]).to eq("approve")
      }.not_to change(AuditLog, :count)
    end

    it "aggregates risk across sub-checks and clamps the overall score at 100" do
      # cvc fail (30) + provider highest risk (60) + previous chargebacks (60)
      # + new account (25)  => raw 175, clamped to 100.
      stub_payments(failed: 0, total: 0)
      allow(account).to receive(:created_at).and_return(1.hour.ago) # new account
      allow(account).to receive(:settings).and_return("chargeback_count" => 2)

      data = clean_card_data(
        "card" => {
          "checks" => { "cvc_check" => "fail" },
          "risk_level" => "highest"
        }
      )

      result = build(payment_method_data: data).validate

      expect(result[:overall_risk_score]).to eq(100)
      expect(result[:recommendation]).to eq("reject")
      expect(result[:requires_additional_verification]).to be(true)
      expect(result[:risk_factors]).to include(
        "cvc_check_failed", "provider_highest_risk", "previous_chargebacks", "new_account"
      )
    end

    it "applies the high_risk_country + geolocation_mismatch 1.2x multiplier" do
      # card country high-risk (25) + funding still credit. geolocation mismatch:
      # user US vs ip country high-risk. We stub the ip->country lookup.
      allow(user).to receive(:preferences).and_return("country" => "US")
      allow(account).to receive(:settings).and_return({})

      data = clean_card_data("card" => { "country" => "NG" }) # NG is high-risk
      validator = build(
        payment_method_data: data,
        request_metadata: { ip_address: "203.0.113.5" }
      )
      # ip resolves to a high-risk country different from user's US.
      allow(validator).to receive(:detect_country_from_ip).and_return("NG")

      result = validator.validate

      expect(result[:risk_factors]).to include("high_risk_country", "geolocation_mismatch")
      # Raw: card 25 + geo (mismatch 30 + high_risk_ip 40) = 95; *1.2 = 114 -> clamp 100.
      expect(result[:overall_risk_score]).to eq(100)
    end

    it "maps to 'review' at a mid risk band" do
      # 0..30 is approve. Push into 31..60 with cvc fail (30) + moderate velocity (20) = 50.
      age_account! # keep the new-account (+25) signal out of this band calc
      stub_payment_methods(recent_24h: 2, recent_1h: 0) # >1 => moderate velocity (20)
      data = clean_card_data("card" => { "checks" => { "cvc_check" => "fail" } }) # 30

      result = build(payment_method_data: data).validate

      expect(result[:overall_risk_score]).to eq(50)
      expect(result[:recommendation]).to eq("review")
      expect(result[:requires_additional_verification]).to be(false)
    end

    it "returns a hard-reject result when an unexpected error is raised mid-validation" do
      validator = build(payment_method_data: clean_card_data)
      allow(validator).to receive(:validate_card_details).and_raise(StandardError, "boom")

      result = validator.validate

      expect(result[:overall_risk_score]).to eq(100)
      expect(result[:recommendation]).to eq("reject")
      expect(result[:risk_factors]).to eq(["validation_error"])
      expect(result[:error]).to eq("boom")
    end
  end

  describe "#validate_card_details" do
    # NOTE (validation gap): this method does NO Luhn check, NO expiry-date
    # enforcement, and NO CVV-format check. It only scores provider-supplied
    # metadata (country, funding, and the provider's own AVS/CVC `checks` flags).
    # The examples below pin that actual behavior; the "Luhn/expiry" examples
    # demonstrate the gap explicitly.

    it "returns valid with zero risk for a non-card payment method" do
      validator = build(payment_method_data: { "type" => "bank" })
      expect(run_check(validator, :validate_card_details)).to eq(valid: true, risk_score: 0)
    end

    it "passes a clean domestic credit card" do
      validator = build(payment_method_data: clean_card_data)
      result = run_check(validator, :validate_card_details)

      expect(result[:valid]).to be(true)
      expect(result[:risk_score]).to eq(0)
      expect(result[:risk_factors]).to eq([])
    end

    it "flags a high-risk country (+25)" do
      validator = build(payment_method_data: clean_card_data("card" => { "country" => "NG" }))
      result = run_check(validator, :validate_card_details)

      expect(result[:risk_score]).to eq(25)
      expect(result[:risk_factors]).to include("high_risk_country")
      expect(result[:valid]).to be(true) # still < 50
    end

    it "flags a high-risk funding source: prepaid (+15)" do
      validator = build(payment_method_data: clean_card_data("card" => { "funding" => "prepaid" }))
      result = run_check(validator, :validate_card_details)

      expect(result[:risk_score]).to eq(15)
      expect(result[:risk_factors]).to include("high_risk_funding_source")
    end

    it "scores cvc_check + address + postal failures and rejects past the 50 threshold" do
      data = clean_card_data(
        "card" => {
          "checks" => {
            "cvc_check" => "fail",                  # +30
            "address_line1_check" => "fail",        # +20
            "address_postal_code_check" => "fail"   # +15
          }
        }
      )
      result = run_check(build(payment_method_data: data), :validate_card_details)

      expect(result[:risk_score]).to eq(65)
      expect(result[:valid]).to be(false) # >= 50 => invalid
      expect(result[:risk_factors]).to contain_exactly(
        "cvc_check_failed", "address_verification_failed", "postal_code_verification_failed"
      )
    end

    it "exposes provider check details in the result payload" do
      result = run_check(build(payment_method_data: clean_card_data), :validate_card_details)
      expect(result[:details]).to include(brand: "visa", country: "US", funding: "credit")
    end

    context "VALIDATION GAP characterization (no Luhn / no expiry / no CVV-format)" do
      it "does NOT reject an invalid-Luhn PAN (Luhn is never checked)" do
        # Bad-Luhn Visa test number, but everything else clean.
        data = clean_card_data("card" => { "number" => VISA_TEST_PAN_BAD_LUHN })
        result = run_check(build(payment_method_data: data), :validate_card_details)

        # GAP: passes despite the invalid checksum.
        expect(result[:valid]).to be(true)
        expect(result[:risk_score]).to eq(0)
      end

      it "does NOT reject an expired card (expiry is never enforced here)" do
        data = clean_card_data(
          "card" => { "exp_month" => 1, "exp_year" => 2000 } # long expired
        )
        result = run_check(build(payment_method_data: data), :validate_card_details)

        # GAP: expiry fields are ignored entirely.
        expect(result[:valid]).to be(true)
        expect(result[:risk_score]).to eq(0)
      end

      it "does NOT reject a malformed CVC value (only the provider 'cvc_check' flag matters)" do
        data = clean_card_data(
          "card" => { "cvc" => "not-a-cvv", "checks" => { "cvc_check" => "pass" } }
        )
        result = run_check(build(payment_method_data: data), :validate_card_details)

        # GAP: the raw CVC string is never inspected; only the provider flag is.
        expect(result[:valid]).to be(true)
        expect(result[:risk_score]).to eq(0)
      end

      it "treats an Amex test PAN identically (PAN content is irrelevant to scoring)" do
        data = clean_card_data("card" => { "number" => AMEX_TEST_PAN, "brand" => "amex" })
        result = run_check(build(payment_method_data: data), :validate_card_details)

        expect(result[:valid]).to be(true)
        expect(result[:risk_score]).to eq(0)
      end
    end
  end

  describe "#check_velocity_limits" do
    it "passes when payment-method velocity is within limits" do
      stub_payment_methods(recent_24h: 1, recent_1h: 0)
      result = run_check(build(payment_method_data: clean_card_data), :check_velocity_limits)

      expect(result[:valid]).to be(true)
      expect(result[:risk_score]).to eq(0)
      expect(result[:risk_factors]).to eq([])
    end

    it "flags moderate velocity (>1 in 24h => +20)" do
      stub_payment_methods(recent_24h: 2, recent_1h: 0)
      result = run_check(build(payment_method_data: clean_card_data), :check_velocity_limits)

      expect(result[:risk_score]).to eq(20)
      expect(result[:risk_factors]).to include("moderate_payment_method_velocity")
      expect(result[:valid]).to be(true)
    end

    it "flags high velocity (>3 in 24h => +40) and stays valid below the 60 threshold" do
      stub_payment_methods(recent_24h: 4, recent_1h: 0)
      result = run_check(build(payment_method_data: clean_card_data), :check_velocity_limits)

      expect(result[:risk_score]).to eq(40)
      expect(result[:risk_factors]).to include("high_payment_method_velocity")
      expect(result[:valid]).to be(true)
    end

    it "compounds high velocity with the derived failed-attempts heuristic to exceed the threshold" do
      # NOTE: failed_attempts is a heuristic = recent_1h_count / 2. With recent_1h=12,
      # failed_attempts=6 (>5 => +50). Combined with high 24h velocity (+40) => 90.
      stub_payment_methods(recent_24h: 4, recent_1h: 12)
      result = run_check(build(payment_method_data: clean_card_data), :check_velocity_limits)

      expect(result[:details][:failed_attempts]).to eq(6)
      expect(result[:risk_score]).to eq(90)
      expect(result[:valid]).to be(false) # >= 60
      expect(result[:risk_factors]).to include("high_payment_method_velocity", "high_failed_attempts")
    end
  end

  describe "#check_account_history" do
    it "passes a seasoned account with clean payment history" do
      allow(account).to receive(:created_at).and_return(90.days.ago)
      stub_payments(failed: 0, total: 10)
      allow(account).to receive(:settings).and_return({})

      result = run_check(build(payment_method_data: clean_card_data), :check_account_history)

      expect(result[:valid]).to be(true)
      expect(result[:risk_score]).to eq(0)
      expect(result[:risk_factors]).to eq([])
    end

    it "flags a brand-new account (+25)" do
      allow(account).to receive(:created_at).and_return(1.hour.ago)
      stub_payments(failed: 0, total: 0)
      allow(account).to receive(:settings).and_return({})

      result = run_check(build(payment_method_data: clean_card_data), :check_account_history)

      expect(result[:risk_factors]).to include("new_account")
      expect(result[:risk_score]).to eq(25)
    end

    it "flags a high payment-failure rate (>0.5 => +40) and rejects past the threshold" do
      allow(account).to receive(:created_at).and_return(90.days.ago)
      stub_payments(failed: 8, total: 10) # 0.8 failure rate
      allow(account).to receive(:settings).and_return({})

      result = run_check(build(payment_method_data: clean_card_data), :check_account_history)

      expect(result[:risk_factors]).to include("high_payment_failure_rate")
      expect(result[:risk_score]).to eq(40)
    end

    it "treats prior chargebacks as a heavy signal (+60) and marks invalid" do
      allow(account).to receive(:created_at).and_return(90.days.ago)
      stub_payments(failed: 0, total: 5)
      allow(account).to receive(:settings).and_return("chargeback_count" => 1)

      result = run_check(build(payment_method_data: clean_card_data), :check_account_history)

      expect(result[:risk_factors]).to include("previous_chargebacks")
      expect(result[:risk_score]).to eq(60)
      expect(result[:valid]).to be(false) # >= 50
      expect(result[:details][:chargeback_count]).to eq(1)
    end
  end

  describe "#validate_geolocation" do
    it "is a no-op (valid, zero risk) when no ip_address is supplied" do
      validator = build(payment_method_data: clean_card_data, request_metadata: {})
      expect(run_check(validator, :validate_geolocation)).to eq(valid: true, risk_score: 0)
    end

    it "passes when ip country matches the user's country" do
      allow(user).to receive(:preferences).and_return("country" => "US")
      validator = build(
        payment_method_data: clean_card_data,
        request_metadata: { ip_address: "192.168.1.10" } # in-service stub resolves to US
      )

      result = run_check(validator, :validate_geolocation)
      expect(result[:valid]).to be(true)
      expect(result[:risk_score]).to eq(0)
      expect(result[:details][:ip_country]).to eq("US")
    end

    it "flags a plain geolocation mismatch (+30)" do
      allow(user).to receive(:preferences).and_return("country" => "GB")
      validator = build(
        payment_method_data: clean_card_data,
        request_metadata: { ip_address: "192.168.1.10" } # resolves to US
      )

      result = run_check(validator, :validate_geolocation)
      expect(result[:risk_factors]).to include("geolocation_mismatch")
      expect(result[:risk_score]).to eq(30)
      expect(result[:valid]).to be(true) # < 50
    end

    it "escalates a mismatch into a high-risk IP country (+30 +40 => invalid)" do
      allow(user).to receive(:preferences).and_return("country" => "US")
      validator = build(
        payment_method_data: clean_card_data,
        request_metadata: { ip_address: "203.0.113.9" }
      )
      allow(validator).to receive(:detect_country_from_ip).and_return("NG") # high-risk

      result = run_check(validator, :validate_geolocation)
      expect(result[:risk_factors]).to include("geolocation_mismatch", "high_risk_ip_country")
      expect(result[:risk_score]).to eq(70)
      expect(result[:valid]).to be(false)
    end

    it "flags detected VPN/proxy usage (+35)" do
      allow(user).to receive(:preferences).and_return("country" => "US")
      validator = build(
        payment_method_data: clean_card_data,
        request_metadata: { ip_address: "192.168.1.10" } # resolves to US (no mismatch)
      )
      allow(validator).to receive(:vpn_or_proxy_detected?).and_return(true)

      result = run_check(validator, :validate_geolocation)
      expect(result[:risk_factors]).to include("vpn_proxy_detected")
      expect(result[:risk_score]).to eq(35)
    end
  end

  describe "#validate_device_fingerprint" do
    it "is a no-op (valid, zero risk) when no device_fingerprint is supplied" do
      validator = build(payment_method_data: clean_card_data, request_metadata: {})
      expect(run_check(validator, :validate_device_fingerprint)).to eq(valid: true, risk_score: 0)
    end

    it "passes a fingerprint seen on a single account" do
      stub_device_velocity(count: 1)
      validator = build(
        payment_method_data: clean_card_data,
        request_metadata: { device_fingerprint: "fp-clean-001" }
      )

      result = run_check(validator, :validate_device_fingerprint)
      expect(result[:valid]).to be(true)
      expect(result[:risk_score]).to eq(0)
      expect(result[:details][:device_accounts]).to eq(1)
    end

    it "flags moderate device velocity (>1 accounts => +20)" do
      stub_device_velocity(count: 2)
      validator = build(
        payment_method_data: clean_card_data,
        request_metadata: { device_fingerprint: "fp-shared-002" }
      )

      result = run_check(validator, :validate_device_fingerprint)
      expect(result[:risk_factors]).to include("moderate_device_velocity")
      expect(result[:risk_score]).to eq(20)
    end

    it "flags high device velocity (>3 accounts => +45) but stays valid below the 50 cutoff" do
      stub_device_velocity(count: 4)
      validator = build(
        payment_method_data: clean_card_data,
        request_metadata: { device_fingerprint: "fp-fraud-003" }
      )

      result = run_check(validator, :validate_device_fingerprint)
      expect(result[:risk_factors]).to include("high_device_velocity")
      expect(result[:risk_score]).to eq(45)
      # NOTE (boundary): 45 is still < 50, so this sub-check reports valid:true even
      # at the highest single device-velocity signal. Pin that exact boundary.
      expect(result[:valid]).to be(true)
    end

    it "flags a suspicious device (+25) when the in-service heuristic trips" do
      stub_device_velocity(count: 1)
      validator = build(
        payment_method_data: clean_card_data,
        request_metadata: { device_fingerprint: "fp-suspect-004" }
      )
      allow(validator).to receive(:suspicious_device?).and_return(true)

      result = run_check(validator, :validate_device_fingerprint)
      expect(result[:risk_factors]).to include("suspicious_device")
      expect(result[:risk_score]).to eq(25)
    end
  end

  describe "#validate_with_provider" do
    it "is a no-op (valid, zero risk) for a non-stripe provider" do
      validator = build(payment_method_data: clean_card_data("provider" => "paypal"))
      expect(run_check(validator, :validate_with_provider)).to eq(valid: true, risk_score: 0)
    end

    it "passes a stripe card with no provider risk_level" do
      validator = build(payment_method_data: clean_card_data) # provider=stripe, no risk_level
      result = run_check(validator, :validate_with_provider)

      expect(result[:valid]).to be(true)
      expect(result[:risk_score]).to eq(0)
    end

    it "adds +30 for an 'elevated' provider risk_level (still valid)" do
      data = clean_card_data("card" => { "risk_level" => "elevated" })
      result = run_check(build(payment_method_data: data), :validate_with_provider)

      expect(result[:risk_factors]).to include("provider_elevated_risk")
      expect(result[:risk_score]).to eq(30)
      expect(result[:valid]).to be(true) # < 40
    end

    it "adds +60 for a 'highest' provider risk_level and marks invalid" do
      data = clean_card_data("card" => { "risk_level" => "highest" })
      result = run_check(build(payment_method_data: data), :validate_with_provider)

      expect(result[:risk_factors]).to include("provider_highest_risk")
      expect(result[:risk_score]).to eq(60)
      expect(result[:valid]).to be(false) # >= 40
      expect(result[:details][:provider_risk_level]).to eq("highest")
    end
  end

  describe "recommendation thresholds (generate_recommendation)" do
    # Drive the orchestrator to each band via a single tunable signal and pin the
    # mapping: 0..30 approve, 31..60 review, 61..80 additional_verification, else reject.
    it "maps 0 => approve" do
      result = build(payment_method_data: clean_card_data).validate
      expect(result[:recommendation]).to eq("approve")
    end

    it "maps the 61..80 band => additional_verification and requires extra verification" do
      # provider highest (60) + new account (25) => 85? Too high. Use elevated (30)
      # + high_payment_failure_rate (40) = 70 => additional_verification.
      allow(account).to receive(:created_at).and_return(90.days.ago)
      stub_payments(failed: 8, total: 10) # +40
      allow(account).to receive(:settings).and_return({})
      data = clean_card_data("card" => { "risk_level" => "elevated" }) # +30

      result = build(payment_method_data: data).validate
      expect(result[:overall_risk_score]).to eq(70)
      expect(result[:recommendation]).to eq("additional_verification")
      expect(result[:requires_additional_verification]).to be(true)
    end
  end
end
