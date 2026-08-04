# frozen_string_literal: true

# Expresses USD amounts in the currency a merchant account settles in.
#
# Gumroad prices and records every sale in USD, but a merchant account whose settlement currency is
# not USD has to receive the amount from the processor in that currency instead. Today the only such
# account is a Brazilian Stripe Connect account, which must settle in BRL because Stripe only offers
# Pix in BRL (see docs/brazil/multi-currency-settlement.md).
#
# The rate is looked up once and reused for every #convert call on the same instance, so the charge
# amount, the application fee, and the destination transfer of a single charge cannot disagree
# because the rate moved between lookups. It is exposed so it can be copied onto PurchaseSettlement
# at charge time, keeping the settled amount reproducible after rates move.
class SettlementConversion
  include CurrencyHelper

  attr_reader :currency, :conversion_rate

  def self.for(merchant_account)
    new(currency: merchant_account.settlement_currency)
  end

  def initialize(currency:)
    @currency = currency.to_s
    # Deliberately skipped for USD so the existing USD path gains no rate lookup, and therefore no
    # Redis or exchange-rate HTTP dependency, from this class existing.
    @conversion_rate = usd? ? nil : get_rate(@currency)
  end

  def usd?
    currency == Currency::USD
  end

  def convert(usd_cents)
    return usd_cents if usd?

    usd_cents_to_currency(currency, usd_cents, conversion_rate)
  end
end
