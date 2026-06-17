module Ui
  # Single reusable pill/badge for status labels, counts, and tags across
  # the platform (container status, "Dangling", task state, infra count, etc).
  class BadgeComponent < ApplicationComponent
    COLORS = {
      gray:   { bg: "bg-gray-800 text-gray-400 border-gray-700",          dot: "bg-gray-400" },
      green:  { bg: "bg-green-900/50 text-green-300 border-green-800/50", dot: "bg-green-400" },
      red:    { bg: "bg-red-900/50 text-red-300 border-red-800/50",       dot: "bg-red-400" },
      orange: { bg: "bg-orange-900/40 text-orange-400 border-orange-700/50", dot: "bg-orange-400" },
      yellow: { bg: "bg-yellow-900/50 text-yellow-300 border-yellow-800/50", dot: "bg-yellow-400" },
      blue:   { bg: "bg-blue-900/50 text-blue-300 border-blue-800/50",    dot: "bg-blue-400" },
      cyan:   { bg: "bg-cyan-900/60 text-cyan-400 border-cyan-800",       dot: "bg-cyan-400" },
      purple: { bg: "bg-purple-900/50 text-purple-300 border-purple-800/50", dot: "bg-purple-400" },
    }.freeze

    SIZES = {
      xs: "px-1.5 py-0.5 text-[10px] font-semibold",
      sm: "px-2 py-0.5 text-xs font-medium",
      md: "px-2 py-1 text-xs font-medium",
    }.freeze

    # color: a COLORS key (:green, :red, ...) for the standard palette, or
    # a raw "bg-... text-... border-..." string for a one-off shade that
    # doesn't fit the palette — passed straight through instead of being
    # fought over via css_class (same-specificity Tailwind utilities
    # resolve by stylesheet order, not DOM order, so layering an override
    # in css_class on top of a COLORS entry isn't reliable).
    def initialize(color: :gray, size: :sm, dot: false, css_class: nil)
      @color     = color
      @size      = size
      @dot       = dot
      @css_class = css_class
    end

    def call
      tag.span(class: classes) do
        @dot ? safe_join([dot_html, content]) : content
      end
    end

    private

    def palette
      COLORS[@color] || COLORS[:gray]
    end

    def color_classes
      @color.is_a?(String) ? @color : palette[:bg]
    end

    def classes
      ["inline-flex items-center gap-1.5 rounded border", SIZES.fetch(@size, SIZES[:sm]), color_classes, @css_class].compact.join(" ")
    end

    def dot_html
      dot_color = @color.is_a?(String) ? "bg-gray-400" : palette[:dot]
      tag.span class: "w-1.5 h-1.5 rounded-full flex-shrink-0 #{dot_color}"
    end
  end
end
