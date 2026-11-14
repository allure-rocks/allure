class SignSegmentAverageGrades < ActiveRecord::Migration[8.1]
  class Segment < ActiveRecord::Base
    self.table_name = "segments"
  end

  # A course's average grade was its ascent over its distance, so a descent
  # read 0 %. It is now the signed net change of its stored profile.
  def up
    Segment.reset_column_information
    Segment.find_each do |segment|
      grade = Allure::Segments::Grade.from_profile(
        segment.elevation_profile, distance: segment.distance,
                                   ascent: segment.ascent, descent: segment.descent
      )
      segment.update_columns(average_grade: grade&.round(2))
    end
  end

  def down; end
end
