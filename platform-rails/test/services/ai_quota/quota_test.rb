require "test_helper"

module AiQuota
  class QuotaTest < ActiveSupport::TestCase
    test "remaining falls back through the chain in order" do
      # An explicit percentage always wins over the counts.
      assert_equal 42, Quota.remaining_from(remaining: 42, used: 99, total: 100)
      # Derived from counts.
      assert_equal 75, Quota.remaining_from(used: 30, total: 120)
      # A zero total can't be divided — nothing left, not everything left.
      assert_equal 0, Quota.remaining_from(used: 0, total: 0)
      # Provider didn't say how much was used, but there is a quota.
      assert_equal 100, Quota.remaining_from(total: 50)
      # Over budget clamps at zero rather than going negative.
      assert_equal 0, Quota.remaining_from(used: 80, total: 50)
      assert_equal 0, Quota.remaining_from(remaining: -5)
    end

    test "colors sit on the documented thresholds" do
      assert_equal :green,  quota(71).color
      assert_equal :yellow, quota(70).color
      assert_equal :yellow, quota(30).color
      assert_equal :red,    quota(29).color
      assert_equal :green,  Quota.new(remaining_pct: 0, unlimited: true).color
    end

    test "empty means nearly exhausted, and unlimited is never empty" do
      assert quota(5).empty?
      assert_not quota(6).empty?
      # No quota at all isn't "empty" — there's nothing to run out of.
      assert_not quota(0, total: 0).empty?
      assert_not Quota.new(remaining_pct: 0, total: 100, unlimited: true).empty?
    end

    private

    def quota(remaining, total: 100)
      Quota.new(remaining_pct: remaining, total: total)
    end
  end
end
