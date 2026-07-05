module Ui
  # Single reusable pill/badge for status labels, counts, and tags across
  # the platform (container status, "Dangling", task state, infra count, etc).
  class BadgeComponent < ApplicationComponent
    COLORS = {
      gray:   { bg: "bg-surface-inset text-text-secondary border-border-subtle", dot: "bg-gray-400" },
      green:  { bg: "bg-green-100 dark:bg-green-500/12 text-green-700 dark:text-green-300 border-green-300 dark:border-green-500/28", dot: "bg-green-500" },
      red:    { bg: "bg-red-100 dark:bg-red-500/12 text-red-700 dark:text-red-300 border-red-300 dark:border-red-500/28", dot: "bg-red-500" },
      orange: { bg: "bg-orange-100 dark:bg-brand/12 text-orange-700 dark:text-orange-300 border-orange-300 dark:border-brand/30", dot: "bg-brand" },
      yellow: { bg: "bg-yellow-100 dark:bg-amber-500/12 text-yellow-700 dark:text-amber-300 border-yellow-300 dark:border-amber-500/28", dot: "bg-amber-500" },
      blue:   { bg: "bg-blue-100 dark:bg-blue-500/12 text-blue-700 dark:text-blue-300 border-blue-300 dark:border-blue-500/28", dot: "bg-blue-500" },
      cyan:   { bg: "bg-cyan-100 dark:bg-cyan-500/14 text-cyan-700 dark:text-cyan-300 border-cyan-300 dark:border-cyan-500/30", dot: "bg-cyan-500" },
      purple: { bg: "bg-purple-100 dark:bg-purple-500/12 text-purple-700 dark:text-purple-300 border-purple-300 dark:border-purple-500/28", dot: "bg-purple-500" },
    }.freeze

    SIZES = {
      xs: "px-1.5 py-0.5 text-[10px] font-mono font-semibold",
      sm: "px-2.5 py-0.5 text-[11px] font-mono font-semibold tracking-wide",
      md: "px-3 py-1 text-xs font-mono font-semibold tracking-wide",
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
      ["inline-flex items-center gap-1.5 rounded-full border", SIZES.fetch(@size, SIZES[:sm]), color_classes, @css_class].compact.join(" ")
    end

    def dot_html
      dot_color = @color.is_a?(String) ? "bg-gray-400" : palette[:dot]
      tag.span class: "w-1.5 h-1.5 rounded-full flex-shrink-0 #{dot_color}"
    end
  end
end
