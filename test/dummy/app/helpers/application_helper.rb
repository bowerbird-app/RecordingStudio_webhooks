module ApplicationHelper
  def dummy_page_nav(title:, subtitle: nil, back_url: nil, back_label: "Home")
    content_for(:title, title) if title.present?
    content_for(:subtitle, subtitle) if subtitle.present?
    flat_pack_page_nav(
      round: true,
      style: :default,
      back_href: back_url,
      back_tooltip: back_label
    )

    recording_studio_page_nav_right do
      concat recording_studio_root_switch_dropdown(style: :ghost, size: :md)
      concat render(
        FlatPack::Button::Component.new(
          text: "Sign out",
          style: :ghost,
          size: :md,
          href: main_app.destroy_user_session_path,
          data: { turbo_method: :delete }
        )
      )
    end
  end

  # Admin 4.2 views still call the removed helper and draw their own title.
  def recording_studio_page_nav(**options)
    flat_pack_page_nav(
      round: true,
      style: :default,
      back_href: options[:page_nav_back_url],
      back_tooltip: options[:page_nav_back_label],
      anchor_href: options[:page_nav_anchor_url],
      anchor_tooltip: options[:page_nav_anchor_label]
    )
    nil
  end

  def recording_studio_page_nav_right(&block)
    content_for(:page_nav_right, &block) if block
    nil
  end
end
