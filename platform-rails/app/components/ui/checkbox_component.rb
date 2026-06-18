module Ui
  # Single reusable checkbox for row-select / bulk-action checkboxes and
  # plain form checkboxes across the platform.
  class CheckboxComponent < ApplicationComponent
    BASE = "rounded border-border-subtle bg-surface-inset cursor-pointer focus:ring-0".freeze
    # text-* / accent-* kept out of BASE and driven by `color:` instead of
    # being layered via css_class — same-specificity Tailwind utilities
    # (e.g. text-cyan-500 baked into BASE vs text-red-500 from a caller)
    # resolve by stylesheet order, not DOM order, so a caller can't
    # reliably override a hardcoded color via css_class.
    COLORS = { cyan: "text-cyan-500 accent-cyan-500", red: "text-red-500 accent-red-500" }.freeze

    # html_attrs: escape hatch for attributes Rails' tag builder can't
    # express via keyword args — Alpine bindings like ":checked",
    # ":indeterminate", "@change" are string attribute names, not
    # Ruby-keyword-safe symbols.
    def initialize(name: nil, value: nil, checked: false, size: "w-3.5 h-3.5", color: :cyan,
                   css_class: nil, data: {}, id: nil, html_attrs: {})
      @name       = name
      @value      = value
      @checked    = checked
      @size       = size
      @color      = color
      @css_class  = css_class
      @data       = data
      @id         = id
      @html_attrs = html_attrs
    end

    def call
      # Classic tag(name, hash) form, not tag.input(**kwargs) — the
      # latter coerces via Ruby keyword args, which rejects the
      # string-keyed Alpine attrs (":checked", "@change") in html_attrs.
      tag(:input, { type: "checkbox", name: @name, value: @value, checked: @checked,
                     id: @id, class: classes, data: @data }.merge(@html_attrs))
    end

    private

    def classes
      [@size, BASE, COLORS.fetch(@color, COLORS[:cyan]), @css_class].compact.join(" ")
    end
  end
end
