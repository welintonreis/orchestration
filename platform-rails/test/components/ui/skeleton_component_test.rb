require "test_helper"
require "view_component/test_helpers"
require "nokogiri"

module Ui
  class SkeletonComponentTest < ActiveSupport::TestCase
    include ViewComponent::TestHelpers

    # No Capybara in this project — Nokogiri ships with Rails and is enough
    # to count elements.
    def html
      Nokogiri::HTML.fragment(rendered_content)
    end

    test "table renders one header cell and one body cell per column, for every row" do
      render_inline(SkeletonComponent.new(:table, columns: [ :check, "w-40", :actions ], rows: 4))

      assert_equal 3, html.css("thead th").size
      assert_equal 4, html.css("tbody tr").size
      assert_equal 12, html.css("tbody td").size
      # :actions renders a button cluster, not a single bar — the shape that
      # keeps the last column from collapsing when the real rows land.
      assert_equal 3, html.css("tbody tr:first-child td:last-child div div").size
    end

    test "column width class reaches the bar" do
      render_inline(SkeletonComponent.new(:table, columns: [ "w-40" ], rows: 1))
      assert html.css("tbody td div.w-40").any?, "esperava tbody td div.w-40"
    end

    test "is announced as busy and its bars are hidden from screen readers" do
      render_inline(SkeletonComponent.new(:table, rows: 1))
      assert html.css("[aria-busy='true']").any?, "esperava [aria-busy='true']"
      assert html.css("[aria-hidden='true'] table").any?, "esperava [aria-hidden='true'] table"
    end

    test "unknown variant falls back to table instead of rendering nothing" do
      render_inline(SkeletonComponent.new(:nope, rows: 2))
      assert html.css("table").any?, "esperava table"
    end

    test "stats and cards honour count" do
      render_inline(SkeletonComponent.new(:stats, count: 6))
      assert_equal 6, html.css(".grid > div").size

      render_inline(SkeletonComponent.new(:cards, count: 3))
      assert_equal 3, html.css(".grid > div").size
    end
  end
end
