# frozen_string_literal: true

require "rails_helper"

# IMP-7552124d35c1 -- `encrypts :last_login_ip` stores an ActiveRecord
# encryption envelope, several times longer than the address. The column was
# `varchar(45)` (sized for the plaintext), so writing ANY real address raised
# PG::StringDataRightTruncation. A full-length IPv6 (39 chars) and an
# IPv4-mapped IPv6 (up to 45 chars) are the values the old limit was sized for.
RSpec.describe User, "last_login_ip" do
  let(:user) { create(:user) }

  {
    "a full-length IPv6 address" => "2001:0db8:85a3:0000:0000:8a2e:0370:7334",
    "an IPv4-mapped IPv6 address" => "0000:0000:0000:0000:0000:ffff:192.168.100.228",
    "a plain IPv4 address" => "203.0.113.42"
  }.each do |label, address|
    it "saves and reloads #{label} without storing the plaintext" do
      user.update!(last_login_ip: address)

      expect(user.reload.last_login_ip).to eq(address)

      raw = described_class.connection.select_value(
        described_class.sanitize_sql([ "SELECT last_login_ip FROM users WHERE id = ?", user.id ])
      )
      expect(raw).to be_present
      expect(raw).not_to include(address)
      expect(raw.length).to be > 45
    end
  end

  it "holds a column wide enough for the encrypted envelope" do
    column = described_class.columns_hash["last_login_ip"]

    expect(column.limit).to be_nil
  end
end
