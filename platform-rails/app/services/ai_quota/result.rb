module AiQuota
  # What a fetcher returns. `message` set means the account couldn't be read —
  # expired credential, provider outage — and the card shows that instead of
  # bars, rather than pretending the quota is zero.
  Result = Struct.new(:plan, :message, :quotas, :extra, keyword_init: true) do
    def self.error(message) = new(message: message, quotas: [], extra: {})

    def quotas = self[:quotas] || []
    def extra  = self[:extra]  || {}
    def ok?    = message.blank?

    def lowest = quotas.reject(&:unlimited).min_by { |q| q.remaining_pct.to_i }
    def next_reset = quotas.filter_map(&:reset_at).min
    def any_empty? = quotas.any?(&:empty?)
  end
end
