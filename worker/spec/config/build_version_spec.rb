# frozen_string_literal: true

require 'tmpdir'
require 'json'
require_relative '../../config/build_version'

# The worker cannot require server/config/version.rb, so config/build_version.rb
# is the worker's small reader. It must resolve the SAME version string as
# Powernode::Version: BUILD_INFO.json, then `git describe` (dev), then a fallback.
RSpec.describe PowernodeWorker::BuildVersion do
  def write_info(dir, hash)
    path = File.join(dir, 'BUILD_INFO.json')
    File.write(path, JSON.generate(hash))
    path
  end

  describe '.version_from_describe' do
    it 'is the plain tag on an exact tag' do
      expect(described_class.version_from_describe('0.2.0-0-gabc1234', 'master')).to eq('0.2.0')
    end

    it 'guesses the next minor off develop' do
      expect(described_class.version_from_describe('0.2.0-137-gabc1234', 'develop')).to eq('0.3.0-dev.137+abc1234')
    end

    it 'is rc on release/ and hotfix/ branches' do
      expect(described_class.version_from_describe('0.2.0-5-gabc1234', 'release/0.3.0')).to eq('0.3.0-rc.5+abc1234')
      expect(described_class.version_from_describe('0.2.0-2-gabc1234', 'hotfix/0.2.1')).to eq('0.2.1-rc.2+abc1234')
    end

    it 'is nil when unusable' do
      expect(described_class.version_from_describe(nil, 'develop')).to be_nil
    end
  end

  describe '.resolve' do
    it 'prefers BUILD_INFO.json' do
      Dir.mktmpdir do |dir|
        path = write_info(dir, version: '0.4.0-dev.3+abc1234')
        expect(described_class.resolve(build_info_path: path)).to eq('0.4.0-dev.3+abc1234')
      end
    end

    it 'falls back to git describe, then to 0.0.0-dev.0' do
      missing = File.join(Dir.tmpdir, 'no-such-build-info.json')
      allow(described_class).to receive(:git_output).with("describe --tags --long --match '[0-9]*.[0-9]*.[0-9]*'").and_return('0.2.0-9-g1234567')
      allow(described_class).to receive(:git_output).with('rev-parse --abbrev-ref HEAD').and_return('develop')
      expect(described_class.resolve(build_info_path: missing)).to eq('0.3.0-dev.9+1234567')

      allow(described_class).to receive(:git_output).and_return(nil)
      allow(described_class).to receive(:warn)
      expect(described_class.resolve(build_info_path: missing)).to eq('0.0.0-dev.0')
    end
  end
end
