module Ui
  # Single reusable button for every action across the platform — row icon
  # actions (Stop/Restart/Kill/...), labeled pill buttons (Scale/Apply/Limpar),
  # and bulk-action bars. Renders link_to for GET, button_to otherwise, so
  # destructive/state-changing actions keep CSRF protection automatically.
  class ButtonComponent < ApplicationComponent
    VARIANTS = {
      gray:        "bg-gray-800 hover:bg-gray-700 text-gray-400 hover:text-gray-200 border border-gray-700",
      cyan:        "bg-gray-800 hover:bg-cyan-900/40 text-gray-400 hover:text-cyan-300 border border-gray-700 hover:border-cyan-800",
      green:       "bg-gray-800 hover:bg-green-900/40 text-gray-400 hover:text-green-300 border border-gray-700 hover:border-green-800",
      yellow:      "bg-gray-800 hover:bg-yellow-900/40 text-gray-400 hover:text-yellow-300 border border-gray-700 hover:border-yellow-800",
      red:         "bg-gray-800 hover:bg-red-900/40 text-gray-400 hover:text-red-400 border border-gray-700 hover:border-red-800",
      blue:        "bg-gray-800 hover:bg-blue-900/40 text-gray-400 hover:text-blue-300 border border-gray-700 hover:border-blue-800",
      purple:      "bg-gray-800 hover:bg-purple-900/40 text-gray-400 hover:text-purple-300 border border-gray-700 hover:border-purple-800",
      solid_cyan:  "bg-cyan-900/60 hover:bg-cyan-800/80 text-cyan-300 border border-cyan-700/50",
      solid_red:   "bg-red-700/50 hover:bg-red-600/60 text-red-200 border border-red-600/60",
      solid_orange:"bg-orange-900/40 hover:bg-orange-800/50 text-orange-300 border border-orange-700/40",
      solid_purple:"bg-purple-950/40 hover:bg-purple-900/60 text-purple-400 border border-purple-900/50",
      ghost:       "bg-gray-800 hover:bg-gray-700 text-gray-300 hover:text-white border border-gray-700",
    }.freeze

    SIZES = {
      icon: "p-1 rounded",
      sm:   "px-2.5 py-1.5 text-xs font-medium rounded-lg",
      md:   "px-3 py-1.5 text-sm font-medium rounded-lg",
    }.freeze

    def initialize(url:, method: :get, variant: :gray, size: :icon, label: nil, icon: nil,
                   title: nil, confirm: nil, frame: nil, turbo: nil, loading: false, disabled: false,
                   css_class: nil, form_class: nil, icon_css_class: "w-4 h-4")
      @url            = url
      @method         = method
      @variant        = variant
      @size           = size
      @label          = label
      @icon           = icon
      @title          = title
      @confirm        = confirm
      @frame          = frame
      @turbo          = turbo
      @loading        = loading
      @disabled       = disabled
      @css_class      = css_class
      @form_class     = form_class
      @icon_css_class = icon_css_class
    end

    def call
      if @method.to_sym == :get
        link_to @url, class: classes, title: @title, data: data_attrs do
          inner_content
        end
      else
        opts = { method: @method, class: classes, title: @title, data: data_attrs, disabled: @disabled }
        opts[:form] = { class: @form_class } if @form_class
        button_to @url, opts do
          inner_content
        end
      end
    end

    private

    def classes
      [
        "transition-colors inline-flex items-center justify-center gap-1.5",
        size_classes,
        variant_classes,
        @css_class,
      ].compact.join(" ")
    end

    # variant: a VARIANTS key (:cyan, :red, ...) for the standard palette,
    # or a raw "bg-... text-... border-..." string for a one-off shade.
    def variant_classes
      @variant.is_a?(String) ? @variant : VARIANTS.fetch(@variant, VARIANTS[:gray])
    end

    # size: a SIZES key (:icon, :sm, :md), or a raw "p-x py-y ..." string
    # for a one-off size that doesn't fit the palette.
    def size_classes
      @size.is_a?(String) ? @size : SIZES.fetch(@size, SIZES[:icon])
    end

    def data_attrs
      {
        turbo: @turbo,
        turbo_confirm: @confirm,
        turbo_frame: @frame,
        action: (@loading ? "click->loading#start" : nil),
      }.compact
    end

    # Most callers pass icon:/label:, but a block is supported for one-off
    # SVGs that aren't in the shared ACTION_ICONS set.
    def inner_content
      return content if content?

      parts = []
      parts << helpers.action_icon(@icon, css_class: @icon_css_class) if @icon
      parts << @label if @label
      safe_join(parts)
    end
  end
end
