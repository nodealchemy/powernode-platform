# frozen_string_literal: true

require "rails_helper"

# knowledge_base_workflows is the audit trail of article state transitions: one
# row per action, saying who moved an article, when, and between which statuses.
#
# The action vocabulary is owned by the database (the valid_kb_workflow_action
# CHECK constraint), not by the model, so these examples assert the model agrees
# with it in both directions — a value Postgres rejects must not pass validation,
# and every value it accepts must actually save.
RSpec.describe KnowledgeBase::Workflow do
  let(:article) { create(:kb_article) }
  let(:user) { create(:user) }

  describe "the action vocabulary" do
    it "mirrors the database CHECK constraint exactly" do
      definition = ActiveRecord::Base.connection.select_value(<<~SQL.squish)
        SELECT pg_get_constraintdef(oid) FROM pg_constraint
        WHERE conname = 'valid_kb_workflow_action'
      SQL

      constrained = definition.to_s.scan(/'([a-z]+)'::character varying/).flatten.uniq

      expect(constrained).not_to be_empty, "valid_kb_workflow_action is missing from the test database"
      expect(described_class::VALID_ACTIONS).to match_array(constrained)
    end

    described_class::VALID_ACTIONS.each do |action|
      it "saves a #{action} row" do
        workflow = build(:kb_workflow, article: article, user: user, action: action)

        expect(workflow.save).to be(true)
        expect(workflow.reload.action).to eq(action)
      end
    end

    it "rejects an action the database would refuse" do
      workflow = build(:kb_workflow, article: article, user: user, action: "translation")

      expect(workflow).not_to be_valid
      expect(workflow.errors[:action]).to be_present
    end

    it "requires an action" do
      workflow = build(:kb_workflow, article: article, user: user, action: nil)

      expect(workflow).not_to be_valid
      expect(workflow.errors[:action]).to be_present
    end
  end

  describe "what a row records" do
    it "keeps the statuses the article moved between" do
      workflow = create(:kb_workflow, :publish_action, article: article, user: user)

      expect(workflow.reload).to have_attributes(
        action: "publish",
        from_status: "draft",
        to_status: "published"
      )
    end

    it "leaves from_status null for a creation" do
      workflow = create(:kb_workflow, :create_action, article: article, user: user)

      expect(workflow.reload.from_status).to be_nil
      expect(workflow.to_status).to eq("draft")
    end

    it "stores a human comment and machine metadata" do
      workflow = create(
        :kb_workflow,
        article: article,
        user: user,
        comment: "Updated: content, title",
        metadata: { source: "api", agent_id: "abc" }
      )

      expect(workflow.reload.comment).to eq("Updated: content, title")
      expect(workflow.metadata).to eq("source" => "api", "agent_id" => "abc")
    end

    it "defaults metadata to an empty hash" do
      workflow = described_class.create!(article: article, user: user, action: "review")

      expect(workflow.reload.metadata).to eq({})
    end
  end

  describe "associations" do
    it "belongs to the article it describes and the user who acted" do
      workflow = create(:kb_workflow, article: article, user: user)

      expect(workflow.reload.article).to eq(article)
      expect(workflow.user).to eq(user)
    end

    it "requires an article" do
      workflow = build(:kb_workflow, article: nil, user: user)

      expect(workflow).not_to be_valid
      expect(workflow.errors[:article]).to be_present
    end

    it "requires a user" do
      workflow = build(:kb_workflow, article: article, user: nil)

      expect(workflow).not_to be_valid
      expect(workflow.errors[:user]).to be_present
    end

    it "reads back from the article as its history" do
      create(:kb_workflow, :create_action, article: article, user: user)
      create(:kb_workflow, :publish_action, article: article, user: user)

      expect(article.reload.workflows.count).to eq(2)
    end
  end

  describe ".action_for" do
    it "names a move by where it lands" do
      expect(described_class.action_for("draft", "published")).to eq("publish")
      expect(described_class.action_for("published", "archived")).to eq("archive")
      expect(described_class.action_for("draft", "review")).to eq("review")
    end

    it "calls a move off published back to draft an unpublish" do
      expect(described_class.action_for("published", "draft")).to eq("unpublish")
    end

    it "calls a change that leaves the status alone an edit" do
      expect(described_class.action_for("draft", "draft")).to eq("edit")
      expect(described_class.action_for("published", "published")).to eq("edit")
    end

    it "falls back to edit for a move the vocabulary cannot name" do
      # review -> draft and archived -> draft are restores, not unpublishes.
      expect(described_class.action_for("review", "draft")).to eq("edit")
      expect(described_class.action_for("archived", "draft")).to eq("edit")
    end

    it "only ever returns an action the database accepts" do
      statuses = [ nil, "draft", "review", "published", "archived" ]

      statuses.product(statuses).each do |from, to|
        expect(described_class::VALID_ACTIONS).to include(described_class.action_for(from, to)),
                                            "action_for(#{from.inspect}, #{to.inspect}) left the vocabulary"
      end
    end
  end

  describe ".change_summary" do
    it "lists the fields an edit touched" do
      article.update!(title: "A new title", excerpt: "A new excerpt")

      expect(described_class.change_summary(article)).to eq("Updated: excerpt, title")
    end

    it "is nil when nothing of interest changed" do
      article.update!(title: article.title)

      expect(described_class.change_summary(article)).to be_nil
    end
  end

  describe "scopes" do
    let!(:created) { create(:kb_workflow, :create_action, article: article, user: user, created_at: 3.hours.ago) }
    let!(:edited) { create(:kb_workflow, :edit_action, article: article, user: user, created_at: 2.hours.ago) }
    let!(:published) { create(:kb_workflow, :publish_action, article: article, user: user, created_at: 1.hour.ago) }
    let!(:elsewhere) { create(:kb_workflow, :publish_action) }

    it "reads an article's history oldest first" do
      expect(described_class.for_article(article.id).chronological.to_a).to eq([ created, edited, published ])
    end

    it "reads the most recent first" do
      expect(described_class.for_article(article.id).recent.first).to eq(published)
    end

    it "selects by action" do
      expect(described_class.for_article(article.id).by_action("edit").to_a).to eq([ edited ])
    end

    it "selects by the user who acted" do
      expect(described_class.by_user(user.id)).to match_array([ created, edited, published ])
    end

    it "answers who moved an article into a status" do
      expect(described_class.entering("published")).to match_array([ published, elsewhere ])
    end

    it "answers what left a status" do
      expect(described_class.leaving("published")).to be_empty
      expect(described_class.for_article(article.id).leaving("draft")).to match_array([ edited, published ])
    end
  end

  describe "#status_change?" do
    it "is true when the article moved" do
      expect(build(:kb_workflow, :publish_action)).to be_status_change
    end

    it "is false for an in-place edit" do
      expect(build(:kb_workflow, :edit_action)).not_to be_status_change
    end
  end
end
