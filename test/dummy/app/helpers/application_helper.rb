module ApplicationHelper
	def recording_studio_page_nav(title:, page_nav_anchor_url: nil)
		content_for(:title, title)
		content_for(:page_nav_anchor_url, page_nav_anchor_url) if page_nav_anchor_url.present?
	end

	def recording_studio_page_nav_right(&)
		content_for(:page_nav_right, &)
	end

	def recording_studio_accessible_avatars(*)
		nil
	end
end
