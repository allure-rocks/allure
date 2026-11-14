# frozen_string_literal: true

class AddRepresentationToWorkoutPublications < ActiveRecord::Migration[8.1]
  def change
    add_column :workout_publications, :representation, :jsonb, null: false, default: {}
    add_check_constraint :workout_publications,
                         "jsonb_typeof(representation) = 'object'",
                         name: "workout_publications_representation_object"
  end
end
