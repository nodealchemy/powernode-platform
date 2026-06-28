# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DocumentPdfService do
  subject(:service) { described_class.new }

  let(:sections) do
    [
      { 'heading' => 'Introduction', 'body' => 'Once upon a time.' },
      { 'heading' => 'Chapter 1', 'body' => 'The story begins.' },
      { 'heading' => 'Chapter 2', 'body' => 'It continues.' }
    ]
  end

  describe '#build' do
    it 'produces one page for the title plus one page per section' do
      doc = service.build(title: 'My Story', sections: sections)
      expect(doc.page_count).to eq(1 + sections.length)
    end

    it 'produces a single title page when there are no sections' do
      expect(service.build(title: 'Empty', sections: []).page_count).to eq(1)
    end

    it 'tolerates sections missing a heading or body' do
      doc = service.build(title: 'Partial', sections: [{ 'body' => 'no heading' }, { 'heading' => 'no body' }])
      expect(doc.page_count).to eq(3)
    end
  end

  describe '#render' do
    it 'renders a valid, non-empty PDF binary' do
      pdf = service.render(title: 'My Story', sections: sections)
      expect(pdf).to be_a(String)
      expect(pdf).to start_with('%PDF-')
      expect(pdf.bytesize).to be > 800
    end

    it 'renders without raising on empty input' do
      expect { service.render(title: 'Empty', sections: []) }.not_to raise_error
    end
  end
end
