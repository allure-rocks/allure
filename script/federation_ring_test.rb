# frozen_string_literal: true

require "json"
require "nokogiri"

class FederationRingTest
  class Failure < StandardError; end

  TIMEOUT = Integer(ENV.fetch("FEDERATION_RING_TIMEOUT", 60))
  USERNAME = "marie"
  PEER_DOMAIN = "allure-b.test:3003"
  PAUL_COMMENT = "Je viens aussi, dimanche."
  PHASES = %w[
    provision wait_for_peer follow approve_follow assert_follow_a assert_follow_b publish
    render_route_image assert_create_a assert_create_b assert_media_a assert_isolation_a
    assert_representation_a redeliver_create_b assert_duplicate_a assert_received_page_a
    like_note_a assert_like_delivery_a assert_like_b
    comment_note_a assert_comment_delivery_a assert_comment_b assert_comment_relay_b assert_comment_confirmed_a
    reply_comment_b assert_reply_delivery_b assert_reply_a delete_comment_a assert_comment_deleted_b
    assert_comment_unrelayed_b assert_unrelay_ignored_a close_comments_b comment_closed_note_a
    assert_comment_rejected_b assert_reject_a reopen_comments_b
    comment_as_paul_b assert_paul_relay_b assert_relayed_comment_a remove_paul_comment_b
    assert_paul_unrelayed_b assert_relay_withdrawn_a
    invite_participant_b assert_invite_delivery_b assert_invite_a confirm_invite_a assert_accept_b
    assert_credit_detached_a
    comment_restricted_note_a assert_restricted_comment_b assert_no_relay_b assert_restricted_comment_object_a
    delete_publication assert_delete_a assert_delete_b block_b publish_second
    assert_blocked_delivery_b assert_blocked_a unblock_b refollow_b assert_refollow_a republish_publication
    assert_new_identity_a unfollow_b assert_withdrawal_a delete_actor_b
    assert_actor_delete_delivered_b assert_actor_gone_a retire_actor_key_b
    assert_key_retired_b promote_peer publish_followers
    assert_followers_delivery_b assert_restricted_create_a assert_restricted_media_a
    assert_restricted_page_a assert_signed_object_a assert_restricted_revoked_a
    publish_public_beside_followers assert_public_withheld_b assert_single_note_a
    publish_segment render_segment_route_image assert_segment_create_a assert_segment_media_a
    redeliver_segment_create_b assert_segment_duplicate_a assert_segment_page_a
    copy_segment_a republish_segment assert_segment_identity_a delete_segment
    assert_segment_delete_a publish_blocked_segment assert_blocked_segment_b
    publish_followers_segment assert_restricted_segment_a assert_restricted_segment_page_a
    assert_signed_segment_object_a assert_restricted_segment_revoked_a
    publish_unfederated_followers assert_followers_withheld_b assert_no_followers_note_a
  ].freeze

  def initialize(phase)
    @phase = phase
  end

  def call
    raise Failure, "unknown phase #{@phase.inspect}" unless PHASES.include?(@phase)

    send(@phase)
    puts "[federation-ring] #{@phase}: ok"
  end

  private

  def provision
    Federation::ActorProvisioner.new(user:).call!
  end

  def wait_for_peer
    target = ENV.fetch("FEDERATION_RING_PEER")
    wait_for("peer #{target}") do
      response = client.get(target, headers: { "Accept" => Allure::Federation::MediaTypes::ACTIVITY_PUB })
      response.status == 200
    rescue Federation::Transport::Client::NetworkError
      false
    end
  end

  def follow
    Federation::Follow.new(user:, target: "@marie@allure-b.test:3003").call!
  end

  # Inbound follows are requests (M5 manual approval). B decides before any
  # Accept is emitted.
  def approve_follow
    local_actor = Federation::ActorProvisioner.new(user:).call!
    following = wait_for("pending follow request on B") do
      Following.where(followed_actor: local_actor, status: "pending").order(:id).last
    end

    Federation::FollowDecision.new(following:, decision: "accept").call!
  end

  def assert_follow_a
    wait_for("A accepted Follow and received Accept") do
      following = Following.order(:id).last
      event = event_for("Follow")
      accept = FederationInboxItem.find_by(activity_type: "Accept")
      following&.accepted? && delivered?(event) && accept&.processed?
    end
  end

  def assert_follow_b
    wait_for("B processed Follow and delivered Accept") do
      following = Following.order(:id).last
      follow = FederationInboxItem.find_by(activity_type: "Follow")
      event = event_for("Accept")
      following&.accepted? && follow&.processed? && delivered?(event)
    end
  end

  def publish
    publish_workout(filename: "multi_segment.gpx", title: "Federation ring route")
  end

  # The blocked-peer check needs a second, distinct publication: the first
  # source is a duplicate once imported, so it uses another fixture.
  def publish_second
    publish_workout(filename: "galibier.gpx", title: "Federation ring second route")
  end

  def publish_workout(filename:, title:, profile: nil)
    profile ||= public_profile
    create_privacy_zones
    upload = ActionDispatch::Http::UploadedFile.new(
      tempfile: File.open(Rails.root.join("spec/fixtures/gpx/#{filename}")),
      filename: filename,
      type: "application/gpx+xml"
    )
    workout = Workouts::Importer.new(
      user:, uploaded_file: upload, sport: Sport.find_by!(slug: "cycling"), title:
    ).call!
    ensure_shared_record(workout)
    ensure_weather(workout)
    workout.update!(commute: true)
    Workouts::Publisher.new(user:, workout:, profile:).call!
  ensure
    upload&.tempfile&.close
  end

  # The ring never reaches Open-Meteo: the gate stores a ready weather summary
  # so the shared weather path runs end to end — snapshot, Note tags, strict
  # remote parsing (PLAN_WEATHER.md §6).
  def ensure_weather(workout)
    WorkoutWeather.find_or_initialize_by(workout:).update!(
      status: "ready", fetch_version: Workouts::WeatherEnricher::FETCH_VERSION,
      analysis_version: Workouts::WeatherEnricher::ANALYSIS_VERSION, endpoint: "archive",
      summary: {
        "condition" => "partly_cloudy", "temperature_min" => 11.2, "temperature_max" => 15.8, "temperature_mean" => 13.4,
        "wind_speed" => 4.2, "wind_direction" => 225,
        "wind_exposure" => { "head" => 0.42, "tail" => 0.31, "cross" => 0.27, "headwind" => 0.8 },
        "is_day" => true
      }
    )
    workout.reload
  end

  # The seeded demo rides still beat the short ring fixture on every metric, so
  # the gate fabricates one held best effort to exercise the shared record
  # marker path end to end: candidate payload, Note tags, and remote parsing.
  def ensure_shared_record(workout)
    distance_key = "mi5"
    # Effort records are unique per (user, sport, distance): the first ring
    # publication holds it, and the later ones do not need their own.
    return if EffortRecord.exists?(user:, sport: workout.sport, distance_key:)

    distance_meters = Allure::Gpx::BestEfforts::DISTANCES.fetch(distance_key)
    workout.best_efforts.create!(
      user:, sport: workout.sport, distance_key:, distance_meters:,
      duration_seconds: 1_800, started_at: workout.started_at,
      start_offset_meters: 0.0, end_offset_meters: distance_meters
    )
    EffortRecord.create!(
      user:, sport: workout.sport, workout:, distance_key:, distance_meters:,
      duration_seconds: 1_800, workout_started_at: workout.started_at
    )
  end

  # The ring has no Chromium route-image worker, so B finalizes its publication
  # in-process. The job falls back to the Ruby renderers and releases the
  # preparing Create, exactly as a lost render job would.
  def render_route_image
    publication = WorkoutPublication.active.order(:id).last
    assert(publication.present?, "no active publication to render")
    assert(publication.route_image_pending?, "publication route image is not pending")

    Workouts::RenderPublicationRouteImageJob.perform_now(publication)
  end

  def assert_create_a
    local_actor = Federation::ActorProvisioner.new(user:).call!
    note = wait_for("A persisted the received Create") do
      candidate = FederationInboxItem.where(activity_type: "Create").order(:id).last
      next unless candidate&.processed?

      record = RemoteNote.find_by(object_uri: candidate.raw.dig("object", "id"))
      record if record&.active? && record.entitled_to?(local_actor)
    end

    assert(note.title.present?, "received note has no title")
    assert(note.metrics.present?, "received note has no metrics")
    assert(note.audience == "public", "received note audience is #{note.audience.inspect}")

    response = client.get(note.object_uri, headers: { "Accept" => Allure::Federation::MediaTypes::ACTIVITY_PUB })
    assert(response.status == 200, "publication object returned HTTP #{response.status}")

    document = JSON.parse(response.body)
    gpx_uri = Array(document["attachment"]).find { |entry| entry["mediaType"] == "application/xml+gpx" }&.fetch("url")
    assert(gpx_uri.present?, "publication has no sanitized GPX attachment")
    dark_uri = Array(document["attachment"]).find { |entry| entry["allure:theme"] == "dark" }&.fetch("url")
    assert(dark_uri.present?, "publication has no dark route image attachment")
    assert_sanitized_gpx(gpx_uri)
  end

  def assert_media_a
    note = wait_for("A cached and parsed remote media") do
      record = RemoteNote.order(:id).last
      next unless record&.active?
      next unless record.attachments.cached.count == 3

      record
    end

    assert(note.representation.dig("track", "features").present?, "remote track was not parsed")
    assert(note.representation.fetch("chart").present?, "remote chart was not derived")
    assert(note.route_metadata.fetch("segments_count").to_i.positive?, "remote route metadata is missing")
    assert(note.attachments.cached.where.not(byte_size: nil).count == 3, "cached media has no verified size")

    variants = note.attachments.cached.where(kind: "route_image").pluck(:theme).sort
    assert(variants == %w[dark light], "both route image variants were not cached: #{variants.inspect}")
  end

  # The received copy belongs to the follower; a second local account on the
  # same instance must never see it (docs/dev/FEDERATION.md).
  def assert_isolation_a
    note = RemoteNote.order(:id).last
    other_actor = Federation::ActorProvisioner.new(user: User.find_by!(username: "paul")).call!

    assert(!note.entitled_to?(other_actor), "another local account holds an entitlement")
    assert(
      RemoteNote.entitled_to(other_actor).where(object_uri: note.object_uri).empty?,
      "another account sees the received note"
    )
  end

  # Sanitized representation: title, sport, metrics and a start location that
  # is not one of the masked endpoints (docs/dev/FEDERATION.md).
  def assert_representation_a
    note = RemoteNote.order(:id).last
    assert(note.present?, "no received note")
    assert(note.title.present?, "received note has no title")
    assert(note.sport_label.present?, "received note has no sport label")
    assert(note.metrics.keys.any?, "received note has no metrics")

    # The profile shares records: the held marker travels as a Note tag and
    # must have been parsed into the representation.
    record_distances = Array(note.representation["record_distances"])
    assert(record_distances.include?("mi5"), "received note has no best-effort record marker")

    # The profile shares the recording device: the imported GPX creator travels
    # as a dedicated Note tag and must have been parsed into the representation.
    assert(
      note.representation["device"] == "Allure Test Suite",
      "received note has no recording device"
    )

    # The profile shares the commute flag: the presence tag must have been
    # parsed into the representation.
    assert(
      note.representation["commute"] == true,
      "received note has no commute flag"
    )

    # The profile shares the weather summary: its tags must have been parsed
    # into the representation, and nothing hourly travels.
    weather = note.representation["weather"]
    assert(
      weather.is_a?(Hash) && weather["condition"] == "partly_cloudy" && weather["temperature_max"] == 15.8 &&
        weather["is_day"] == true && weather["temperature_mean"] == 13.4,
      "received note has no weather summary"
    )

    location = note.representation["location"]
    assert(location.present?, "received note has no sanitized location")
    masked = [ [ 6.4, 45.0 ], [ 6.4, 45.005 ] ]
    actual = [ location["longitude"], location["latitude"] ]
    assert(!masked.include?(actual), "received location exposes a masked endpoint")
  end

  # Re-POST the same Create. Admission must recognize the duplicate and persist
  # nothing new (docs/dev/FEDERATION.md item 8).
  def redeliver_create_b
    event = event_for("Create")
    delivery = event&.deliveries&.first
    assert(delivery.present?, "no Create delivery to redeliver")

    delivery.update!(status: "pending", attempts: 0, next_attempt_at: nil, lease_until: nil, last_error: nil)
    Federation::Delivery::Deliver.new(delivery:).call!
  end

  def assert_duplicate_a
    note = RemoteNote.order(:id).last
    assert(note.present?, "no received note")
    assert(RemoteNote.where(object_uri: note.object_uri).count == 1, "duplicate Create created a second note")
    assert(note.recipients.where(status: "active").count == 1, "duplicate Create created a second entitlement")
    assert(FederationInboxItem.where(activity_type: "Create").count == 1, "duplicate Create was admitted twice")
  end

  # A public note renders for any signed-in account, and its media is served
  # through this instance's own endpoints (docs/dev/FEDERATION.md items 7/9). The
  # entitlement-gated HTTP isolation check lives in the restricted scenario.
  def assert_received_page_a
    note = RemoteNote.order(:id).last
    # Loaded before any integration session: the session executor leaves the
    # development query-log context unusable for a top-level query afterwards.
    paul = User.find_by!(username: "paul")
    dark_blob = note.attachments.cached.find_by(kind: "route_image", theme: "dark")&.blob
    assert(dark_blob.present?, "the received note has no cached dark image")

    entitled = integration_session(user)
    entitled_result = note_page_statuses(entitled, note)
    assert(
      entitled_result[:statuses] == [ 200, 200, 200 ],
      "entitled account did not receive the public note"
    )
    assert(entitled_result[:dark_body] == dark_blob.download, "the dark variant was not served")

    stranger = integration_session(paul)
    assert(
      note_page_statuses(stranger, note)[:statuses] == [ 200, 200, 200 ],
      "a public note is not visible to signed-in accounts"
    )
  end

  def note_page_statuses(session, note)
    session.get("/remote_notes/#{note.id}")
    note_status = session.response.status
    session.get("/remote_notes/#{note.id}/media/gpx")
    gpx_status = session.response.status
    session.get("/remote_notes/#{note.id}/media/route-image?theme=dark")
    dark_status = session.response.status
    dark_body = session.response.body
    { statuses: [ note_status, gpx_status, dark_status ], dark_body: }
  end

  # PLAN_REACTIONS.md: the receiving account reacts to the received note. A
  # mints a Like carrying the Allure type, delivers it to the origin, and B
  # stores a local reaction and notifies the workout owner.
  def like_note_a
    note = RemoteNote.active.order(:id).last
    assert(note.present?, "no received note to like")

    Reactions::Toggle.new(user:, target: note, kind: "beer").call!
  end

  def assert_like_delivery_a
    event = event_for("Like")
    assert(event.present?, "A has no Like event")
    assert(event.payload["_allure_reaction"] == "beer", "the Like did not carry the Allure reaction type")
    wait_for("A delivered the Like") { delivered?(event) }
  end

  def assert_like_b
    reaction = wait_for("B stored the inbound reaction") do
      Reaction.active.where(kind: "beer").order(:id).last
    end
    assert(reaction.actor.remote?, "the inbound reaction actor is not remote")
    assert(reaction.workout.present?, "the inbound reaction has no local workout")
    assert(
      FederationInboxItem.where(activity_type: "Like").order(:id).last&.processed?,
      "B did not process the Like activity"
    )
    assert(Notification.where(kind: "reaction").exists?, "B did not notify the workout owner")
  end

  # PLAN_COMMENTS.md Slice 2: A's account comments on the received note, B
  # hosts the thread and its owner replies, A's author deletes the comment,
  # and a thread B closed refuses the next one with a Reject.
  def comment_note_a
    note = RemoteNote.active.order(:id).last
    assert(note.present?, "no received note to comment on")

    Comments::Post.new(user:, target: note, body: "Belle sortie !\nOn y retourne ?").call!
  end

  def assert_comment_delivery_a
    comment = own_comments.roots.order(:id).last
    event = FederationOutboxEvent.find_by(activity_uri: comment&.activity_uri)
    assert(event.present?, "A has no comment Create")
    assert(event.payload.dig("object", "inReplyTo") == comment.remote_note.object_uri, "the comment does not answer the note")
    assert(event.audience["to"] == [ comment.remote_note.actor.uri ], "the comment is not addressed to the thread host")
    wait_for("A delivered the comment") { delivered?(event.reload) }

    response = client.get(comment.uri, headers: { "Accept" => Allure::Federation::MediaTypes::ACTIVITY_PUB })
    assert(response.status == 200, "A's comment object returned HTTP #{response.status}")
  end

  def assert_comment_b
    comment = wait_for("B stored the remote comment") { hosted_remote_comment }
    assert(comment.active?, "the received comment is not active")
    assert(comment.workout.user_id == user.id, "the comment is not on the owner's workout")
    assert(comment.content_html.include?("Belle sortie"), "the comment lost its text")
    assert(FederationInboxItem.find_by(activity_uri: comment.activity_uri)&.processed?, "B did not process the comment")
    assert(Notification.where(user:, kind: "comment", subject: comment).exists?, "B did not notify the workout owner")
  end

  # PLAN_COMMENTS.md Slice 3: the host relays the comment it took to the
  # instances its publication went to, the author's included, which learns
  # the comment was taken.
  def assert_comment_relay_b
    comment = hosted_remote_comment
    announce = wait_for("B relayed the accepted comment") { relay_event_for(comment) }
    assert(announce.payload["object"] == comment.raw, "B did not relay the author's own object")
    wait_for("B delivered the relay") { delivered?(announce.reload) }
  end

  def assert_comment_confirmed_a
    mine = wait_for("the thread host confirmed A's comment") do
      record = own_comments.roots.order(:id).last
      record if record&.confirmed_at.present?
    end
    assert(FederationInboxItem.find_by(activity_uri: mine.relay_activity_uri)&.processed?, "A did not process the relay")
  end

  def reply_comment_b
    comment = hosted_remote_comment
    Comments::Post.new(user:, target: comment.workout, body: "Dimanche prochain.", parent_id: comment.to_param).call!
  end

  def assert_reply_delivery_b
    reply = own_comments.where.not(parent_id: nil).order(:id).last
    event = FederationOutboxEvent.find_by(activity_uri: reply&.activity_uri)
    assert(event.present?, "B has no reply Create")
    assert(event.subject_type == "WorkoutPublication", "the owner's reply does not ride on its publication")
    wait_for("B delivered the reply") { delivered?(event.reload) }
  end

  def assert_reply_a
    mine = own_comments.roots.order(:id).last
    reply = wait_for("A stored the host's reply") { Comment.find_by(parent_id: mine.id) }
    assert(reply.actor.remote?, "the reply author is not remote")
    assert(reply.remote_note_id == mine.remote_note_id, "the reply is not on the received note")
    assert(Notification.where(user:, kind: "comment", subject: reply).exists?, "A did not notify the answered author")
  end

  def delete_comment_a
    Comments::Delete.new(user:, comment: own_comments.roots.order(:id).last).call!
  end

  def assert_comment_deleted_b
    comment = wait_for("B deleted the remote comment") do
      record = hosted_remote_comment
      record if record&.deleted?
    end
    assert(Comment.find_by(parent_id: comment.id)&.active?, "the owner's reply did not survive the deletion")

    response = client.get(comment.uri, headers: { "Accept" => Allure::Federation::MediaTypes::ACTIVITY_PUB })
    assert(response.status == 404, "the deleted comment object returned HTTP #{response.status}")
  end

  # The host stops relaying the deleted comment where its Announce went; on
  # the author's instance, already deleted, that Undo changes nothing.
  def assert_comment_unrelayed_b
    assert_unrelayed(hosted_remote_comment)
  end

  def assert_unrelay_ignored_a
    mine = own_comments.roots.order(:id).last
    wait_for("A processed the host's Undo") { relay_undo_item_for(mine)&.processed? }
    assert(mine.reload.deleted?, "the host's Undo turned A's deleted comment #{mine.status}")
  end

  def close_comments_b
    Comments::Close.new(user:, workout: hosted_remote_comment.workout, closed: true).call!
  end

  def comment_closed_note_a
    Comments::Post.new(user:, target: RemoteNote.active.order(:id).last, body: "Encore une question").call!
  end

  def assert_comment_rejected_b
    reject = wait_for("B refused the comment with a Reject") do
      FederationOutboxEvent.where(activity_type: "Reject").order(:id).detect do |event|
        event.payload["_allure_reason"] == "closed"
      end
    end
    assert(FederationInboxItem.find_by(activity_uri: reject.payload["object"])&.rejected?, "B accepted a closed thread")
    wait_for("B delivered the Reject") { delivered?(reject.reload) }
  end

  def assert_reject_a
    refused = wait_for("A marked the comment refused") do
      record = own_comments.order(:id).last
      record if record&.rejected?
    end
    assert(refused.removal_reason == "closed", "the refusal reason is #{refused.removal_reason.inspect}")
  end

  def reopen_comments_b
    Comments::Close.new(user:, workout: hosted_remote_comment.workout, closed: false).call!
  end

  # A third party's comment — B's second account — reaches A only through the
  # host's relay; A checks it against its author's own copy before storing it,
  # and the owner's removal on B takes it out on A, words included.
  def comment_as_paul_b
    paul = User.find_by!(username: "paul")
    Comments::Post.new(user: paul, target: hosted_remote_comment.workout, body: PAUL_COMMENT).call!
  end

  def assert_paul_relay_b
    comment = paul_comment
    announce = relay_event_for(comment)
    assert(announce.present?, "B has no relay for its member's comment")
    assert(announce.payload.dig("object", "id") == comment.uri, "the relay does not carry the member's comment")
    wait_for("B delivered the member's relay") { delivered?(announce.reload) }
  end

  def assert_relayed_comment_a
    relayed = wait_for("A stored the relayed comment") { Comment.where.not(relayed_by_actor_id: nil).order(:id).last }
    assert(relayed.active?, "the relayed comment is #{relayed.status}")
    assert(relayed.relayed_by_actor_id == relayed.remote_note.actor_id, "the relay does not name the thread host")
    assert(relayed.actor.remote? && relayed.actor.uri.end_with?("/users/paul"), "the relayed author is #{relayed.actor.uri}")
    assert(relayed.body == PAUL_COMMENT, "the relayed comment lost its text")
    note_id = relayed.remote_note_id

    session = integration_session(user)
    session.get("/remote_notes/#{note_id}")
    assert(session.response.status == 200, "the received note page returned HTTP #{session.response.status}")
    assert(session.response.body.include?(PAUL_COMMENT), "the received note page does not show the relayed comment")
  end

  def remove_paul_comment_b
    Comments::Remove.new(user:, comment: paul_comment).call!
  end

  def assert_paul_unrelayed_b
    assert_unrelayed(paul_comment)
  end

  def assert_relay_withdrawn_a
    withdrawn = wait_for("A took the relayed comment out") do
      record = Comment.where.not(relayed_by_actor_id: nil).order(:id).last
      record if record&.removed?
    end
    assert(withdrawn.removal_reason == "unknown", "the withdrawn relay reason is #{withdrawn.removal_reason.inspect}")
    assert(withdrawn.body.empty? && withdrawn.raw.blank?, "A kept the withdrawn relay's words")
    note_id = withdrawn.remote_note_id

    session = integration_session(user)
    session.get("/remote_notes/#{note_id}")
    assert(!session.response.body.include?(PAUL_COMMENT), "the received note page still shows the withdrawn comment")
  end

  # Restricted scenario: the followers comment is hosted by B under the
  # followers audience, and A never serves it as an object.
  def comment_restricted_note_a
    note = RemoteNote.active.where(audience: "followers").order(:id).last
    assert(note.present?, "no received followers note to comment on")

    Comments::Post.new(user:, target: note, body: "Réservé aux abonnés").call!
  end

  def assert_restricted_comment_b
    comment = wait_for("B stored the followers comment") { hosted_remote_comment }
    assert(comment.audience == "followers", "the hosted comment audience is #{comment.audience.inspect}")
  end

  # A followers thread is never relayed (PLAN_COMMENTS.md §6.6).
  def assert_no_relay_b
    assert(FederationOutboxEvent.where(activity_type: "Announce").none?, "B relayed a comment on a followers thread")
  end

  def assert_restricted_comment_object_a
    comment = own_comments.order(:id).last
    wait_for("A delivered the followers comment") do
      delivered?(FederationOutboxEvent.find_by(activity_uri: comment.activity_uri))
    end

    response = client.get(comment.uri, headers: { "Accept" => Allure::Federation::MediaTypes::ACTIVITY_PUB })
    assert(response.status == 404, "a followers comment object returned HTTP #{response.status}")
  end

  def own_comments = Comment.where(actor: Federation::ActorProvisioner.new(user:).call!)

  def hosted_remote_comment
    Comment.joins(:actor).where(actors: { local: false }).where.not(workout_id: nil).order(:id).last
  end

  def paul_comment
    paul_actor = Federation::ActorProvisioner.new(user: User.find_by!(username: "paul")).call!
    Comment.where(actor: paul_actor).where.not(workout_id: nil).order(:id).last
  end

  def relay_event_for(comment)
    FederationOutboxEvent.find_by(
      activity_uri: Federation::Outbox::CommentAnnounce.activity_uri_for(comment, comment.thread_host_actor)
    )
  end

  def relay_undo_item_for(comment)
    FederationInboxItem.where(activity_type: "Undo").order(:id).detect do |item|
      item.raw.dig("object", "type") == "Announce" && item.raw.dig("object", "object") == comment.uri
    end
  end

  # The host's Undo goes where the relay went, and the relay keeps no words.
  def assert_unrelayed(comment)
    announce = relay_event_for(comment)
    undo = wait_for("B undid the relay") do
      FederationOutboxEvent.where(activity_type: "Undo").order(:id).detect do |event|
        event.payload.dig("object", "id") == announce.activity_uri
      end
    end
    wait_for("B delivered the Undo") { delivered?(undo.reload) }
    assert(announce.reload.payload["redacted"] == true, "B kept the withdrawn relay's words")
  end

  # Development forgery protection is on, so the sign-in form's authenticity
  # token is carried into the session POST.
  #
  # Loading the integration session marks execution contexts nestable, as a
  # test case would; a runner never pushed one, so the request's executor
  # would pop the runner's context to nil and break every later query.
  def integration_session(session_user)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    ActiveSupport::ExecutionContext.nestable = false
    session.host! "allure-a.test"
    session.get("/session/new")
    token = session.response.body[/name="authenticity_token" value="([^"]+)"/, 1]
    assert(token.present?, "sign-in form has no authenticity token")
    session.post(
      "/session",
      params: {
        authenticity_token: token,
        email_address: session_user.email_address,
        password: "allure-dev-password"
      }
    )
    assert(session.response.status.in?([ 200, 302, 303 ]), "failed to sign in #{session_user.username}")
    answer_second_factor(session, session_user) if session.response.location.to_s.include?("/session/challenge")
    session
  end

  # The seeded demo accounts carry an authenticator app (docs/dev/AUTH.md).
  def answer_second_factor(session, session_user)
    session.get("/session/challenge/new")
    token = session.response.body[/name="authenticity_token" value="([^"]+)"/, 1]
    session_user.update_column(:otp_last_used_step, nil)
    session.post(
      "/session/challenge",
      params: { authenticity_token: token, code: ROTP::TOTP.new(session_user.reload.otp_secret).now }
    )
    assert(session.response.redirect? && !session.response.location.include?("/session"),
           "failed the second step for #{session_user.username}")
  end

  def assert_create_b
    wait_for("B delivered Create") { delivered?(event_for("Create")) }
  end

  # docs/dev/SHARED-ACTIVITIES.md: B's owner invites A's account, which holds the
  # publication and follows her, to confirm the outing. A stores the
  # invitation, shows its card on the received note, and confirms: an Accept
  # goes back and A's account gets a credit row from the note's figures.
  def invite_participant_b
    workout = user.workouts.recordings.order(:id).last
    Participations::Propose.new(user:, workout:, target: "@marie@allure-a.test:3002").call!
  end

  def assert_invite_delivery_b
    event = event_for("Invite")
    assert(event.present?, "B has no Invite event")
    assert(event.payload["to"] == [ "http://allure-a.test:3002/users/marie" ], "the Invite is not addressed to A alone")
    assert(event.payload.to_json.exclude?("coordinates"), "the Invite carries geometry")
    wait_for("B delivered the Invite") { delivered?(event) }
  end

  def assert_invite_a
    participation = wait_for("A stored the invitation") { RemoteParticipation.pending.order(:id).last }
    assert(participation.recipient_actor.user == user, "the invitation names another account")
    assert(participation.sport_slug == "cycling", "the invitation lost its sport")
    assert(Notification.exists?(user:, kind: "participation_requested", subject: participation),
           "A's account was not told of the invitation")

    session = integration_session(user)
    session.get("/remote_notes/#{participation.remote_note_id}")
    assert(session.response.status == 200, "received note returned HTTP #{session.response.status}")
    assert(session.response.body.include?("/remote_participations/#{participation.to_param}"),
           "the received note has no invitation card")
  end

  def confirm_invite_a
    participation = RemoteParticipation.pending.order(:id).last
    Participations::RemoteAnswer.new(participation:, user:, decision: "confirm").call!
    credit = participation.reload.credit_row
    assert(credit.present? && credit.credit_remote?, "the confirmation built no credit row")
    assert(credit.distance.to_f.positive? && credit.ascent.present?, "the credit row lost the note's figures")
    wait_for("A delivered the Accept") { delivered?(event_for("Accept")) }
  end

  def assert_accept_b
    participation = wait_for("B recorded the confirmation") do
      WorkoutParticipation.where.not(wire_activity_uri: nil).where.not(participant_confirmed_at: nil).order(:id).last
    end
    assert(participation.active?, "the confirmed participation is not active")
    assert(Notification.exists?(user:, kind: "participation_confirmed", subject: participation),
           "B's owner was not told of the confirmation")
  end

  # After B deletes the publication, A's credit stays, detached (§6.5).
  def assert_credit_detached_a
    credit = wait_for("A detached the remote credit") do
      user.workouts.credit_rows_only.where.not(remote_participation_id: nil).where.not(credit_detached_at: nil).last
    end
    assert(credit.title.nil?, "the detached credit kept the owner's title")
  end

  def delete_publication
    workout = user.workouts.order(:id).last
    Workouts::PublicationDeletion.new(user:, workout:).call!
  end

  def assert_delete_a
    note = wait_for("A tombstoned the received Delete") do
      item = FederationInboxItem.where(activity_type: "Delete").order(:id).last
      next unless item&.processed?

      record = RemoteNote.order(:id).last
      record if record&.deleted? && record.recipients.where(status: "active").empty?
    end

    assert(note.location_data_purged?, "deleted note retained location data")
    assert(note.representation["redacted"] == true, "deleted note representation was not redacted")
    assert(note.attachments.purged.count == 3, "deleted note media descriptors are not purged")

    object_response = client.get(note.object_uri, headers: { "Accept" => Allure::Federation::MediaTypes::ACTIVITY_PUB })
    assert(object_response.status == 404, "deleted publication returned HTTP #{object_response.status}")

    create_item = publication_creates.order(:id).last
    assert(create_item.present?, "no admitted Create found")
    gpx_uri = Array(create_item.raw.dig("object", "attachment"))
      .find { |entry| entry["mediaType"] == "application/xml+gpx" }&.fetch("url")
    assert(client.get(gpx_uri).status == 404, "deleted publication GPX is still available")
  end

  def assert_delete_b
    wait_for("B delivered Delete") { delivered?(event_for("Delete")) }
  end

  # A blocks the peer's authority after the first publication cycle. B's new
  # Create must reach A's admission and be answered 403, and A must persist
  # nothing for it.
  def block_b
    Federation::Safety::Blocking.new.block_domain!(domain: PEER_DOMAIN, created_by: user)
  end

  def assert_blocked_delivery_b
    event = event_for("Create")
    assert(event.present?, "B has no Create event")

    wait_for("B's Create delivery to the blocked peer fails with 403") do
      event.deliveries.exists?(status: "failed", last_response_status: 403)
    end
  end

  def assert_blocked_a
    assert(
      publication_creates.count == 1,
      "A admitted an activity from a blocked instance"
    )
    note = RemoteNote.order(:id).last
    assert(note&.deleted?, "A's received note changed after the block")
    assert(Federation::Safety::Blocks.blocked_domain?(PEER_DOMAIN), "A does not consider the peer blocked")

    response = client.get(user.actor.uri, headers: { "Accept" => Allure::Federation::MediaTypes::ACTIVITY_PUB })
    assert(response.status == 200, "A's public actor endpoint returned HTTP #{response.status}")
  end

  def publish_blocked_segment
    workout = user.workouts.find_by!(title: "Federation ring route")
    segment = create_ring_segment(workout, name: "Federation ring blocked course")
    Segments::Publisher.new(user:, segment:).call!
    publication = SegmentPublication.active.order(:id).last
    Segments::RenderPublicationRouteImageJob.perform_now(publication)
  end

  def assert_blocked_segment_b
    event = FederationOutboxEvent.where(subject_type: "SegmentPublication", activity_type: "Create").order(:id).last
    assert(event.present?, "B has no segment Create event")

    wait_for("B's segment Create delivery to the blocked peer fails with 403") do
      event.deliveries.exists?(status: "failed", last_response_status: 403)
    end
  end

  # --- Republish, withdrawal, and actor deletion ------------------------------

  def unblock_b
    Federation::Safety::Blocking.new.unblock_domain!(domain: PEER_DOMAIN)
  end

  # The block ended A's follow of the peer, locally (docs/dev/FEDERATION.md), and
  # unblocking restores nothing: A follows again. B still holds the accepted
  # relationship, so it accepts the renewed Follow at once.
  def refollow_b
    follow
  end

  def assert_refollow_a
    local_actor = Federation::ActorProvisioner.new(user:).call!
    wait_for("A follows the peer again after the unblock") do
      Following.where(follower_actor: local_actor).order(:id).last&.accepted?
    end
  end

  # The first workout's publication was withdrawn in the delete cycle; a fresh
  # publish must produce a new object identity (docs/dev/FEDERATION.md item 10).
  def republish_publication
    workout = user.workouts.find_by!(title: "Federation ring route")
    assert(workout.active_publications.none?, "republish expects the first publication to be withdrawn")
    Workouts::Publisher.new(user:, workout:, profile: public_profile).call!
  end

  def assert_new_identity_a
    local_actor = Federation::ActorProvisioner.new(user:).call!
    previous_object = RemoteNote.deleted.order(:id).last&.object_uri
    note = wait_for("A activated the republished identity") do
      record = RemoteNote.active.order(:id).last
      record if record&.entitled_to?(local_actor)
    end

    assert(previous_object.present?, "no deleted note to compare against")
    assert(note.object_uri != previous_object, "republished note kept the old object identity")

    old_response = client.get(previous_object, headers: { "Accept" => Allure::Federation::MediaTypes::ACTIVITY_PUB })
    assert(old_response.status == 404, "withdrawn object returned HTTP #{old_response.status}")
  end

  # --- Federated courses (PLAN_SEGMENTS_FEDERATION.md §17.2) ------------------

  def publish_segment
    workout = user.workouts.find_by!(title: "Federation ring route")
    segment = create_ring_segment(workout, name: "Federation ring course")
    Segments::Publisher.new(user:, segment:).call!
  end

  # The ring has no Chromium route-image worker, so B finalizes its publication
  # in-process, exactly like the workout flow.
  def render_segment_route_image
    publication = SegmentPublication.active.order(:id).last
    assert(publication.present?, "no active segment publication to render")
    assert(publication.route_image_pending?, "segment publication route image is not pending")

    Segments::RenderPublicationRouteImageJob.perform_now(publication)
  end

  def assert_segment_create_a
    local_actor = Federation::ActorProvisioner.new(user:).call!
    segment = wait_for("A persisted the received course") do
      candidate = FederationInboxItem.where(activity_type: "Create").order(:id).last
      next unless candidate&.processed?

      record = RemoteSegment.find_by(object_uri: candidate.raw.dig("object", "id"))
      record if record&.active? && record.entitled_to?(local_actor)
    end

    assert(segment.audience == "public", "received course audience is #{segment.audience.inspect}")
    assert(segment.representation["kind"] == "segment", "received course kind is #{segment.representation['kind'].inspect}")
    assert(segment.attachments.count == 3, "received course media descriptors are missing")
  end

  def assert_segment_media_a
    segment = wait_for("A cached and parsed the remote course") do
      record = RemoteSegment.order(:id).last
      next unless record&.active?
      next unless record.attachments.cached.count == 3

      record
    end

    features = segment.representation.dig("track", "features")
    assert(Array(features).length == 1, "remote course track is not exactly one LineString")
    assert(segment.representation["chart"].nil?, "remote course carries an elevation chart")
    assert(segment.route_metadata.fetch("segments_count").to_i.positive?, "remote course route metadata is missing")
    assert(segment.attachments.cached.where.not(byte_size: nil).count == 3, "cached course media has no verified size")

    variants = segment.attachments.cached.where(kind: "route_image").pluck(:theme).sort
    assert(variants == %w[dark light], "both course image variants were not cached: #{variants.inspect}")
  end

  def redeliver_segment_create_b
    event = FederationOutboxEvent.where(subject_type: "SegmentPublication", activity_type: "Create").order(:id).last
    delivery = event&.deliveries&.first
    assert(delivery.present?, "no segment Create delivery to redeliver")

    delivery.update!(status: "pending", attempts: 0, next_attempt_at: nil, lease_until: nil, last_error: nil)
    Federation::Delivery::Deliver.new(delivery:).call!
  end

  def assert_segment_duplicate_a
    segment = RemoteSegment.order(:id).last
    assert(segment.present?, "no received course")
    assert(RemoteSegment.where(object_uri: segment.object_uri).count == 1, "duplicate course Create created a second row")
    assert(segment.recipients.where(status: "active").count == 1, "duplicate course Create created a second entitlement")
  end

  # A public course renders for any signed-in account, and its track and media
  # are served through this instance's own endpoints.
  def assert_segment_page_a
    segment = RemoteSegment.active.order(:id).last
    # Loaded before any integration session: the session executor leaves the
    # development query-log context unusable for a top-level query afterwards.
    paul = User.find_by!(username: "paul")
    dark_blob = segment.attachments.cached.find_by(kind: "route_image", theme: "dark")&.blob
    assert(dark_blob.present?, "the received course has no cached dark image")

    entitled = integration_session(user)
    entitled_result = segment_page_statuses(entitled, segment)
    assert(
      entitled_result[:statuses] == [ 200, 200, 200, 200 ],
      "entitled account did not receive the public course"
    )
    assert(entitled_result[:dark_body] == dark_blob.download, "the dark course variant was not served")

    stranger = integration_session(paul)
    assert(
      segment_page_statuses(stranger, segment)[:statuses] == [ 200, 200, 200, 200 ],
      "a public course is not visible to signed-in accounts"
    )
  end

  def segment_page_statuses(session, segment)
    session.get("/remote_segments/#{segment.id}")
    page_status = session.response.status
    session.get("/remote_segments/#{segment.id}/track")
    track_status = session.response.status
    session.get("/remote_segments/#{segment.id}/media/gpx")
    gpx_status = session.response.status
    session.get("/remote_segments/#{segment.id}/media/route-image?theme=dark")
    dark_status = session.response.status
    dark_body = session.response.body
    { statuses: [ page_status, track_status, gpx_status, dark_status ], dark_body: }
  end

  # The copied course is private and owner-only, and the copier's own workout
  # is matched locally against it (PLAN_SEGMENTS_FEDERATION.md §12.4).
  def copy_segment_a
    remote = RemoteSegment.active.order(:id).last
    workout = user.workouts.find_by(title: "Copied course ride") || import_ring_workout
    result = Segments::RemoteImporter.new(user:, remote_segment: remote).call!
    copy = result.segment

    assert(copy.visibility == "private", "local copy visibility is #{copy.visibility.inspect}")
    assert(copy.remote_segment_id == remote.id, "local copy lost its provenance")
    assert(copy.source_workout_id.nil?, "local copy retained a source workout")

    Segments::MatchWorkoutJob.perform_now(workout)
    effort = SegmentEffort.find_by(segment: copy, workout:)
    assert(effort.present?, "copied course did not match the local workout")
  end

  def import_ring_workout
    upload = ActionDispatch::Http::UploadedFile.new(
      tempfile: File.open(Rails.root.join("spec/fixtures/gpx/multi_segment.gpx")),
      filename: "multi_segment.gpx",
      type: "application/xml+gpx"
    )
    Workouts::Importer.new(
      user:,
      uploaded_file: upload,
      sport: Sport.find_by!(slug: "cycling"),
      title: "Copied course ride"
    ).call!
  ensure
    upload&.tempfile&.close
  end

  def republish_segment
    segment = Segment.find_by!(name: "Federation ring course")
    segment.update!(name: "Federation ring course v2")
    Segments::PublicationReplacement.new(user:, segment:).call!
  end

  def assert_segment_identity_a
    local_actor = Federation::ActorProvisioner.new(user:).call!
    previous = nil
    current = wait_for("A activated the republished course identity") do
      records = RemoteSegment.order(:id).to_a
      next unless records.length >= 2

      previous = records[-2]
      records[-1] if records[-1]&.active? && records[-1].entitled_to?(local_actor) && previous.reload.deleted?
    end

    assert(previous.representation["redacted"] == true, "withdrawn course was not redacted")
    assert(previous.attachments.purged.count == 3, "withdrawn course media was not purged")
    assert(current.object_uri != previous.object_uri, "republished course kept the old object identity")

    old_response = client.get(previous.object_uri, headers: { "Accept" => Allure::Federation::MediaTypes::ACTIVITY_PUB })
    assert(old_response.status == 404, "withdrawn course returned HTTP #{old_response.status}")
  end

  def delete_segment
    publication = SegmentPublication.active.order(:id).last
    assert(publication.present?, "no active segment publication to withdraw")

    Segments::PublicationWithdrawal.new(user:, publication:).call!
  end

  def assert_segment_delete_a
    segment = wait_for("A tombstoned the withdrawn course") do
      record = RemoteSegment.order(:id).last
      record if record&.deleted? && record.recipients.where(status: "active").empty?
    end

    assert(segment.location_data_purged?, "deleted course retained location data")
    assert(segment.representation["redacted"] == true, "deleted course representation was not redacted")
    assert(segment.attachments.purged.count == 3, "deleted course media descriptors are not purged")

    response = client.get(segment.object_uri, headers: { "Accept" => Allure::Federation::MediaTypes::ACTIVITY_PUB })
    assert(response.status == 404, "withdrawn course returned HTTP #{response.status}")

    copy = Segment.where(remote_segment_id: RemoteSegment.select(:id)).order(:id).last
    assert(copy.present?, "the local copy did not survive the remote withdrawal")
  end

  def create_ring_segment(workout, name:, visibility: "public")
    create_privacy_zones
    track = workout.track_segments.order(:position).first
    assert(track.present?, "workout has no track segment")
    segment = Segments::Creator.new(
      user:,
      workout:,
      name:,
      start_index: 0,
      end_index: track.points.length - 1,
      sport: workout.sport
    ).call
    assert(segment.persisted?, "segment creation failed: #{segment.errors.full_messages.to_sentence}")
    segment.update!(
      visibility:,
      privacy_zone_acknowledged_at: Time.current
    )
    segment
  end

  # Unfollow withdraws the entitlement immediately. The public note keeps its
  # cached media (docs/dev/FEDERATION.md); the feed drops the author.
  def assert_withdrawal_a
    local_actor = Federation::ActorProvisioner.new(user:).call!
    note = wait_for("A withdrew the entitlement") do
      record = RemoteNote.active.order(:id).last
      record if record && !record.entitled_to?(local_actor)
    end

    assert(note.recipients.where(status: "active").none?, "an active entitlement remains after unfollow")
    assert(note.attachments.cached.count == 3, "public media was purged on unfollow")
    assert(!note.location_data_purged?, "public note location was redacted on unfollow")

    rows = Federation::FollowingFeed.new(actor: local_actor).relation.to_a
    assert(rows.none? { |row| row.kind == "remote" }, "the following feed still lists the unfollowed author")
  end

  def delete_actor_b
    Users::DeleteAccount.new(user:).call!
  end

  def assert_actor_delete_delivered_b
    event = FederationOutboxEvent.where(activity_type: "Delete", subject_type: "Actor").order(:id).last
    assert(event.present?, "no actor Delete event found")

    wait_for("B delivered the actor Delete") do
      event.deliveries.exists?(status: "delivered", last_response_status: 202)
    end
  end

  def assert_actor_gone_a
    actor = Actor.remote.find_by(uri: peer_actor_uri)
    assert(actor&.tombstoned?, "A did not tombstone the deleted remote author")

    response = client.get(peer_actor_uri, headers: { "Accept" => Allure::Federation::MediaTypes::ACTIVITY_PUB })
    assert(response.status == 410, "deleted actor endpoint returned HTTP #{response.status}")
  end

  # An explicit sweep replaces a development recurring entry: the key retires
  # only after every event and delivery is terminal (docs/dev/FEDERATION.md).
  def retire_actor_key_b
    Federation::RecoveryJob.perform_now
  end

  def assert_key_retired_b
    actor = Actor.local.find_by(uri: peer_actor_uri)
    assert(actor.present?, "B's local actor is missing")
    assert(actor.tombstoned?, "B's local actor was not tombstoned")
    assert(actor.private_key_retired_at.present?, "B's actor key was not retired")
    assert(actor.private_key_ciphertext.blank?, "B's actor key is still stored")
  end

  def peer_actor_uri = "http://#{PEER_DOMAIN}/users/marie"

  # --- Restricted federation (Slice 7) ---------------------------------------

  # The operator on B promotes A's authority. Only a promoted peer may receive
  # followers-only deliveries or fetch their media.
  def promote_peer
    FederationPeerPolicy.find_or_create_by!(domain: "allure-a.test:3002") do |policy|
      policy.capability_profile = "restricted_fetch"
    end
  end

  def publish_followers
    publish_workout(
      filename: "galibier.gpx",
      title: "Federation ring followers route",
      profile: followers_profile
    )
  end

  def assert_followers_delivery_b
    event = event_for("Create")
    assert(event.present?, "B has no followers Create event")

    wait_for("B delivered the followers Create to A's personal inbox") do
      event.deliveries.exists?(
        status: "delivered",
        last_response_status: 202,
        inbox_url: "http://allure-a.test:3002/users/marie/inbox"
      )
    end
  end

  def assert_restricted_create_a
    local_actor = Federation::ActorProvisioner.new(user:).call!
    note = wait_for("A persisted the followers Create") do
      candidate = FederationInboxItem.where(activity_type: "Create").order(:id).last
      next unless candidate&.processed?

      record = RemoteNote.find_by(object_uri: candidate.raw.dig("object", "id"))
      record if record&.active? && record.entitled_to?(local_actor)
    end

    assert(note.audience == "followers", "received note audience is #{note.audience.inspect}")
    assert(note.metrics.present?, "followers note has no metrics")
  end

  def assert_restricted_media_a
    note = wait_for("A cached the followers media with a signed fetch") do
      record = RemoteNote.order(:id).last
      next unless record&.active?
      next unless record.attachments.cached.count == 3

      record
    end

    assert(note.representation.dig("track", "features").present?, "restricted track was not parsed")
  end

  def publish_followers_segment
    workout = user.workouts.find_by!(title: "Federation ring followers route")
    segment = create_ring_segment(
      workout,
      name: "Federation ring followers course",
      visibility: "followers_only"
    )
    Segments::Publisher.new(user:, segment:).call!
  end

  def assert_restricted_segment_a
    local_actor = Federation::ActorProvisioner.new(user:).call!
    segment = wait_for("A persisted the followers course") do
      candidate = FederationInboxItem.where(activity_type: "Create").order(:id).last
      next unless candidate&.processed?

      record = RemoteSegment.find_by(object_uri: candidate.raw.dig("object", "id"))
      record if record&.active? && record.entitled_to?(local_actor)
    end

    assert(segment.audience == "followers", "received course audience is #{segment.audience.inspect}")
  end

  # Entitlement-gated HTTP isolation: only the follower's account renders the
  # followers course, its track, and its media; a second local account gets
  # 404 for all three.
  def assert_restricted_segment_page_a
    segment = wait_for("A cached the followers course media") do
      record = RemoteSegment.active.order(:id).last
      record if record && record.attachments.cached.count == 3
    end
    # Loaded before any integration session: the session executor leaves the
    # development query-log context unusable for a top-level query afterwards.
    paul = User.find_by!(username: "paul")

    entitled = integration_session(user)
    assert(
      segment_page_statuses(entitled, segment)[:statuses] == [ 200, 200, 200, 200 ],
      "the entitled follower did not receive the restricted course"
    )

    stranger = integration_session(paul)
    assert(
      segment_page_statuses(stranger, segment)[:statuses] == [ 404, 404, 404, 404 ],
      "an unrelated account reached the restricted course"
    )
  end

  def assert_signed_segment_object_a
    segment = RemoteSegment.active.order(:id).last
    accept = Allure::Federation::MediaTypes::ACTIVITY_PUB

    signed = signed_object_get(segment.object_uri, accept:)
    assert(signed.status == 200, "entitled signed course GET returned HTTP #{signed.status}")

    unsigned = client.get(segment.object_uri, headers: { "Accept" => accept })
    assert(unsigned.status == 404, "unsigned course GET returned HTTP #{unsigned.status}")

    paul = User.find_by!(username: "paul")
    paul_actor = Federation::ActorProvisioner.new(user: paul).call!
    wrong = signed_object_get(segment.object_uri, actor: paul_actor, accept:)
    assert(wrong.status == 404, "non-follower signed course GET returned HTTP #{wrong.status}")
  end

  # Entitlement-gated HTTP isolation: only the follower's account renders the
  # followers note and its media; a second local account gets 404 (docs/dev/FEDERATION.md
  # §17.2 item 9).
  def assert_restricted_page_a
    note = RemoteNote.active.order(:id).last
    # Loaded before any integration session: the session executor leaves the
    # development query-log context unusable for a top-level query afterwards.
    paul = User.find_by!(username: "paul")

    entitled = integration_session(user)
    assert(
      note_page_statuses(entitled, note)[:statuses] == [ 200, 200, 200 ],
      "the entitled follower did not receive the restricted note"
    )

    stranger = integration_session(paul)
    assert(
      note_page_statuses(stranger, note)[:statuses] == [ 404, 404, 404 ],
      "an unrelated account reached the restricted note"
    )
  end

  # The object endpoint reauthorizes every request: the entitled follower's
  # signed GET succeeds, an unsigned GET and a non-follower's signed GET 404.
  def assert_signed_object_a
    note = RemoteNote.order(:id).last
    accept = Allure::Federation::MediaTypes::ACTIVITY_PUB

    signed = signed_object_get(note.object_uri, accept:)
    assert(signed.status == 200, "entitled signed object GET returned HTTP #{signed.status}")

    unsigned = client.get(note.object_uri, headers: { "Accept" => accept })
    assert(unsigned.status == 404, "unsigned object GET returned HTTP #{unsigned.status}")

    paul = User.find_by!(username: "paul")
    paul_actor = Federation::ActorProvisioner.new(user: paul).call!
    wrong = signed_object_get(note.object_uri, actor: paul_actor, accept:)
    assert(wrong.status == 404, "non-follower signed object GET returned HTTP #{wrong.status}")
  end

  # One Note per peer (docs/dev/PUBLISHING.md): the same workout published to
  # the public beside its followers publication is not sent to the promoted
  # follower, which already holds the narrower Note.
  def publish_public_beside_followers
    publication = Workouts::Publisher.new(user:, workout: followers_workout, profile: public_profile).call!
    Workouts::RenderPublicationRouteImageJob.perform_now(publication) if publication.reload.route_image_pending?
  end

  def assert_public_withheld_b
    workout = followers_workout
    audiences = workout.active_publications.map(&:audience)
    assert(audiences == %w[followers public], "the workout carries #{audiences.inspect} instead of both audiences")

    event = wait_for("B expanded the public Create beside the followers one") do
      candidate = Workouts::PublicationWithdrawal.find_create_event(workout.active_publication_for("public"))
      candidate if candidate&.status.in?(%w[expanded complete])
    end
    assert(event.deliveries.none?, "the promoted follower was also sent the public Note")
  end

  def assert_single_note_a
    assert(RemoteNote.where(audience: "public").none?, "A received the public Note beside the followers one")
    assert(RemoteNote.where(audience: "followers").count == 1, "A does not hold exactly the followers Note")
  end

  def followers_workout = user.workouts.find_by!(title: "Federation ring followers route")

  # Public scenario, restricted federation off on both nodes: the followers
  # audience is publishable for local followers (docs/dev/FEDERATION.md), and even a
  # promoted peer is not sent it. The promotion is removed afterwards so the
  # rest of the public scenario runs against an unknown peer.
  def publish_unfederated_followers
    promote_peer
    publication = publish_workout(
      filename: "running_5k.gpx",
      title: "Federation ring local followers route",
      profile: followers_profile
    )
    Workouts::RenderPublicationRouteImageJob.perform_now(publication) if publication.reload.route_image_pending?
  end

  def assert_followers_withheld_b
    workout = user.workouts.find_by!(title: "Federation ring local followers route")
    assert(workout.active_publications.map(&:audience) == %w[followers], "the local followers publication is not active")

    event = wait_for("B expanded the followers Create") do
      candidate = Workouts::PublicationWithdrawal.find_create_event(workout.active_publication_for("followers"))
      candidate if candidate&.status.in?(%w[expanded complete])
    end
    assert(event.deliveries.none?, "B sent a followers publication with restricted federation off")
  ensure
    FederationPeerPolicy.where(domain: "allure-a.test:3002").destroy_all
  end

  def assert_no_followers_note_a
    assert(RemoteNote.where(audience: "followers").none?, "A received a followers note with restricted federation off")
  end

  def unfollow_b
    Federation::Unfollow.new(user:, target: "@marie@allure-b.test:3003").call!
  end

  def assert_restricted_revoked_a
    note = wait_for("A withdrew the followers entitlement and purged its media") do
      record = RemoteNote.order(:id).last
      record if record&.location_data_purged? && record.recipients.where(status: "active").none?
    end

    assert(note.attachments.purged.count == 3, "followers media was not purged")
    # B learns of the unfollow when it processes the delivered Undo, which can
    # land in the same second as this GET: the refusal is awaited, not raced.
    wait_for("B refused the withdrawn follower's signed object GET") do
      signed_object_get(note.object_uri, accept: Allure::Federation::MediaTypes::ACTIVITY_PUB).status == 404
    end
  end

  def assert_restricted_segment_revoked_a
    segment = wait_for("A withdrew the followers course entitlement and purged its media") do
      record = RemoteSegment.active.order(:id).last
      record if record&.location_data_purged? && record.recipients.where(status: "active").none?
    end

    assert(segment.attachments.purged.count == 3, "followers course media was not purged")
    wait_for("B refused the withdrawn follower's signed course GET") do
      signed_object_get(segment.object_uri, accept: Allure::Federation::MediaTypes::ACTIVITY_PUB).status == 404
    end
  end

  def signed_object_get(url, accept:, actor: nil)
    actor ||= Federation::ActorProvisioner.new(user:).call!
    Federation::SignedFetcher.new(actor:).get(url, accept:, max_bytes: 1.megabyte)
  end

  def followers_profile
    PublishingProfile.ensure_built_ins_for!(user)
    user.publishing_profiles.find_by!(built_in_key: "followers").tap do |profile|
      profile.update!(
        settings: profile.settings.merge(
          "gpx" => true, "route_image" => true, "mask_start" => false, "mask_finish" => false
        )
      )
    end
  end

  def user
    @user ||= User.find_by!(username: USERNAME)
  end

  # The public gate proves zone filtering removes the departure and the arrival
  # from the sanitized GPX, so this profile enables both endpoint masks: an
  # unmasked endpoint is deliberately exempt from zone filtering.
  def public_profile
    PublishingProfile.ensure_built_ins_for!(user)
    user.publishing_profiles.find_by!(built_in_key: "public").tap do |profile|
      profile.update!(
        settings: profile.settings.merge(
          "gpx" => true, "route_image" => true, "records" => true, "device" => true,
          "commute" => true, "weather" => true, "mask_start" => true, "mask_finish" => true
        )
      )
    end
  end

  # Endpoint zones for both ring fixtures: the public gate proves that zones
  # remove the departure and the arrival from multi_segment's sanitized GPX,
  # and a masked profile must be able to publish galibier too.
  def create_privacy_zones
    return if user.privacy_zones.exists?

    [
      [ "Start", 6.4000, 45.0000 ],
      [ "Finish", 6.4000, 45.0050 ],
      [ "Galibier start", 6.4077, 45.0640 ],
      [ "Galibier finish", 6.4117, 45.0670 ]
    ].each do |name, longitude, latitude|
      user.privacy_zones.create!(
        name:, latitude:, longitude:, radius_meters: 75, active: true
      )
    end
  end

  def assert_sanitized_gpx(uri)
    response = client.get(uri)
    assert(response.status == 200, "sanitized GPX returned HTTP #{response.status}")
    points = Nokogiri::XML(response.body).xpath("//*[local-name()='trkpt']").map do |node|
      [ Float(node["lat"]), Float(node["lon"]) ]
    end
    assert(points.length == 4, "sanitized GPX contains #{points.length} points instead of 4")
    assert(!points.include?([ 45.0, 6.4 ]), "sanitized GPX exposes the departure")
    assert(!points.include?([ 45.005, 6.4 ]), "sanitized GPX exposes the arrival")
  end

  def event_for(activity_type)
    FederationOutboxEvent.where(activity_type:).order(:id).last
  end

  # Admitted publication Creates, without the comments that answer them.
  def publication_creates
    FederationInboxItem.where(activity_type: "Create").where("raw -> 'object' ->> 'inReplyTo' IS NULL")
  end

  def delivered?(event)
    event&.complete? && event.deliveries.exists?(status: "delivered", last_response_status: 202)
  end

  def client
    @client ||= Federation::Transport::Client.new
  end

  def wait_for(description)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TIMEOUT
    loop do
      result = ActiveRecord::Base.uncached { yield }
      return result if result
      raise Failure, "timed out after #{TIMEOUT}s waiting for #{description}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 1
    end
  end

  def assert(condition, message)
    raise Failure, message unless condition
  end
end

phase = ARGV.fetch(0) { raise FederationRingTest::Failure, "a phase is required" }
FederationRingTest.new(phase).call
