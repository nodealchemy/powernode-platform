# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::Concerns::CodebaseContextResolvable do
  # Minimal stand-in for a tool that includes the concern. Mirrors how
  # Ai::Tools::BaseTool subclasses expose a private `account` reader.
  let(:test_class) do
    Class.new do
      include Ai::Tools::Concerns::CodebaseContextResolvable

      def initialize(account:)
        @account = account
      end

      private

      attr_reader :account
    end
  end

  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:instance) { test_class.new(account: account) }

  describe "#resolve_repository" do
    it "returns nil when the identifier is blank" do
      expect(instance.send(:resolve_repository, nil)).to be_nil
      expect(instance.send(:resolve_repository, "")).to be_nil
    end

    it "resolves by id" do
      repo = create(:git_repository, account: account)
      expect(instance.send(:resolve_repository, repo.id)).to eq(repo)
    end

    it "resolves by name" do
      repo = create(:git_repository, account: account, name: "my-repo")
      expect(instance.send(:resolve_repository, "my-repo")).to eq(repo)
    end

    it "resolves by full_name" do
      repo = create(:git_repository, account: account, full_name: "org/my-repo")
      expect(instance.send(:resolve_repository, "org/my-repo")).to eq(repo)
    end

    context "when the identifier matches no repository for the account" do
      it "raises RecordNotFound whose message lists the account's available repositories" do
        create(:git_repository, account: account, full_name: "acme/widgets")
        create(:git_repository, account: account, full_name: "acme/gadgets")

        expect {
          instance.send(:resolve_repository, "nonexistent")
        }.to raise_error(ActiveRecord::RecordNotFound) do |error|
          expect(error.message).to include("repository not found: nonexistent")
          expect(error.message).to include("acme/widgets")
          expect(error.message).to include("acme/gadgets")
        end
      end

      it "never includes repositories belonging to another account" do
        create(:git_repository, account: other_account, full_name: "other/secret-repo")

        expect {
          instance.send(:resolve_repository, "nonexistent")
        }.to raise_error(ActiveRecord::RecordNotFound) do |error|
          expect(error.message).not_to include("secret-repo")
        end
      end

      it "reports clearly when the account has no git repositories at all" do
        expect {
          instance.send(:resolve_repository, "nonexistent")
        }.to raise_error(ActiveRecord::RecordNotFound, /no git repositories/)
      end

      it "caps the listed repositories and notes how many more exist" do
        26.times { |n| create(:git_repository, account: account, full_name: "acme/repo-#{n}") }

        expect {
          instance.send(:resolve_repository, "nonexistent")
        }.to raise_error(ActiveRecord::RecordNotFound) do |error|
          listed = error.message.scan(%r{acme/repo-\d+})
          expect(listed.size).to be <= 20
          expect(error.message).to include("26")
          expect(error.message).to match(/more/i)
        end
      end
    end
  end
end
