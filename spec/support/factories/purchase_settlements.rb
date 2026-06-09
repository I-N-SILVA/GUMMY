# frozen_string_literal: true

FactoryBot.define do
  factory :purchase_settlement do
    purchase
    currency { Currency::BRL }
    amount_cents { 5_000 }
    fee_cents { 250 }
    conversion_rate { "5.43" }
  end
end
