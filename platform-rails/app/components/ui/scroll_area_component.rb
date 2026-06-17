module Ui
  # Single reusable scrollable container with a consistent thin dark
  # scrollbar (sidebar nav, log viewers, long lists, modals).
  class ScrollAreaComponent < ApplicationComponent
    BASE = "overflow-auto scroll-thin".freeze

    def initialize(css_class: nil, max_height: nil, direction: :y)
      @css_class  = css_class
      @max_height = max_height
      @direction  = direction
    end

    def call
      tag.div(content, class: classes, style: style)
    end

    private

    def classes
      dir = case @direction
            when :y then "overflow-y-auto overflow-x-hidden"
            when :x then "overflow-x-auto overflow-y-hidden"
            else "overflow-auto"
            end
      [dir, "scroll-thin", @css_class].compact.join(" ")
    end

    def style
      @max_height ? "max-height:#{@max_height}" : nil
    end
  end
end
