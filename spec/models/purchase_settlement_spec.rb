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
end
