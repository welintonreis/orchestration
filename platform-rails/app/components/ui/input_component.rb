module Ui
  # Single reusable text/number/email input for forms and filter boxes
  # across the platform.
  class InputComponent < ApplicationComponent
    # No padding/rounding/sizing here on purpose: those utilities vary by
    # call site (rounded vs rounded-lg, px-2.5 vs px-3, w-56, etc) and
    # Tailwind utility classes share specificity — two conflicting
    # same-specificity classes on one element resolve by stylesheet order,
    # not DOM order, so baking in a default here could silently lose to
    # (or beat) whatever a caller passes via css_class. Sizing is always
    # the caller's responsibility.
    BASE = "bg-surface-inset border border-border-subtle text-text-primary text-sm focus:outline-none focus:border-cyan-600".freeze

    def initialize(name:, type: :text, value: nil, placeholder: nil, min: nil, max: nil,
                    step: nil, css_class: nil, data: {}, id: nil, autocomplete: nil, html_attrs: {})
      @name         = name
      @type         = type
      @value        = value
      @placeholder  = placeholder
      @min          = min
      @max          = max
      @step         = step
      @css_class    = css_class
      @data         = data
      @id           = id
      @autocomplete = autocomplete
      @html_attrs   = html_attrs
    end

    def call
      # Built as a Hash variable (not trailing key:value literal) and
      # merged with html_attrs so Alpine bindings like "x-model" (string
      # keys, invalid as Ruby keyword-call syntax) can be passed through.
      options = { type: @type, placeholder: @placeholder, min: @min, max: @max, step: @step,
                  class: classes, data: @data, id: @id, autocomplete: @autocomplete }.merge(@html_attrs)
      text_field_tag @name, @value, options
    end

    private

    def classes
      [BASE, @css_class].compact.join(" ")
    end
  end
end
