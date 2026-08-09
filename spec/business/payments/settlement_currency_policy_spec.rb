# frozen_string_literal: true

require "spec_helper"

describe SettlementCurrencyPolicy do
  let(:seller) { create(:user) }

  describe ".currency_for" do
    it "settles an unlisted country in usd" do
      expect(described_class.currency_for("US", seller:)).to eq(Currency::USD)
    end

    it "settles an unlisted country in usd even when a market flag is on for the seller" do
      Feature.activate_user(:brl_settlement, seller)

      expect(described_class.currency_for("US", seller:)).to eq(Currency::USD)
    end

    it "settles a listed market in its own currency once its flag is on for the seller" do
      Feature.activate_user(:brl_settlement, seller)

      expect(described_class.currency_for("BR", seller:)).to eq(Currency::BRL)
    end

    it "settles a listed market in usd while its flag is off" do
      expect(described_class.currency_for("BR", seller:)).to eq(Currency::USD)
    end

    it "gates the market per seller rather than per country" do
      Feature.activate_user(:brl_settlement, create(:user))

      expect(described_class.currency_for("BR", seller:)).to eq(Currency::USD)
    end

    it "opens the market for every seller in it when the flag is enabled globally" do
      Feature.activate(:brl_settlement)

      expect(described_class.currency_for("BR", seller:)).to eq(Currency::BRL)
    end
  end

  describe ".market?" do
    it "recognizes a listed market" do
      expect(described_class.market?("BR")).to eq(true)
    end

    it "does not recognize an unlisted country" do
      expect(described_class.market?("US")).to eq(false)
    end
  end

  describe "MARKETS" do
    it "names a currency and a gating flag for every market" do
      described_class::MARKETS.each_value do |market|
        expect(market.currency).to be_present
        expect(market.feature_flag).to be_present
      end
    end

    it "does not list usd as a market currency, since usd is the unlisted default" do
      expect(described_class::MARKETS.values.map(&:currency)).not_to include(Currency::USD)
    end
  end
end
