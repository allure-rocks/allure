# frozen_string_literal: true

class FederationDomainBlock < ApplicationRecord
  include FederationDomainFormat

  belongs_to :created_by, class_name: "User", optional: true

  validates :domain, uniqueness: true
end
