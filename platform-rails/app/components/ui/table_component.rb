module Ui
  # Single reusable table shell (header row + tbody) for every list page.
  # Row markup stays page-specific (passed as the block), since columns and
  # cell content are wildly different per resource — this just DRYs up the
  # <table>/<thead> boilerplate and keeps header styling consistent.
  class TableComponent < ApplicationComponent
    def initialize(headers: [], css_class: nil)
      # headers: array of String, or { label:, align: :right, width: "w-8" }
      @headers   = headers
      @css_class = css_class
    end

    private

    def header_class(h)
      align = h.is_a?(Hash) ? h[:align] : nil
      width = h.is_a?(Hash) ? h[:width] : nil
      [
        "px-4 py-3 text-[10px] font-mono font-semibold text-text-muted uppercase tracking-wider",
        align == :right ? "text-right" : nil,
        align == :center ? "text-center" : nil,
        width,
      ].compact.join(" ")
    end

    def header_label(h)
      h.is_a?(Hash) ? h[:label] : h
    end
  end
end
