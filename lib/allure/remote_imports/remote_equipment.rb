# frozen_string_literal: true

module Allure
  module RemoteImports
    # One piece of gear on the provider's side (docs/dev/REMOTE-IMPORTS.md).
    # `kind` is `bike` or `shoes`.
    RemoteEquipment = Data.define(:external_id, :name, :kind, :brand, :model, :active)
  end
end
