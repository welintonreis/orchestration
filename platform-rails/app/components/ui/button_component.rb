module Ui
  # Single reusable button for every action across the platform — row icon
  # actions (Stop/Restart/Kill/...), labeled pill buttons (Scale/Apply/Limpar),
  # and bulk-action bars. Renders link_to for GET, button_to otherwise, so
  # destructive/state-changing actions keep CSRF protection automatically.
  class ButtonComponent < ApplicationComponent
    VARIANTS = {
      gray:        "bg-surface-inset hover:bg-surface-active text-text-secondary hover:text-text-primary border border-border-subtle dark:hover:bg-surface-inset dark:hover:border-border-subtle",
      cyan:        "bg-surface-inset hover:bg-cyan-100 dark:hover:bg-surface-inset text-text-secondary hover:text-cyan-700 dark:hover:text-cyan-300 border border-border-subtle hover:border-cyan-300 dark:hover:border-cyan-500/40",
      green:       "bg-surface-inset hover:bg-green-100 dark:hover:bg-surface-inset text-text-secondary hover:text-green-700 dark:hover:text-green-300 border border-border-subtle hover:border-green-300 dark:hover:border-green-500/40",
      yellow:      "bg-surface-inset hover:bg-yellow-100 dark:hover:bg-surface-inset text-text-secondary hover:text-yellow-700 dark:hover:text-amber-300 border border-border-subtle hover:border-yellow-300 dark:hover:border-amber-500/40",
      red:         "bg-surface-inset hover:bg-red-100 dark:hover:bg-surface-inset text-text-secondary hover:text-red-600 dark:hover:text-red-400 border border-border-subtle hover:border-red-300 dark:hover:border-red-500/40",
      blue:        "bg-surface-inset hover:bg-blue-100 dark:hover:bg-surface-inset text-text-secondary hover:text-blue-700 dark:hover:text-blue-300 border border-border-subtle hover:border-blue-300 dark:hover:border-blue-500/40",
      purple:      "bg-surface-inset hover:bg-purple-100 dark:hover:bg-surface-inset text-text-secondary hover:text-purple-700 dark:hover:text-purple-300 border border-border-subtle hover:border-purple-300 dark:hover:border-purple-500/40",
      solid_cyan:  "bg-cyan-100 dark:bg-cyan-500/12 hover:bg-cyan-200 dark:hover:bg-cyan-500/20 text-cyan-700 dark:text-cyan-300 border border-cyan-300 dark:border-cyan-500/30",
      solid_red:   "bg-red-200 dark:bg-red-500/14 hover:bg-red-300 dark:hover:bg-red-500/22 text-red-800 dark:text-red-300 border border-red-400 dark:border-red-500/35",
      solid_orange:"bg-orange-100 dark:bg-brand/[0.08] hover:bg-orange-200 dark:hover:bg-brand/[0.16] text-orange-700 dark:text-orange-300 border border-orange-300 dark:border-brand/35",
      solid_purple:"bg-purple-100 dark:bg-purple-500/10 hover:bg-purple-200 dark:hover:bg-purple-500/18 text-purple-700 dark:text-purple-300 border border-purple-300 dark:border-purple-500/30",
      ghost:       "bg-surface-inset hover:bg-surface-active text-text-secondary hover:text-text-primary border border-border-subtle dark:hover:bg-surface-inset",
    }.freeze

    SIZES = {
      icon: "p-1.5 rounded-md",
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
