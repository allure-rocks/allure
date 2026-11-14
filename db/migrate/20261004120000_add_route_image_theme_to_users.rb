# frozen_string_literal: true

# The account's picture-theme preference: which generated route image variant
# the browser shows. `auto` follows the page theme (`current_theme`), `light`
# and `dark` force the variant regardless of the theme (DESIGN.md §15.4).
class AddRouteImageThemeToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :route_image_theme, :string, default: "auto", null: false
    add_check_constraint :users,
                         "route_image_theme::text = ANY (ARRAY['auto'::character varying::text, 'light'::character varying::text, 'dark'::character varying::text])",
                         name: "users_route_image_theme"
  end
end
