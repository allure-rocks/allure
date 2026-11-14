# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Remote profiles" do
  before { sign_in_as(create(:user)) }

  let(:actor) do
    create(
      :actor,
      uri: "https://remote.example/users/demo",
      handle: "demo@remote.example",
      acct: "demo@remote.example",
      display_name: "Demo Remote",
      summary: "Hiker <script>alert('x')</script>"
    )
  end

  it "renders a cached profile and strips remote scripts" do
    get remote_profile_path(actor.acct)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Demo Remote", "demo@remote.example")
    expect(response.body).not_to include("<script>")
  end

  it "404s an unknown handle without resolving it" do
    expect(Federation::ActorResolver).not_to receive(:new)

    get remote_profile_path("nobody@remote.example")

    expect(response).to have_http_status(:not_found)
  end

  it "404s a tombstoned actor" do
    actor.tombstone!

    get remote_profile_path(actor.acct)

    expect(response).to have_http_status(:not_found)
  end

  it "404s a blocked actor" do
    create(:federation_actor_block, actor_uri: actor.uri)

    get remote_profile_path(actor.acct)

    expect(response).to have_http_status(:not_found)
  end

  it "404s an actor on a blocked authority" do
    create(:federation_domain_block, domain: "remote.example")

    get remote_profile_path(actor.acct)

    expect(response).to have_http_status(:not_found)
  end

  it "offers the follow action to a signed-in member" do
    sign_in_as(create(:user))

    get remote_profile_path(actor.acct)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("follows.actions.follow"))
  end

  it "follows the actor with the target the profile button renders" do
    member = create(:user)
    sign_in_as(member)
    webfinger_resolver = instance_double(Federation::WebFingerResolver)
    allow(Federation::WebFingerResolver).to receive(:new).and_return(webfinger_resolver)
    allow(webfinger_resolver).to receive(:resolve).with(actor.acct).and_return(actor)

    get remote_profile_path(actor.acct)
    target = Nokogiri::HTML(response.body).at_css("input[name='target']")&.[]("value")

    expect(target).to eq(actor.acct)

    post federation_follow_path, params: { target: }

    following = Following.find_by!(follower_actor: member.actor, followed_actor: actor)
    expect(following).to be_pending
  end

  it "unfollows an actor whose instance no longer answers" do
    member = create(:user)
    sign_in_as(member)
    following = create(:following, :accepted, follower_actor: Federation::ActorProvisioner.new(user: member).call!,
                                              followed_actor: actor)
    stub_request(:any, /remote\.example/).to_raise(OpenSSL::SSL::SSLError.new("wrong version number"))

    delete federation_follow_path, params: { target: actor.acct }

    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to eq(I18n.t("federation_follow.destroy.success"))
    expect(following.reload).to be_undone
  end

  it "answers an unreachable instance on follow with an alert, not an error" do
    sign_in_as(create(:user))
    stub_request(:any, /gone\.example/).to_raise(OpenSSL::SSL::SSLError.new("wrong version number"))

    post federation_follow_path, params: { target: "demo@gone.example" }

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq(I18n.t("federation_follow.errors.invalid_target"))
  end

  it "uses the signed-in account's locale" do
    sign_in_as(create(:user, locale: "en"))

    get remote_profile_path(actor.acct)

    expect(response.body).to include('lang="en"')
  end

  it "lists only the notes admitted for the current account" do
    viewer = create(:user)
    viewer_actor = Federation::ActorProvisioner.new(user: viewer).call!
    admitted = create(:remote_note, actor:, title: "Admitted hike")
    other = create(:remote_note, actor:, title: "Other account hike")
    create(:remote_note_recipient, remote_note: admitted, recipient_actor: viewer_actor)
    sign_in_as(viewer)

    get remote_profile_path(actor.acct)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Admitted hike")
    expect(response.body).not_to include("Other account hike")
    expect(response.parsed_body.css("h2").map(&:text)).to include(I18n.t("profile.journal.title"))
    card = response.parsed_body.at_css("article.feed-item")
    expect(card.at_css(".feed-item__author")).to be_nil
    expect(card.css(".btn")).to be_empty
    expect(card.at_css("h3 a.stretched-link")["href"]).to eq(remote_note_path(admitted))
    expect(card.at_css(".allure-feed-metrics, .allure-record-badge")).to be_nil
  end

  it "uses the same count-only sport mix and filters without counting another account's notes" do
    viewer = create(:user)
    viewer_actor = Federation::ActorProvisioner.new(user: viewer).call!
    hiking = create(:remote_note, actor:, title: "Shared hike", sport_label: "Hiking", started_at: 1.day.ago)
    cycling = create(:remote_note, actor:, title: "Shared ride", sport_label: "Cycling", started_at: 1.day.ago)
    create(:remote_note, actor:, sport_label: "Trail")
    [ hiking, cycling ].each { |note| create(:remote_note_recipient, remote_note: note, recipient_actor: viewer_actor) }
    sign_in_as(viewer)

    get remote_profile_path(actor.acct)

    payload = JSON.parse(response.parsed_body.at_css('[data-hub-pie-payload-value]')["data-hub-pie-payload-value"])
    expect(payload["slices"].sum { |slice| slice["values"]["workouts"] }).to eq(2)
    expect(payload["slices"].size).to eq(2)
    expect(response.body).not_to include("Trail")

    get remote_profile_path(actor.acct), params: { sport: "label:Cycling", period: "days30" }

    expect(response.body).to include("Shared ride")
    expect(response.body).not_to include("Shared hike")
    expect(response.parsed_body.at_css('[data-hub-pie-payload-value]')).to be_nil
    expect(response.parsed_body.at_css('input[name="sport"][value="label:cycling"]')["checked"]).to be_present
  end

  it "keeps unknown remote sports and escapes their filter values" do
    viewer = create(:user)
    viewer_actor = Federation::ActorProvisioner.new(user: viewer).call!
    note = create(:remote_note, actor:, sport_label: 'Unusual "sport" <test>')
    create(:remote_note_recipient, remote_note: note, recipient_actor: viewer_actor)
    sign_in_as(viewer)

    get remote_profile_path(actor.acct), params: { sport: 'label:Unusual "sport" <test>' }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.at_css("article.feed-item")).to be_present
    expect(response.body).not_to include("<test>")
  end

  it "lists only the courses admitted for the current account" do
    viewer = create(:user)
    viewer_actor = Federation::ActorProvisioner.new(user: viewer).call!
    admitted = create(:remote_segment, actor:, name: "Admitted course")
    other = create(:remote_segment, actor:, name: "Other account course")
    create(:remote_segment_recipient, remote_segment: admitted, recipient_actor: viewer_actor)
    sign_in_as(viewer)

    get remote_profile_path(actor.acct)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Admitted course", I18n.t("remote_profiles.segments.title"))
    expect(response.body).not_to include("Other account course")
  end

  it "paginates received courses independently from the publication journal" do
    viewer = create(:user)
    viewer_actor = Federation::ActorProvisioner.new(user: viewer).call!
    13.times do |index|
      course = create(:remote_segment, actor:, name: "Course #{index}")
      create(:remote_segment_recipient, remote_segment: course, recipient_actor: viewer_actor)
    end
    sign_in_as(viewer)

    get remote_profile_path(actor.acct), params: { period: "year" }

    links = response.parsed_body.css(".pagination a.page-link").map { |link| link["href"] }
    next_page = links.find { |url| Rack::Utils.parse_nested_query(URI.parse(url).query)["segments_page"] == "2" }
    expect(next_page).to be_present
    expect(next_page).to include("period=year")

    get next_page

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.at_css("#profile-courses-title").parent.css("article").size).to eq(1)
  end

  it "redirects an anonymous visitor to sign-in" do
    create(:remote_note, actor:, title: "Hidden hike")
    delete session_path

    get remote_profile_path(actor.acct)

    expect(response).to redirect_to(new_session_path)
  end
end
