# frozen_string_literal: true

require "spec_helper"

describe SettlementConversion do
  before do
    $currency_namespace = Redis::Namespace.new(:currencies, redis: $redis)
    $currency_namespace.set("BRL", 5.5)
  end

  describe "USD settlement" do
    let(:conversion) { described_class.new(currency: Currency::USD) }

    it "returns amounts unchanged" do
      expect(conversion.convert(1_234)).to eq(1_234)
    end

    it "records no conversion rate" do
      expect(conversion.conversion_rate).to be_nil
    end

    it "is reported as USD" do
      expect(conversion).to be_usd
    end
  end

  describe "non-USD settlement" do
    let(:conversion) { described_class.new(currency: Currency::BRL) }

    it "converts USD cents into the settlement currency" do
      expect(conversion.convert(1_000)).to eq(5_500)
    end

    it "exposes the rate used so it can be recorded against the purchase" do
      expect(conversion.conversion_rate).to eq("5.5")
    end

    it "keeps using the rate captured at construction after the stored rate moves" do
      conversion.convert(1_000)
      $currency_namespace.set("BRL", 9.9)

      expect(conversion.convert(1_000)).to eq(5_500)
    end

    it "is not reported as USD" do
      expect(conversion).not_to be_usd
    end
  end

  describe "an explicit conversion rate" do
    it "uses the rate given rather than the stored one" do
      conversion = described_class.new(currency: Currency::BRL, conversion_rate: BigDecimal("4.0"))

      expect(conversion.conversion_rate).to eq(BigDecimal("4.0"))
      expect(conversion.convert(1_000)).to eq(4_000)
    end

    it "is ignored for usd, which never converts" do
      conversion = described_class.new(currency: Currency::USD, conversion_rate: BigDecimal("4.0"))

      expect(conversion.conversion_rate).to be_nil
      expect(conversion.convert(1_000)).to eq(1_000)
    end
  end

  describe ".for" do
    it "settles a US Stripe account in USD" do
      merchant_account = create(:merchant_account_stripe_connect, country: "US")
      expect(described_class.for(merchant_account)).to be_usd
    end

    it "settles a Brazilian Stripe account in BRL once brl_settlement is enabled" do
      merchant_account = create(:merchant_account_stripe_connect, country: "BR")
      Feature.activate_user(:brl_settlement, merchant_account.user)

      conversion = described_class.for(merchant_account)

      expect(conversion.currency).to eq(Currency::BRL)
      expect(conversion.convert(1_000)).to eq(5_500)
    end

    it "settles a Brazilian Stripe account in USD while brl_settlement is off" do
      merchant_account = create(:merchant_account_stripe_connect, country: "BR")
      expect(described_class.for(merchant_account)).to be_usd
    end
  end
end
