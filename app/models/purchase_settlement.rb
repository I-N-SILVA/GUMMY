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

  # Records what a purchase settled for, given the SettlementConversion its charge was created with.
  #
  # A no-op for USD settlement — absence of a row already means "settled in USD", so writing one
  # would only add rows for every sale on the platform.
  #
  # Amounts come from the purchase's own USD totals converted at the charge's rate, not from the
  # charge total, so a purchase that was one of several on a combined charge records its own share.
  #
  # An existing row is overwritten rather than kept: when a charge intent is re-created (an SCA
  # retry, say) the earlier intent is abandoned, and the row should describe the intent that is
  # actually live.
  def self.record_for(purchase, settlement)
    return if settlement.nil? || settlement.usd?

    find_or_initialize_by(purchase_id: purchase.id).tap do |record|
      record.update!(
        currency: settlement.currency,
        amount_cents: settlement.convert(purchase.total_transaction_cents),
        fee_cents: settlement.convert(purchase.total_transaction_amount_for_gumroad_cents),
        conversion_rate: settlement.conversion_rate
      )
    end
  end
end
