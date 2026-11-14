# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Authentication
  include DemoAccounts

  allow_browser versions: :modern

  # Pagy turns `page` into a SQL offset. A value past PostgreSQL's bigint range
  # raises before any page renders, so client input is clamped to a bound no
  # legitimate page reaches; a malformed link answers a normal empty page.
  MAX_PAGE = 1_000_000

  # The switcher's choice for a signed-out visitor, and the language served
  # when neither it nor the browser names an offered one.
  VISITOR_LOCALE_COOKIE = :allure_locale
  VISITOR_FALLBACK_LOCALE = "en"

  before_action :clamp_page_parameter
  before_action :set_locale
  after_action :vary_signed_out_pages_by_language

  helper_method :current_user, :signed_in?, :instance_operator?

  private

  def current_user = Current.session&.user

  def signed_in? = current_user.present?

  # The viewer's calendar: period windows and analytics anchor on the
  # account's own day, never the application default zone.
  def viewer_time_zone = Time.find_zone(current_user&.time_zone) || Time.zone

  def viewer_today = viewer_time_zone.today

  def instance_operator? = current_user&.instance_operator? || false

  # Locale resolution, most specific first. `?locale=` is honoured so that a
  # federated profile link can be shared in a given language without the
  # recipient needing an account. A signed-out visitor is then served the
  # language they chose with the switcher (the `?locale=` of their last
  # signed-out page, kept in a cookie), else the best match of their browser's
  # Accept-Language, else English — a visitor whose language is not offered
  # more likely reads it than French.
  #
  # The session is resumed here rather than relying on a controller's
  # `before_action :resume_session`: public controllers that opt out of
  # authentication append their callback after this one, which used to resolve
  # the default locale for signed-in visitors.
  def set_locale
    resume_session
    requested = locale_from_params
    remember_visitor_locale(requested) if requested && !signed_in?
    I18n.locale = requested || current_user&.locale || visitor_locale
  end

  def locale_from_params = supported_locale(params[:locale])

  def visitor_locale
    supported_locale(cookies[VISITOR_LOCALE_COOKIE]) ||
      Allure::AcceptLanguage.best_match(request.headers["Accept-Language"], available: I18n.available_locales) ||
      VISITOR_FALLBACK_LOCALE
  end

  def supported_locale(value)
    value = value.to_s
    value if I18n.available_locales.map(&:to_s).include?(value)
  end

  def remember_visitor_locale(locale)
    cookies[VISITOR_LOCALE_COOKIE] = { value: locale, expires: 1.year, same_site: :lax, httponly: true, secure: request.ssl? }
  end

  # A signed-out page's language depends on the request's Accept-Language and
  # cookie; a shared cache must not hand one visitor another's language.
  def vary_signed_out_pages_by_language
    return if signed_in? || response.media_type != "text/html"

    response.headers["Vary"] = [ response.headers["Vary"].presence, "Accept-Language", "Cookie" ].compact.join(", ")
  end

  # Pagy resolves `page` from `request.GET`, so the clamp rewrites that source
  # before any paginator reads it. Clamping runs before `set_locale` so the
  # controller `params` copy carries the same bounded value; the federation
  # collection serializer clamps its own argument as well.
  def clamp_page_parameter
    query = request.GET
    return unless query.key?("page")

    value = query["page"].to_s
    query["page"] = value.match?(/\A\d+\z/) ? value.to_i.clamp(1, MAX_PAGE) : 1
  end
end
