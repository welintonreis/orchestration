module Ui
  # Loading placeholder shown while a turbo-frame fetches its real content.
  #
  # Replaces the hand-written animate-pulse blocks that were copy-pasted into
  # containers/images/volumes/secrets/networks/stacks/swarm-services, which
  # differed only in column widths and row count.
  #
  # The point of a skeleton is that the real content lands in the same place it
  # occupied, so :table takes a column spec rather than a plain count — pass the
  # widths of the actual columns and nothing jumps on swap.
  #
  #   render Ui::SkeletonComponent.new(:table, columns: [:check, "w-40", "w-12", :actions], rows: 8)
  #   render Ui::SkeletonComponent.new(:stats, count: 5)
  #   render Ui::SkeletonComponent.new(:cards, count: 6)
  #   render Ui::SkeletonComponent.new(:toolbar)
  #   render Ui::SkeletonComponent.new(:detail)
  #
  # Column spec entries: a Tailwind width class for a normal cell, :check for a
  # leading checkbox, :actions for a trailing button cluster.
  class SkeletonComponent < ApplicationComponent
    VARIANTS = %i[table stats cards toolbar detail].freeze

    # Grid used by the stat-tile rows across the app (dashboard/_stat_card).
    STATS_GRID = "grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-4 mb-6".freeze

    # `grid` overrides STATS_GRID for screens whose stat row isn't the
    # dashboard's 5-column one (security uses 4) — a skeleton laid out on a
    # different grid than the real content defeats the whole point.
    def initialize(variant = :table, columns: nil, rows: 8, count: 5, toolbar: false, css_class: nil, grid: nil, card: true)
      @variant   = VARIANTS.include?(variant) ? variant : :table
      @columns   = columns.presence || [ :check, "w-40", "w-24", "w-32", "w-20", :actions ]
      @rows      = rows
      @count     = count
      @toolbar   = toolbar
      @css_class = css_class
      @grid      = grid || STATS_GRID
      @card      = card
    end

    private

    attr_reader :variant, :columns, :rows, :count, :toolbar, :css_class, :grid, :card

    # `card: false` for skeletons that sit *inside* an existing card — a second
    # bordered box nested in the first is exactly the layout noise this is
    # supposed to avoid.
    def card_classes
      [ ("bg-surface-raised border border-border rounded-xl overflow-hidden" if card),
        "animate-pulse", css_class ].compact.join(" ")
    end

    # Headers are uniform bars — matching each header's exact text width buys
    # nothing, the row height is what prevents the shift.
    def header_bar(col)
      case col
      when :check   then tag.div(class: "w-3.5 h-3.5 bg-surface-active rounded")
      when :actions then nil
      else               tag.div(class: "h-3 w-16 bg-surface-active rounded")
      end
    end

    def body_cell(col)
      case col
      when :check
        tag.div(class: "w-3.5 h-3.5 bg-surface-inset rounded")
      when :actions
        tag.div(class: "flex items-center justify-end gap-2") do
          safe_join(Array.new(3) { tag.div(class: "h-7 w-7 bg-surface-inset rounded") })
        end
      else
        tag.div(class: "h-3.5 #{col} bg-surface-inset rounded")
      end
    end
  end
end
