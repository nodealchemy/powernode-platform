# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClamavService do
  describe '.scan_file' do
    it 'returns clean result with placeholder message' do
      result = described_class.scan_file('/path/to/file.txt')

      expect(result[:clean]).to be true
      expect(result[:message]).to eq('File scan not implemented')
    end

    it 'accepts any file path' do
      result = described_class.scan_file('/any/path/file.pdf')

      expect(result).to be_a(Hash)
      expect(result[:clean]).to be true
    end
  end

  describe '.available?' do
    it 'returns false since ClamAV is not implemented' do
      expect(described_class.available?).to be false
    end
  end
end
