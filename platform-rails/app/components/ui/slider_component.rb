module Ui
  # Single reusable range slider (e.g. CPU/memory limit sliders).
  class SliderComponent < ApplicationComponent
    BASE = "w-full h-1.5 rounded cursor-pointer accent-cyan-500".freeze

    def initialize(name:, min: 0, max: 100, step: 1, value: 0, css_class: nil, oninput: nil, data: {}, id: nil)
      @name      = name
      @min       = min
      @max       = max
      @step      = step
      @value     = value
      @css_class = css_class
      @oninput   = oninput
      @data      = data
      @id        = id
    end

    def call
      tag.input(type: "range", name: @name, min: @min, max: @max, step: @step, value: @value,
                class: classes, oninput: @oninput, data: @data, id: @id)
    end

    private

    def classes
      [BASE, @css_class].compact.join(" ")
    end
  end
end
