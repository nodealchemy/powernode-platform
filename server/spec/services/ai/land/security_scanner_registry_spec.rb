# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Land::SecurityScannerRegistry do
  before { described_class.reset! }
  after { described_class.reset! }

  it "registers and lists a callable handler" do
    handler = ->(_ctx) { [] }
    described_class.register(:brakeman, handler)

    expect(described_class.registered?(:brakeman)).to be(true)
    expect(described_class.names).to eq([ :brakeman ])
    expect(described_class.handlers[:brakeman]).to eq(handler)
  end

  it "accepts a block handler and makes it callable" do
    described_class.register(:cve) { |_ctx| [ { scanner: "cve", severity: "low", detail: "x" } ] }
    result = described_class.handlers[:cve].call({})
    expect(result).to eq([ { scanner: "cve", severity: "low", detail: "x" } ])
  end

  it "rejects a non-callable handler" do
    expect { described_class.register(:bad, "not callable") }.to raise_error(ArgumentError)
  end

  it "unregisters a handler" do
    described_class.register(:tmp) { |_| [] }
    described_class.unregister(:tmp)
    expect(described_class.registered?(:tmp)).to be(false)
  end

  it "isolates state via reset!" do
    described_class.register(:a) { |_| [] }
    described_class.reset!
    expect(described_class.names).to eq([])
  end
end
