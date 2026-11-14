# frozen_string_literal: true

module DevTools
  # The development-only engine. It is not isolated: its routes are drawn into
  # the application's own route set and its controllers inherit from
  # ApplicationController.
  class Engine < ::Rails::Engine
    config.to_prepare do
      # The impersonation state rides on every controller: the bar above the
      # topbar, the stop action and the sign-out path all read it. Re-included
      # on each prepare so the module stays current after a reload.
      ApplicationController.include DevTools::Impersonation
    end
  end
end
