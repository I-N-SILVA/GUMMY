# frozen_string_literal: true

require "spec_helper"

describe SellerProfileLinksSection do
  let(:seller) { build(:user) }

  def build_section(links)
    described_class.new(seller:, json_data: { "links" => links })
  end

  def link(url:, title: "My newsletter", subtitle: nil)
    { "id" => SecureRandom.uuid, "title" => title, "url" => url }.tap do |attributes|
      attributes["subtitle"] = subtitle if subtitle
    end
  end

  it "defaults to no links" do
    expect(described_class.new(seller:).links).to eq([])
  end

  it "accepts http and https links" do
    section = build_section([link(url: "http://example.com"), link(url: "https://example.com/posts?a=1")])

    expect(section).to be_valid
  end

  it "keeps the optional description" do
    section = build_section([link(url: "https://example.com", subtitle: "Weekly, on Fridays")])

    expect(section).to be_valid
    expect(section.links.first["subtitle"]).to eq("Weekly, on Fridays")
  end

  describe "urls" do
    it "rejects a javascript url" do
      section = build_section([link(url: "javascript:alert(1)")])

      expect(section).not_to be_valid
      expect(section.errors.full_messages).to include(/valid URL/)
    end

    it "rejects a data url" do
      expect(build_section([link(url: "data:text/html;base64,PHNjcmlwdD4=")])).not_to be_valid
    end

    it "rejects a url with no host" do
      expect(build_section([link(url: "https://")])).not_to be_valid
    end

    it "rejects text that is not a url" do
      expect(build_section([link(url: "not a url")])).not_to be_valid
    end

    it "rejects a blank url" do
      expect(build_section([link(url: "")])).not_to be_valid
    end
  end

  describe "titles" do
    it "requires a title" do
      section = build_section([link(url: "https://example.com", title: "  ")])

      expect(section).not_to be_valid
      expect(section.errors.full_messages).to include(/needs a title/)
    end

    it "rejects a title longer than the limit" do
      section = build_section([link(url: "https://example.com", title: "a" * (described_class::MAX_TITLE_LENGTH + 1))])

      expect(section).not_to be_valid
    end

    it "rejects a description longer than the limit" do
      section = build_section([
                                link(url: "https://example.com", subtitle: "a" * (described_class::MAX_SUBTITLE_LENGTH + 1))
                              ])

      expect(section).not_to be_valid
    end
  end

  describe "count" do
    it "accepts the maximum number of links" do
      section = build_section(Array.new(described_class::MAX_LINKS) { link(url: "https://example.com") })

      expect(section).to be_valid
    end

    it "rejects more than the maximum" do
      section = build_section(Array.new(described_class::MAX_LINKS + 1) { link(url: "https://example.com") })

      expect(section).not_to be_valid
      expect(section.errors.full_messages).to include("You can add up to #{described_class::MAX_LINKS} links")
    end
  end

  it "rejects properties that are not in the schema" do
    section = described_class.new(seller:, json_data: { "links" => [], "onclick" => "alert(1)" })

    expect(section).not_to be_valid
  end
end
