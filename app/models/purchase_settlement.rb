# frozen_string_literal: true

# Records the amount a purchase actually settled for when its settlement currency is not USD
# (e.g. a Brazilian Stripe Connect account settling in BRL). Gumroad records purchases in USD
# (Purchase#price_cents, #rate_converted_to_usd); this side table holds the non-USD settled
# amount without altering the purchases table, which cannot take new columns.
#
# Absence of a row means the purchase settled in USD (the legacy default), so no backfill is
# needed. Values are copied at settlement time so the record stays accurate if rates later move.
class PurchaseSettlement < ApplicationRecord
  belongs_to :purchase

  validates :purchase_id, uniqueness: true
  validates :currency, presence: true
  validates :amount_cents, presence: true, numericality: { only_integer: true }
  validates :fee_cents, numericality: { only_integer: true }

  # Settlement-currency units per 1 USD, applied to convert the USD-based purchase amount into
  # the settlement currency. Stored so the settled amount is reproducible from the original sale.
  validates :conversion_rate, numericality: { greater_than: 0 }, allow_nil: true
end
