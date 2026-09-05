# frozen_string_literal: true

module SettlementCurrencyPolicy
  Market = Struct.new(:currency, :feature_flag, keyword_init: true)

  MARKETS = {
    Compliance::Countries::BRA.alpha2 => Market.new(currency: Currency::BRL, feature_flag: :brl_settlement)
  }.freeze

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
