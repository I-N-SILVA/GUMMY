# frozen_string_literal: true

class ProfileLinkClick < ApplicationRecord
  belongs_to :seller_profile_section

  validates :link_id, presence: true
  validates :clicked_on, presence: true
  validates :clicks_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def self.record!(section:, link_id:, on: Date.current)
    return false unless section.is_a?(SellerProfileLinksSection)
    return false unless section.links.any? { _1["id"] == link_id }

    now = Time.current
    upsert_all(
      [{ seller_profile_section_id: section.id, link_id:, clicked_on: on, clicks_count: 1, created_at: now, updated_at: now }],
      on_duplicate: Arel.sql("clicks_count = clicks_count + 1, updated_at = VALUES(updated_at)")
    )
    true
  end

  def self.totals_by_link_id(section)
    where(seller_profile_section_id: section.id).group(:link_id).sum(:clicks_count)
  end
end
