# frozen_string_literal: true

# The root path is a dispatcher, not a destination: it lands members on their
# personal hub. A visitor is sent through the sign-in gate by
# `require_authentication` ("public means registered"), then returns here and
# is forwarded to the hub. `/feed` stays the canonical feed address.
class HomeController < ApplicationController
  def show
    redirect_to me_path
  end
end
