# frozen_string_literal: true

require "test_helper"

class FlatPackCardKeywordsTest < ActiveSupport::TestCase
  test "dummy does not map Card style and Card rejects that keyword" do
    initializer = Rails.root.join("config/initializers/flat_pack_card_style.rb")
    refute File.exist?(initializer), "dummy Card style: compat must stay deleted"
    refute defined?(FlatPackCardStyleCompat)

    ancestors = FlatPack::Card::Component.ancestors.map(&:name)
    refute_includes ancestors, "FlatPackCardStyleCompat"

    error = assert_raises(ArgumentError) do
      FlatPack::Card::Component.new(style: :outlined)
    end
    assert_match(/unknown keyword: :style/, error.message)

    card = FlatPack::Card::Component.new(
      background: :none,
      shadow: :none,
      border: :strong,
      hover: :none
    )
    assert_kind_of FlatPack::Card::Component, card
  end
end
