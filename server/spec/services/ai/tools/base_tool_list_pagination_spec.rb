# frozen_string_literal: true

require "rails_helper"

# APO-8b (IMP-c5a62a32d3bb) — the shared list-pagination seam.
#
# Before this, every list action on the MCP surface answered with either the
# whole table or a hard-coded cap, and the `count` beside the rows meant a
# different thing per action: some counted the UNCAPPED relation, some counted
# the relation AFTER the cap was applied (so 100 rows and 10,000 rows were
# indistinguishable), and some returned no count at all. No action offered a
# page two.
#
# The seam is core because the defect is not extension-shaped: any tool
# returning a relation has it. These examples pin the four properties every
# caller inherits — a SiteSetting-resolved default with a constant fallback, a
# clamp instead of a refusal on an over-large limit, an UNCAPPED count, and a
# keyset cursor that walks every row exactly once.
RSpec.describe Ai::Tools::BaseTool, "list pagination seam" do
  let(:account) { create(:account) }

  # A probe tool that exercises ONLY the seam. Deliberately not one of the
  # real tools: the properties below belong to BaseTool, and asserting them
  # through a concrete tool would let that tool's own filtering explain a pass.
  let(:tool_class) do
    Class.new(described_class) do
      def self.name
        "Ai::Tools::ListPaginationProbeTool"
      end

      def list(params)
        paginated_result(:pages, ::Page.where(account_id: account.id), params,
                         sort: :title, direction: :asc) { |p| { id: p.id, title: p.title } }
      end
    end
  end

  subject(:tool) { tool_class.new(account: account) }

  def clear_settings
    SiteSetting.where(
      key: [ described_class::LIST_DEFAULT_LIMIT_SETTING, described_class::LIST_MAX_LIMIT_SETTING ]
    ).delete_all
  end

  before { clear_settings }

  describe "the default page size" do
    it "falls back to the constant when the operator has set no value" do
      expect(described_class.default_list_limit).to eq(described_class::LIST_DEFAULT_LIMIT)
    end

    it "resolves from SiteSetting when the operator has set one" do
      SiteSetting.set(described_class::LIST_DEFAULT_LIMIT_SETTING, 7, setting_type: "integer")

      expect(described_class.default_list_limit).to eq(7)
    end

    it "ignores a non-positive configured value rather than returning an empty page forever" do
      SiteSetting.set(described_class::LIST_DEFAULT_LIMIT_SETTING, 0, setting_type: "integer")

      expect(described_class.default_list_limit).to eq(described_class::LIST_DEFAULT_LIMIT)
    end
  end

  describe "a page of rows" do
    let!(:pages) do
      (1..5).map { |n| create(:page, account: account, title: format("probe-%02d", n)) }
    end

    before { SiteSetting.set(described_class::LIST_DEFAULT_LIMIT_SETTING, 2, setting_type: "integer") }

    it "reports the UNCAPPED total, not the size of the page it returned" do
      result = tool.list({})

      expect(result[:success]).to be(true)
      expect(result[:data][:pages].size).to eq(2)
      expect(result[:data][:returned]).to eq(2)
      expect(result[:data][:count]).to eq(5)
      expect(result[:data][:limit]).to eq(2)
    end

    it "signals that rows remain and hands back a cursor to reach them" do
      result = tool.list({})

      expect(result[:data][:has_more]).to be(true)
      expect(result[:data][:next_cursor]).to be_present
    end

    it "closes the walk on the last page" do
      result = tool.list({ limit: 50 })

      expect(result[:data][:has_more]).to be(false)
      expect(result[:data][:next_cursor]).to be_nil
    end

    it "walks every row exactly once through next_cursor" do
      seen   = []
      cursor = nil

      10.times do
        result = tool.list({ limit: 2, cursor: cursor }.compact)
        seen.concat(result[:data][:pages].map { |p| p[:id] })
        cursor = result[:data][:next_cursor]
        break if cursor.nil?
      end

      expect(cursor).to be_nil
      expect(seen).to eq(pages.sort_by(&:title).map(&:id))
    end

    it "clamps an over-large limit to the configured maximum instead of refusing it" do
      SiteSetting.set(described_class::LIST_MAX_LIMIT_SETTING, 3, setting_type: "integer")

      result = tool.list({ limit: 10_000 })

      expect(result[:success]).to be(true)
      expect(result[:data][:limit]).to eq(3)
      expect(result[:data][:pages].size).to eq(3)
      expect(result[:data][:count]).to eq(5)
    end

    # The clamp is for a limit that is too LARGE. A limit that is not a
    # positive integer is a different case and must be refused, not coerced:
    # `limit: 0` coerced into `.limit(1)` — or worse, honoured — would answer
    # a truncated page the caller never asked for and had no way to detect.
    [ 0, -1, "abc" ].each do |bad_limit|
      it "refuses limit: #{bad_limit.inspect} as a result rather than raising or coercing it" do
        result = nil
        expect { result = tool.list({ limit: bad_limit }) }.not_to raise_error

        expect(result[:success]).to be(false)
        expect(result[:error]).to include("limit")
      end
    end

    # A malformed cursor must come back as a REFUSAL the caller can read, not
    # as an exception: SdwanTool#call and SystemPackageRepositoryTool#call do
    # not rescue ArgumentError, so a raise there escapes to the controller's
    # generic handler and surfaces as a JSON-RPC -32603 internal error.
    it "refuses an unreadable cursor as a result rather than raising" do
      result = nil
      expect { result = tool.list({ cursor: "not-a-cursor" }) }.not_to raise_error

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("cursor")
    end

    # Valid base64 of valid JSON is not yet a cursor. Each of these decodes one
    # step further than the last, so a check that only covers the outer layer
    # leaves the inner one raising NoMethodError out of the tool.
    [
      [ "valid base64, not JSON",        Base64.urlsafe_encode64("hello", padding: false) ],
      [ "valid JSON, not an object",     Base64.urlsafe_encode64("5", padding: false) ],
      [ "an object with no id",          Base64.urlsafe_encode64({ "v" => "x" }.to_json, padding: false) ],
      # The layer past "has an id": a NON-EMPTY id that is not a UUID is bound
      # straight into the keyset predicate against a uuid primary key, and
      # Postgres answers `invalid input syntax for type uuid` — an
      # ActiveRecord::StatementInvalid neither paginated_result nor any tool's
      # #call rescues, so it reaches the agent as JSON-RPC -32603 rather than
      # as something it can read and correct.
      [ "an id that is not a UUID",      Base64.urlsafe_encode64({ "v" => "x", "i" => "not-a-uuid" }.to_json, padding: false) ],
      # A sort value that casts to NULL cannot satisfy the row comparison
      # either — without a refusal it answers an empty page forever.
      [ "a null sort value",             Base64.urlsafe_encode64({ "i" => "0199aa00-0000-7000-8000-000000000000" }.to_json, padding: false) ]
    ].each do |label, forged|
      it "refuses a cursor that is #{label}" do
        result = nil
        expect { result = tool.list({ cursor: forged }) }.not_to raise_error

        expect(result[:success]).to be(false)
        expect(result[:error]).to include("cursor")
      end
    end
  end

  # A NULL sort value makes the keyset row comparison NULL — never true — so a
  # nullable sort column drops every such row from page two onward and the walk
  # ends short of `count` with nothing to show for it. That is the one failure
  # mode of this design that is invisible in the payload, so it is refused at
  # the call site rather than trusted to code review.
  describe "a nullable sort column" do
    let(:nullable_sort_tool) do
      Class.new(described_class) do
        def self.name
          "Ai::Tools::NullableSortProbeTool"
        end

        def list(params)
          paginated_result(:pages, ::Page.where(account_id: account.id), params,
                           sort: :meta_description, direction: :asc) { |p| { id: p.id } }
        end
      end
    end

    it "is refused rather than silently dropping rows from page two" do
      create(:page, account: account)

      expect { nullable_sort_tool.new(account: account).list({}) }
        .to raise_error(ArgumentError, /meta_description is nullable/)
    end
  end

  describe "the declared parameter fragment" do
    it "declares limit and cursor for tools to splat into their action schemas" do
      expect(described_class::PAGINATION_PARAMETERS.keys).to contain_exactly(:limit, :cursor)
      expect(described_class::PAGINATION_PARAMETERS[:limit][:type]).to eq("integer")
      expect(described_class::PAGINATION_PARAMETERS[:cursor][:type]).to eq("string")
    end
  end
end
