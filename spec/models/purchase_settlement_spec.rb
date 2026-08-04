# frozen_string_literal: true

require "spec_helper"

describe PurchaseSettlement do
  describe "validations" do
    it "is valid with the factory defaults" do
      expect(build(:purchase_settlement)).to be_valid
    end

    it "requires a currency" do
      settlement = build(:purchase_settlement, currency: nil)
      expect(settlement).not_to be_valid
      expect(settlement.errors).to include(:currency)
    end

    it "requires an integer amount" do
      settlement = build(:purchase_settlement, amount_cents: nil)
      expect(settlement).not_to be_valid
      expect(settlement.errors).to include(:amount_cents)
    end

    it "rejects a non-positive conversion rate" do
      settlement = build(:purchase_settlement, conversion_rate: 0)
      expect(settlement).not_to be_valid
      expect(settlement.errors).to include(:conversion_rate)
    end

    it "allows a missing conversion rate" do
      expect(build(:purchase_settlement, conversion_rate: nil)).to be_valid
    end

    it "permits only one settlement per purchase" do
      purchase = create(:purchase)
      create(:purchase_settlement, purchase:)
      duplicate = build(:purchase_settlement, purchase:)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors).to include(:purchase_id)
    end
  end

  describe "#purchase" do
    it "belongs to the settled purchase" do
      purchase = create(:purchase)
      expect(create(:purchase_settlement, purchase:).purchase).to eq(purchase)
    end
  end

  describe ".record_for" do
    let(:purchase) { create(:purchase, price_cents: 1_000) }

    before do
      $currency_namespace = Redis::Namespace.new(:currencies, redis: $redis)
      $currency_namespace.set("BRL", 5.5)
    end

    it "records nothing when the charge settled in USD" do
      described_class.record_for(purchase, SettlementConversion.new(currency: Currency::USD))

      expect(described_class.count).to eq(0)
    end

    it "records nothing when there is no settlement" do
      described_class.record_for(purchase, nil)

      expect(described_class.count).to eq(0)
    end

    it "records the converted amount, fee, and rate for a non-USD charge" do
      described_class.record_for(purchase, SettlementConversion.new(currency: Currency::BRL))

      settlement = described_class.sole
      expect(settlement.purchase_id).to eq(purchase.id)
      expect(settlement.currency).to eq(Currency::BRL)
      expect(settlement.conversion_rate).to eq(BigDecimal("5.5"))
      expect(settlement.amount_cents)
        .to eq((purchase.total_transaction_cents * BigDecimal("5.5")).round)
      expect(settlement.fee_cents)
        .to eq((purchase.total_transaction_amount_for_gumroad_cents * BigDecimal("5.5")).round)
    end

    it "overwrites an earlier record so the row describes the live charge intent" do
      described_class.record_for(purchase, SettlementConversion.new(currency: Currency::BRL))
      $currency_namespace.set("BRL", 6.0)
      described_class.record_for(purchase, SettlementConversion.new(currency: Currency::BRL))

      settlement = described_class.sole
      expect(settlement.conversion_rate).to eq(BigDecimal("6.0"))
      expect(settlement.amount_cents)
        .to eq((purchase.total_transaction_cents * BigDecimal("6.0")).round)
    end

    it "records each purchase's own share of a combined charge rather than the charge total" do
      other_purchase = create(:purchase, price_cents: 2_500)
      settlement = SettlementConversion.new(currency: Currency::BRL)

      described_class.record_for(purchase, settlement)
      described_class.record_for(other_purchase, settlement)

      expect(described_class.find_by(purchase_id: purchase.id).amount_cents)
        .to eq((purchase.total_transaction_cents * BigDecimal("5.5")).round)
      expect(described_class.find_by(purchase_id: other_purchase.id).amount_cents)
        .to eq((other_purchase.total_transaction_cents * BigDecimal("5.5")).round)
    end
  end
end
