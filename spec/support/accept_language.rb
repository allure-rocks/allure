# frozen_string_literal: true

# A signed-out page follows the browser's Accept-Language, and Rack::Test
# sends none, which would serve English. Request specs browse as a French
# browser — the application's default locale — unless an example sends its
# own header (an empty one stands for a browser that names no language).
module DefaultAcceptLanguage
  def process(method, path, params: nil, headers: nil, **options)
    headers = { "Accept-Language" => "fr" }.merge(headers.to_h) unless headers.to_h.key?("Accept-Language") || headers.to_h.key?("HTTP_ACCEPT_LANGUAGE")
    super
  end
end

ActionDispatch::Integration::Session.prepend(DefaultAcceptLanguage)
