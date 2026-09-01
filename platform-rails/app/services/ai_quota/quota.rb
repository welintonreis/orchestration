module AiQuota
  # One quota window, normalized across providers.
  #
  # Naming trap worth knowing: remaining_pct is a percentage, while used/total
  # are raw counts — except for claude and codex, where the provider reports in
  # percent and total is literally 100.
  Quota = Struct.new(
    :name, :model_key, :used, :total, :remaining_pct,
    :reset_at, :recurring, :unlimited, :severity, :locked_reason,
    keyword_init: true
  ) do
    GREEN = 70
    YELLOW = 30
    EMPTY = 5

    # The chain every provider falls back through: an explicit percentage the
    # provider gave us, else one derived from the counts.
    def self.remaining_from(remaining: nil, used: nil, total: nil)
      return [ remaining.to_f.round, 0 ].max if remaining
      return 0 if total.to_i.zero?
      return 100 if used.nil? || used.to_f.negative?
      return 0 if used.to_f >= total.to_f

      ((total.to_f - used.to_f) / total.to_f * 100).round
    end

    def color
      return :green if unlimited

      case remaining_pct.to_i
      when (GREEN + 1)..Float::INFINITY then :green
      when YELLOW..GREEN                then :yellow
      else                                   :red
      end
    end

    def empty?
      !unlimited && total.to_i.positive? && remaining_pct.to_i <= EMPTY
    end

    def locked?
      locked_reason.present?
    end
  end
end
