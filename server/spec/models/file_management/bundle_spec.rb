# frozen_string_literal: true

require "rails_helper"

# NOTE: file_type is irrelevant to bundle membership — a bundle's concern is the
# object's *role* (scene/voiceover/music/...), not its media type. These specs use
# plain file_objects and assign roles. Realistic video/audio assets are exercised
# in increment 3, once FileManagement::ProcessingJob's job_type enum is extended to
# allow the video_processing/audio_processing types its after_create already queues
# (a pre-existing defect: creating a video/audio object currently raises). See the
# campaign decision log (deferred to increment 3, which owns ProcessingJob job_types).
RSpec.describe FileManagement::Bundle do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:bundle) { create(:file_bundle, account: account, created_by: user) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_inclusion_of(:bundle_type).in_array(described_class::BUNDLE_TYPES) }
    it { is_expected.to validate_inclusion_of(:status).in_array(described_class::STATUSES) }

    it "is valid from the factory" do
      expect(bundle).to be_valid
    end
  end

  describe "associations" do
    it "belongs to an account and creator" do
      expect(bundle.account).to eq(account)
      expect(bundle.created_by).to eq(user)
    end

    it "optionally links the producing mission" do
      template = create(:ai_mission_template, :content_production)
      mission = create(:ai_mission, :content_production, account: account, created_by: user, mission_template: template)
      bundle.update!(mission: mission)
      expect(bundle.reload.mission).to eq(mission)
    end

    it "optionally points at a primary (rendered) artifact" do
      artifact = create(:file_object, account: account, uploaded_by: user)
      bundle.update!(primary_object: artifact)
      expect(bundle.reload.primary_object).to eq(artifact)
    end
  end

  describe "#add_object!" do
    let(:scene_a) { create(:file_object, account: account, uploaded_by: user) }
    let(:scene_b) { create(:file_object, account: account, uploaded_by: user) }

    it "assigns the object to the bundle with role + position" do
      bundle.add_object!(scene_a, role: "scene")
      expect(scene_a.reload.bundle).to eq(bundle)
      expect(scene_a.bundle_role).to eq("scene")
      expect(scene_a.bundle_position).to eq(1)
    end

    it "auto-increments position within a role sequence" do
      bundle.add_object!(scene_a, role: "scene")
      bundle.add_object!(scene_b, role: "scene")
      expect(scene_b.reload.bundle_position).to eq(2)
    end

    it "honours an explicit position" do
      bundle.add_object!(scene_a, role: "scene", position: 5)
      expect(scene_a.reload.bundle_position).to eq(5)
    end

    it "rejects an unknown role" do
      expect { bundle.add_object!(scene_a, role: "bogus") }.to raise_error(ArgumentError)
    end
  end

  describe "asset queries" do
    let(:scene_1) { create(:file_object, account: account, uploaded_by: user) }
    let(:scene_2) { create(:file_object, account: account, uploaded_by: user) }
    let(:vo)      { create(:file_object, account: account, uploaded_by: user) }
    let(:track)   { create(:file_object, account: account, uploaded_by: user) }

    before do
      bundle.add_object!(scene_2, role: "scene", position: 2)
      bundle.add_object!(scene_1, role: "scene", position: 1)
      bundle.add_object!(vo, role: "voiceover")
      bundle.add_object!(track, role: "music")
    end

    it "returns scenes ordered by position" do
      expect(bundle.scenes.map(&:id)).to eq([scene_1.id, scene_2.id])
    end

    it "returns voiceover and music as audio tracks" do
      expect(bundle.audio_tracks).to contain_exactly(vo, track)
      expect(bundle.voiceover).to eq(vo)
      expect(bundle.music).to eq(track)
    end

    it "counts members" do
      expect(bundle.object_count).to eq(4)
      expect(bundle.scenes.count).to eq(2)
    end
  end

  describe "shared download links (reuses FileManagement::Share)" do
    let(:render) { create(:file_object, account: account, uploaded_by: user) }

    describe "#share_primary!" do
      before { bundle.update!(primary_object: render) }

      it "creates a public, expiring, download-limited share for the finished render" do
        share = bundle.share_primary!(created_by: user, expires_in: 7.days, max_downloads: 5)

        expect(share).to be_a(FileManagement::Share)
        expect(share.object).to eq(render)
        expect(share.account).to eq(account)
        expect(share.created_by).to eq(user)
        expect(share).to be_public_link
        expect(share.download_allowed?).to be(true)
        expect(share).to be_active
        expect(share.max_downloads).to eq(5)
        expect(share.expires_at).to be_within(1.minute).of(7.days.from_now)
        expect(share.share_token).to be_present
      end

      it "raises when the bundle has no finished render" do
        bundle.update!(primary_object: nil)
        expect { bundle.share_primary!(created_by: user) }.to raise_error(ArgumentError, /no primary/i)
      end
    end

    describe "#share_all! + #download_manifest" do
      let(:scene) { create(:file_object, account: account, uploaded_by: user) }
      let(:audio) { create(:file_object, account: account, uploaded_by: user) }

      before do
        bundle.add_object!(scene, role: "scene")
        bundle.add_object!(audio, role: "music")
      end

      it "creates one public expiring share per member object" do
        shares = bundle.share_all!(created_by: user, expires_in: 1.day)
        expect(shares.length).to eq(2)
        expect(shares).to all(be_a(FileManagement::Share))
        expect(shares.map(&:file_object_id)).to contain_exactly(scene.id, audio.id)
        expect(shares).to all(be_public_link)
      end

      it "returns a download manifest with a host-relative link per shared member" do
        bundle.share_all!(created_by: user, expires_in: 1.day)
        manifest = bundle.download_manifest

        expect(manifest.length).to eq(2)
        entry = manifest.first
        expect(entry).to include(:filename, :bundle_role, :share_token, :share_path, :download_path, :expires_at)
        expect(entry[:download_path]).to include("/shared/")
        expect(entry[:download_path]).to end_with("/download")
      end
    end
  end

  describe "object membership (FileManagement::Object side)" do
    let(:obj) { create(:file_object, account: account, uploaded_by: user) }

    it "exposes a belongs_to :bundle association" do
      bundle.add_object!(obj, role: "document")
      expect(obj.reload.bundle).to eq(bundle)
    end

    it "validates bundle_role against the allowed set" do
      obj.bundle_role = "not_a_role"
      expect(obj).not_to be_valid
      expect(obj.errors[:bundle_role]).to be_present
    end

    it "nullifies membership when the bundle is destroyed (files survive)" do
      bundle.add_object!(obj, role: "document")
      bundle.destroy!
      expect(obj.reload.bundle_id).to be_nil
      expect(FileManagement::Object.exists?(obj.id)).to be(true)
    end

    it "scopes objects to a bundle" do
      bundle.add_object!(obj, role: "document")
      expect(FileManagement::Object.in_bundle(bundle.id)).to include(obj)
    end
  end
end
