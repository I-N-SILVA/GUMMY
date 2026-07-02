# frozen_string_literal: true

require "spec_helper"

RSpec.describe Kami do
  around do |example|
    described_class.reload!
    example.run
  ensure
    described_class.reload!
  end

  describe ".brand_name" do
    it "returns the brand name from the manifest" do
      expect(described_class.brand_name).to eq("Kami")
    end
  end

  describe ".default_locale" do
    it "returns the manifest default when DEFAULT_LOCALE is not set" do
      allow(ENV).to receive(:fetch).with("DEFAULT_LOCALE", anything) { |_, default| default }
      expect(described_class.default_locale).to eq(:en)
    end

    it "prefers the DEFAULT_LOCALE environment variable" do
      allow(ENV).to receive(:fetch).with("DEFAULT_LOCALE", anything).and_return("pt-BR")
      expect(described_class.default_locale).to eq(:"pt-BR")
    end
  end

  describe ".available_locales" do
    it "returns the manifest locales as symbols" do
      expect(described_class.available_locales).to eq([:en, :"pt-BR"])
    end
  end

  describe ".normalize_locale" do
    it "maps aliased language tags to their supported locale" do
      expect(described_class.normalize_locale("pt")).to eq(:"pt-BR")
      expect(described_class.normalize_locale("pt-PT")).to eq(:"pt-BR")
      expect(described_class.normalize_locale("PT-BR")).to eq(:"pt-BR")
    end

    it "reduces regional tags to their supported base language" do
      expect(described_class.normalize_locale("en-US")).to eq(:en)
    end

    it "returns nil for unsupported languages" do
      expect(described_class.normalize_locale("fr")).to be_nil
    end

    it "returns nil for blank tags" do
      expect(described_class.normalize_locale(nil)).to be_nil
      expect(described_class.normalize_locale("  ")).to be_nil
    end
  end

  describe ".default_currency" do
    it "returns the manifest default when DEFAULT_CURRENCY is not set" do
      allow(ENV).to receive(:fetch).with("DEFAULT_CURRENCY", anything) { |_, default| default }
      expect(described_class.default_currency).to eq("USD")
    end

    it "prefers the DEFAULT_CURRENCY environment variable, upcased" do
      allow(ENV).to receive(:fetch).with("DEFAULT_CURRENCY", anything).and_return("brl")
      expect(described_class.default_currency).to eq("BRL")
    end
  end

  describe ".module_enabled?" do
    it "returns true for modules the manifest ships" do
      expect(described_class.module_enabled?(:pix)).to be(true)
      expect(described_class.module_enabled?(:brl_settlement)).to be(true)
    end

    it "returns false for unknown modules" do
      expect(described_class.module_enabled?(:boleto)).to be(false)
    end

    it "lets KAMI_MODULE_* environment variables override the manifest" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("KAMI_MODULE_PIX").and_return("false")
      expect(described_class.module_enabled?(:pix)).to be(false)

      allow(ENV).to receive(:[]).with("KAMI_MODULE_BOLETO").and_return("TRUE")
      expect(described_class.module_enabled?(:boleto)).to be(true)
    end
  end
end
