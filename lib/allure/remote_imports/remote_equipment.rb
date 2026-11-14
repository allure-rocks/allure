# frozen_string_literal: true

module Allure
  module RemoteImports
    # One piece of gear on the provider's side (PLAN_REMOTE_IMPORTS.md §5.1).
    # `kind` is `bike` or `shoes`.
    RemoteEquipment = Data.define(:external_id, :name, :kind, :brand, :model, :active)
  end
end
