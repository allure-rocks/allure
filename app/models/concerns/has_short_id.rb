# frozen_string_literal: true

module HasShortId
  extend ActiveSupport::Concern

  included do
    attr_readonly :uuid
  end

  class_methods do
    def find_by_short_id!(short_id)
      find_by!(uuid: Allure::ShortId.decode(short_id))
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end
  end

  def to_param = Allure::ShortId.encode(uuid)
end
