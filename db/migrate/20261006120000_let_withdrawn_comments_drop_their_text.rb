# frozen_string_literal: true

# PLAN_COMMENTS.md §3.3: deleting a comment takes its words with it. The row
# keeps its identity so a late Create stays refused, but a comment its author
# deleted, or whose author's account was deleted, keeps no text: only an
# active comment needs a non-empty body.
class LetWithdrawnCommentsDropTheirText < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :comments, name: "comments_body_length"
    add_check_constraint :comments,
                         "char_length(body) <= 2000 AND (status <> 'active' OR char_length(body) >= 1)",
                         name: "comments_body_length"
  end

  def down
    remove_check_constraint :comments, name: "comments_body_length"
    add_check_constraint :comments, "char_length(body) BETWEEN 1 AND 2000", name: "comments_body_length"
  end
end
