# frozen_string_literal: true

require "rails_helper"

# G15: the global PCI log formatter must scrub SECRETS as well as PCI data, so a
# leaked credential in a log line is redacted (not just card/PCI values).
RSpec.describe "PCI compliance log formatter (G15 secret scrubbing)" do
  subject(:formatter) { Rails.application.config.log_formatter }

  def format(msg)
    formatter.call("INFO", Time.utc(2026, 1, 1), "test", msg)
  end

  it "is configured as a callable formatter" do
    expect(formatter).to respond_to(:call)
  end

  it "redacts a leaked secret from a log line" do
    out = format("connecting with api_key=sk-abcdef0123456789ABCDEF")

    expect(out).to include("[REDACTED]")
    expect(out).not_to include("sk-abcdef0123456789ABCDEF")
  end

  it "redacts a bearer token in a log line" do
    out = format("Authorization: Bearer abcDEF1234567890token")

    expect(out).to include("[REDACTED]")
    expect(out).not_to include("abcDEF1234567890token")
  end

  it "still masks a PCI value (credit card), preserving existing behaviour" do
    out = format("charging card 4111 1111 1111 1111 now")

    expect(out).not_to include("4111 1111 1111 1111")
  end

  it "leaves an ordinary log line unchanged" do
    out = format("user 42 viewed the dashboard")

    expect(out).to include("user 42 viewed the dashboard")
  end

  it "passes a non-String message through untouched" do
    out = format({ event: "ok" })

    expect(out).to include({ event: "ok" }.to_s)
  end
end
