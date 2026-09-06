# frozen_string_literal: true

class ProfileLinkClicksController < ApplicationController
  def create
    section = SellerProfileSection.find_by_external_id(params[:id])
    return e404_json unless section.is_a?(SellerProfileLinksSection)

    ProfileLinkClick.record!(section:, link_id: params[:link_id]) unless skip_recording?(section)

    render json: { success: true }
  end

  private
    def skip_recording?(section)
      is_bot? || impersonating_user.present? || logged_in_user&.id == section.seller_id
    end
end
