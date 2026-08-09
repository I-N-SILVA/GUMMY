# frozen_string_literal: true

# Which currency a local Stripe Connect account settles its charges in.
#
# Gumroad's historical default is that every charge settles in USD regardless of where the seller is.
# A market listed here instead settles in its own currency, which is what local payment methods
# require — Stripe only offers Pix in BRL, only offers OXXO in MXN, and so on.
#
# Adding a market is one entry: the country, the currency Stripe settles that country's local
# accounts in, and the feature flag that gates the rollout. Everything downstream (the charge
# processor, PurchaseSettlement, the local payment method registry) reads the answer from here rather
# than testing for a specific country, so no other file needs editing to open a new market.
#
# An unlisted country settles in USD, which is every country today until a flag is switched on.
module SettlementCurrencyPolicy
  Market = Struct.new(:currency, :feature_flag, keyword_init: true)

  MARKETS = {
    Compliance::Countries::BRA.alpha2 => Market.new(currency: Currency::BRL, feature_flag: :brl_settlement)
  }.freeze

  # `seller` is the flag's actor, so a market can be rolled out to one seller at a time rather than
  # to a whole country at once.
  def self.currency_for(country_code, seller:)
    market = MARKETS[country_code]
    return Currency::USD if market.nil?
    return Currency::USD unless Feature.active?(market.feature_flag, seller)

    market.currency
  end

  def self.market?(country_code)
    MARKETS.key?(country_code)
  end

  def self.countries
    MARKETS.keys
  end
end
