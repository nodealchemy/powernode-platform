# frozen_string_literal: true

require 'prawn'

# Renders a multi-page PDF document for a content production's document
# deliverable, using Prawn (mirrors the Prawn idioms used by the reports
# pipeline). Input is a title plus an ordered list of sections; each section
# becomes its own page, so a document's page_count is 1 (title page) + sections.
#
#   sections: [{ "heading" => "...", "body" => "..." }, ...]
class DocumentPdfService
  # Build the Prawn::Document (not yet rendered) — exposed so callers/tests can
  # inspect page_count before rendering to bytes.
  def build(title:, sections: [])
    Prawn::Document.new(page_size: 'A4', margin: 48) do |pdf|
      pdf.font_size(24) { pdf.text title.to_s, style: :bold }
      pdf.move_down 8
      pdf.font_size(9) do
        pdf.text "Generated #{Time.now.utc.strftime('%Y-%m-%d %H:%M UTC')}", color: '888888'
      end
      pdf.stroke_horizontal_rule
      pdf.move_down 16

      Array(sections).each do |section|
        heading = section['heading'] || section[:heading]
        body    = section['body'] || section[:body]

        pdf.start_new_page
        if heading && !heading.to_s.empty?
          pdf.font_size(16) { pdf.text heading.to_s, style: :bold }
          pdf.move_down 6
        end
        pdf.font_size(11) { pdf.text body.to_s } if body && !body.to_s.empty?
      end

      pdf.number_pages 'Page <page> of <total>',
                       at: [pdf.bounds.right - 120, 0], align: :right, size: 8
    end
  end

  # Render the document to a binary PDF String.
  def render(title:, sections: [])
    build(title: title, sections: sections).render
  end
end
