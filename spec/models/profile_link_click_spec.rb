# frozen_string_literal: true

require "spec_helper"

describe ProfileLinkClick do
  let(:seller) { create(:user) }
  let(:link_id) { SecureRandom.uuid }
  let(:other_link_id) { SecureRandom.uuid }
  let(:section) do
    SellerProfileLinksSection.create!(
      seller:,
      json_data: {
        "links" => [
          { "id" => link_id, "title" => "Newsletter", "url" => "https://example.com/news" },
          { "id" => other_link_id, "title" => "Discord", "url" => "https://example.com/discord" }
        ]
      }
    )
  end

  describe ".record!" do
    it "counts a click against the link" do
      expect(described_class.record!(section:, link_id:)).to eq(true)

      expect(described_class.totals_by_link_id(section)).to eq(link_id => 1)
    end

    it "collapses repeated clicks on the same day into one row" do
      3.times { described_class.record!(section:, link_id:) }

      expect(described_class.count).to eq(1)
      expect(described_class.totals_by_link_id(section)).to eq(link_id => 3)
    end

    it "keeps a separate row per day" do
      described_class.record!(section:, link_id:, on: Date.current - 1)
      described_class.record!(section:, link_id:)

      expect(described_class.count).to eq(2)
      expect(described_class.totals_by_link_id(section)).to eq(link_id => 2)
    end

    it "counts each link separately" do
      described_class.record!(section:, link_id:)
      2.times { described_class.record!(section:, link_id: other_link_id) }

      expect(described_class.totals_by_link_id(section)).to eq(link_id => 1, other_link_id => 2)
    end

    # The endpoint is public, so an unknown id would otherwise let anyone grow this table.
    it "ignores a link id the section does not contain" do
      expect(described_class.record!(section:, link_id: SecureRandom.uuid)).to eq(false)

      expect(described_class.count).to eq(0)
    end

    it "ignores a section that does not hold links" do
      other = SellerProfileRichTextSection.create!(seller:, json_data: { "text" => {} })

      expect(described_class.record!(section: other, link_id:)).to eq(false)
      expect(described_class.count).to eq(0)
    end
  end

  describe ".totals_by_link_id" do
    it "is empty for a section with no clicks" do
      expect(described_class.totals_by_link_id(section)).to eq({})
    end

    it "does not count another section's clicks" do
      other_section = SellerProfileLinksSection.create!(
        seller:,
        json_data: { "links" => [{ "id" => link_id, "title" => "Elsewhere", "url" => "https://example.com" }] }
      )
      described_class.record!(section: other_section, link_id:)

      expect(described_class.totals_by_link_id(section)).to eq({})
    end
  end
end
