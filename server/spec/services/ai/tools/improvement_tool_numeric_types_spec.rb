# frozen_string_literal: true

require "rails_helper"

# The tool declares `confidence_score` as `type: "number"` on the way IN
# (definition :37, action_definitions :69) and the model validates it
# numerically — but ai_improvement_recommendations.confidence_score is
# decimal(5,4), so reading it back yields a BigDecimal, and BigDecimal#to_json
# emits a STRING. Every consumer that parsed the field as a number got "0.87"
# and had to conclude either that the tool was broken or that the schema lied.
#
# BigDecimal is a Ruby Numeric, so `be_a(Numeric)` does NOT catch this. The bug
# only exists after serialization, so these assertions round-trip through JSON —
# that is the whole point of the file.
#
# The generic sweep at the bottom is the durable half: it fails for ANY future
# decimal column that reaches a payload, not just this one field.
RSpec.describe Ai::Tools::ImprovementTool, "numeric field types" do
  let(:account) { create(:account) }

  subject(:tool) { described_class.new(account: account, internal: true) }

  let!(:recommendation) do
    Ai::ImprovementRecommendation.create!(
      account: account,
      recommendation_type: "code_lint",
      status: "pending",
      confidence_score: 0.87,
      evidence: { "title" => "a lint offer" },
      target_type: "Devops::GitRepository",
      target_id: SecureRandom.uuid
    )
  end

  # What a consumer actually receives.
  def round_trip(payload)
    JSON.parse(payload.to_json)
  end

  describe "list_improvements" do
    it "emits confidence as a JSON number, not a quoted string" do
      first = round_trip(tool.send(:list_improvements, {})[:data])["improvements"].first

      expect(first["confidence"]).to be_a(Numeric)
      expect(first["confidence"]).to eq(0.87)
    end
  end

  describe "create_improvement" do
    it "emits confidence as a JSON number on the way back out too" do
      result = tool.send(:create_improvement, {
                           recommendation_type: "code_lint",
                           title: "another offer",
                           fingerprint: SecureRandom.hex(6),
                           confidence_score: 0.42,
                           files: [ "server/app/models/thing.rb" ]
                         })

      payload = round_trip(result[:data])["recommendation"]

      expect(payload["confidence"]).to be_a(Numeric)
      expect(payload["confidence"]).to eq(0.42)
    end

    # The round trip is the contract: a number goes in, the same number comes
    # back. Before the fix it went in as a Float and came back as "0.42".
    it "round-trips the value it was given" do
      created = tool.send(:create_improvement, {
                            recommendation_type: "dead_code",
                            title: "round trip",
                            fingerprint: SecureRandom.hex(6),
                            confidence_score: 0.5,
                            files: [ "server/app/models/other.rb" ]
                          })
      id = created[:data][:recommendation][:id]

      listed = round_trip(tool.send(:list_improvements, {})[:data])["improvements"]
               .find { |i| i["id"] == id }

      expect(listed["confidence"]).to eq(0.5)
    end
  end

  describe "scoreboard" do
    it "emits its counts and velocity as JSON numbers" do
      data = round_trip(tool.send(:scoreboard, {})[:data])

      expect(data["discovered"]).to be_a(Numeric)
      expect(data["metric"]["net_improvement_velocity"]).to be_a(Numeric)
      expect(data["metric"]["window_days"]).to be_a(Numeric)
    end
  end

  # The durable half. A BigDecimal anywhere in a payload becomes a JSON string
  # the moment it is serialized, whatever the field is called — so rather than
  # enumerating today's numeric fields, this fails for any decimal column a
  # future change lets reach a payload.
  describe "no BigDecimal reaches any payload" do
    def deep_values(object)
      case object
      when Hash  then object.flat_map { |k, v| [ k ] + deep_values(v) }
      when Array then object.flat_map { |v| deep_values(v) }
      else [ object ]
      end
    end

    it "holds for every action that returns records" do
      payloads = [
        tool.send(:list_improvements, {}),
        tool.send(:scoreboard, {}),
        tool.send(:create_improvement, {
                    recommendation_type: "test_gap",
                    title: "sweep",
                    fingerprint: SecureRandom.hex(6),
                    confidence_score: 0.31,
                    files: [ "server/app/models/sweep.rb" ]
                  })
      ]

      payloads.each do |payload|
        offenders = deep_values(payload).grep(BigDecimal)
        expect(offenders).to be_empty,
                             "#{offenders.size} BigDecimal value(s) would serialize as JSON strings: " \
                             "#{offenders.inspect}"
      end
    end
  end
end
