# frozen_string_literal: true

class SettlementConversion
  include CurrencyHelper

  attr_reader :currency, :conversion_rate

  def self.for(merchant_account)
    new(currency: merchant_account.settlement_currency)
  end

  def initialize(currency:, conversion_rate: nil)
    @currency = currency.to_s
    @conversion_rate = usd? ? nil : (conversion_rate || get_rate(@currency))
  end

  def usd?
    currency == Currency::USD
  end

  def convert(usd_cents)
    return usd_cents if usd?

    usd_cents_to_currency(currency, usd_cents, conversion_rate)
  end
end
