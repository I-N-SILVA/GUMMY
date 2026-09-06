import { request } from "$app/utils/request";

export const recordProfileLinkClick = ({ sectionId, linkId }: { sectionId: string; linkId: string }) =>
  request({
    method: "POST",
    url: Routes.profile_section_link_clicks_path(sectionId),
    accept: "json",
    data: { link_id: linkId },
  });
