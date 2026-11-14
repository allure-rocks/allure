# frozen_string_literal: true

# Members' help (DESIGN.md §20.20): a few pages on the concepts the screens
# cannot explain in a hint. Each topic's text is one locale-specific partial per
# language, help/topics/_<topic>.<locale>.html.erb; titles and summaries live in
# the locale files under help.topics.<topic>.
class HelpController < ApplicationController
  # URL slug => partial and i18n key, in the order the index lists them.
  TOPICS = {
    "publishing" => "publishing",
    "privacy-zones" => "privacy_zones",
    "sharing-beyond" => "sharing_beyond",
    "segments" => "segments",
    "training-load" => "training_load"
  }.freeze

  def index
    @topics = TOPICS
  end

  def show
    @slug = params[:topic].to_s
    @topic = TOPICS.fetch(@slug) { raise ActiveRecord::RecordNotFound }
  end
end
