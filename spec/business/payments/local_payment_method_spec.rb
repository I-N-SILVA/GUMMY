# frozen_string_literal: true

require "spec_helper"

describe LocalPaymentMethod do
  let(:pix) { described_class[:pix] }

  describe ".[]" do
    it "looks a method up by id" do
      expect(pix.id).to eq(:pix)
    end

    it "accepts a string id" do
      expect(described_class["pix"]).to eq(pix)
    end

    it "returns nil for an unregistered method" do
      expect(described_class[:not_a_method]).to be_nil
    end
  end

  describe ".from_params" do
    it "finds the method named by a truthy checkout param" do
      expect(described_class.from_params({ pix: true })).to eq(pix)
    end

    it "returns nil when no method param is present" do
      expect(described_class.from_params({ stripe_token: "tok_123" })).to be_nil
    end

    it "ignores a method param that is blank" do
      expect(described_class.from_params({ pix: "" })).to be_nil
    end
  end

  describe "#build_chargeable" do
    it "builds the chargeable the method declares" do
      expect(pix.build_chargeable(zip_code: "01310-100")).to be_a(StripeChargeablePix)
    end

    it "passes arguments through to the chargeable" do
      expect(pix.build_chargeable(zip_code: "01310-100").zip_code).to eq("01310-100")
    end
  end

  describe "#available_for?" do
    let(:user) { create(:user) }

    it "is unavailable on an account outside the method's countries" do
      merchant_account = create(:merchant_account_stripe_connect, user:, country: "US")
      Feature.activate_user(:brl_settlement, user)

      expect(pix.available_for?(merchant_account)).to eq(false)
    end

    it "is unavailable while the account still settles in usd" do
      merchant_account = create(:merchant_account_stripe_connect, user:, country: "BR")

      expect(merchant_account.settlement_currency).to eq(Currency::USD)
      expect(pix.available_for?(merchant_account)).to eq(false)
    end

    it "becomes available once the account settles in the currency the method requires" do
      merchant_account = create(:merchant_account_stripe_connect, user:, country: "BR")
      Feature.activate_user(:brl_settlement, user)

      expect(pix.available_for?(merchant_account)).to eq(true)
    end
  end

  describe ".available_for" do
    let(:user) { create(:user) }

    it "lists pix for a brl-settling brazilian account" do
      merchant_account = create(:merchant_account_stripe_connect, user:, country: "BR")
      Feature.activate_user(:brl_settlement, user)

      expect(described_class.available_for(merchant_account)).to include(pix)
    end

    it "lists nothing for a us account" do
      merchant_account = create(:merchant_account_stripe_connect, user:, country: "US")

      expect(described_class.available_for(merchant_account)).to be_empty
    end
  end

  describe ".ids_available_to_seller" do
    it "returns nothing for a seller with no stripe merchant account" do
      expect(described_class.ids_available_to_seller(nil)).to eq([])
    end

    it "lists the method ids as strings for a brl-settling seller" do
      user = create(:user)
      create(:merchant_account_stripe_connect, user:, country: "BR")
      Feature.activate_user(:brl_settlement, user)

      expect(described_class.ids_available_to_seller(user)).to eq(["pix"])
    end

    it "lists nothing for a seller whose account still settles in usd" do
      user = create(:user)
      create(:merchant_account_stripe_connect, user:, country: "BR")

      expect(described_class.ids_available_to_seller(user)).to eq([])
    end
  end

  describe "the registered catalog" do
    it "registers pix as an asynchronous brl method for brazil" do
      expect(pix.settlement_currency).to eq(Currency::BRL)
      expect(pix.countries).to eq(["BR"])
      expect(pix.asynchronous?).to eq(true)
    end

    it "gives every method a settlement currency and at least one country" do
      described_class.all.each do |method|
        expect(method.settlement_currency).to be_present
        expect(method.countries).to be_present
      end
    end

    # A method whose currency no market ever settles in could never be offered, since
    # #available_for? requires the account to already settle in that currency.
    it "only registers methods whose currency some market actually settles in" do
      settled_currencies = SettlementCurrencyPolicy::MARKETS.values.map(&:currency)

      described_class.all.each do |method|
        expect(settled_currencies).to include(method.settlement_currency)
      end
    end
  end
end
