Rails.application.routes.draw do
  resource :session
  # The second step of a password sign-in (docs/dev/AUTH.md).
  resource :session_challenge, only: %i[new create], path: "session/challenge" do
    post :options
    post :cancel
  end
  # Identity providers (docs/dev/AUTH.md). OmniAuth answers POST /auth/:provider
  # itself; these routes receive its verified callbacks.
  match "/auth/:provider/callback", to: "provider_callbacks#create", via: %i[get post],
                                    constraints: { provider: /google|oidc/ }, as: :provider_callback
  post "/auth/apple/form_post", to: "apple_form_posts#create", as: :apple_form_post
  # OmniAuth's test mode returns with a GET; the real return is the re-post.
  match "/auth/apple/return", to: "provider_callbacks#create", via: %i[get post], as: :apple_return
  get "/auth/failure", to: "provider_callbacks#failure", as: :provider_failure
  # The iOS companion's provider sign-in (docs/dev/AUTH.md): started in the
  # system browser, collected by the app's web view.
  get "/auth/ios/:provider", to: "companion_provider_starts#show", as: :companion_provider_start
  resource :session_handoff, only: :create, path: "session/handoff"
  resource :onboarding, only: %i[new create destroy], path: "auth/onboarding"
  # Re-authentication before a sensitive action (docs/dev/AUTH.md).
  resource :reauthentication, only: %i[new create], path: "session/reauthenticate" do
    post :options
  end
  resources :passwords, param: :token
  # Open registration (M4): sign-up plus live username availability, gated by
  # ALLOW_REGISTRATION. The closed branch states so plainly, with no dead link.
  resource :registration, only: %i[new create] do
    get :availability, on: :collection
  end
  # Release notes: the footer's what's-new dialog acknowledges the running
  # version once per account. State only, no HTML form, hence :update alone.
  resource :release_notes, only: :update, path: "release-notes"
  get "/funding", to: "funding#show", as: :funding
  get "/funding/thanks", to: "funding#thanks", as: :funding_thanks
  post "/funding/portal/:subscription_id", to: "funding#portal", as: :funding_portal
  post "/funding/webhooks/:provider", to: "funding/webhooks#create", as: :funding_webhook
  # Operator administration console (docs/dev/ADMIN.md). Every route inherits the
  # 404-for-non-operators gate from Admin::BaseController, and the product
  # chrome never links here except for the configured operator.
  namespace :admin do
    root to: "dashboard#show"
    get "/funding", to: "funding#index", as: :funding
    post "/accounts/:account_id/funding", to: "funding#create", as: :account_funding
    delete "/funding/:id", to: "funding#destroy", as: :funding_contribution
    post "/funding/subscriptions/:id/attachment", to: "funding#attach", as: :funding_subscription_attachment
    # Background jobs (docs/dev/ADMIN.md): the live panel and its recovery
    # controls. Every action is operator-gated by Admin::BaseController and
    # audited.
    get "/jobs", to: "jobs#show", as: :jobs
    post "/jobs/failed/retry_all", to: "jobs#retry_all", as: :jobs_retry_all
    post "/jobs/failed/discard_all", to: "jobs#discard_all", as: :jobs_discard_all
    post "/jobs/failed/:id/retry", to: "jobs#retry_job", as: :job_retry
    post "/jobs/failed/:id/discard", to: "jobs#discard_job", as: :job_discard
    post "/jobs/queues/:queue_name/pause", to: "jobs#pause_queue", as: :queue_pause
    post "/jobs/queues/:queue_name/resume", to: "jobs#resume_queue", as: :queue_resume
    post "/jobs/rebuild", to: "jobs#rebuild", as: :jobs_rebuild
    post "/jobs/route_images", to: "jobs#backfill_route_images", as: :jobs_backfill_route_images
    post "/jobs/segment_route_images", to: "jobs#backfill_segment_route_images", as: :jobs_backfill_segment_route_images
    post "/jobs/backfill_elevation", to: "jobs#backfill_elevation", as: :jobs_backfill_elevation
    post "/jobs/backfill_weather", to: "jobs#backfill_weather", as: :jobs_backfill_weather
    post "/jobs/backfill_places", to: "jobs#backfill_places", as: :jobs_backfill_places
    post "/jobs/backfill_toponymy", to: "jobs#backfill_toponymy", as: :jobs_backfill_toponymy
    post "/jobs/loop_reuse", to: "jobs#backfill_loop_reuse", as: :jobs_backfill_loop_reuse
    post "/jobs/elevation_profiles", to: "jobs#backfill_elevation_profiles", as: :jobs_backfill_elevation_profiles
    post "/jobs/segment_terrain_elevation", to: "jobs#backfill_segment_terrain_elevation",
                                            as: :jobs_backfill_segment_terrain_elevation
    post "/jobs/segment_places", to: "jobs#backfill_segment_places", as: :jobs_backfill_segment_places
    post "/jobs/together_detection", to: "jobs#backfill_together_detection", as: :jobs_backfill_together_detection
    post "/jobs/heart_rate", to: "jobs#backfill_heart_rate", as: :jobs_backfill_heart_rate
    post "/jobs/route_suggestions", to: "jobs#backfill_route_suggestions", as: :jobs_backfill_route_suggestions
    # Federation (docs/dev/ADMIN.md): the former /settings/federation surface,
    # moved into the console and expanded. Every mutation is operator-gated by
    # Admin::BaseController and audited.
    get "/federation", to: "federation#show", as: :federation
    post "/federation/domain_blocks", to: "federation#create_domain_block", as: :federation_domain_blocks
    delete "/federation/domain_blocks/:id", to: "federation#destroy_domain_block", as: :federation_domain_block
    post "/federation/actor_blocks", to: "federation#create_actor_block", as: :federation_actor_blocks
    delete "/federation/actor_blocks/:id", to: "federation#destroy_actor_block", as: :federation_actor_block
    post "/federation/peer_policies", to: "federation#create_peer_policy", as: :federation_peer_policies
    delete "/federation/peer_policies/:id", to: "federation#destroy_peer_policy", as: :federation_peer_policy
    post "/federation/media_retry", to: "federation#retry_media", as: :federation_media_retry
    # Publications (docs/dev/ADMIN.md): oversight lists and takedown through
    # the immutable withdrawal lifecycle.
    get "/publications", to: "publications#index", as: :publications
    post "/publications/workouts/:id/withdraw", to: "publications#withdraw_workout",
         as: :workout_publication_withdraw
    post "/publications/courses/:id/withdraw", to: "publications#withdraw_course",
         as: :course_publication_withdraw
    # Accounts and invitations (docs/dev/ADMIN.md).
    get "/accounts", to: "accounts#index", as: :accounts
    get "/accounts/:id", to: "accounts#show", as: :account
    patch "/accounts/:id/photo_quota", to: "accounts#photo_quota", as: :account_photo_quota
    post "/accounts/:id/suspend", to: "accounts#suspend", as: :account_suspend
    post "/accounts/:id/reinstate", to: "accounts#reinstate", as: :account_reinstate
    post "/accounts/:id/reset_second_factor", to: "accounts#reset_second_factor", as: :account_reset_second_factor
    # docs/dev/ACCOUNT.md: the operator schedules or cancels a deletion.
    post "/accounts/:id/deletion", to: "accounts#schedule_deletion", as: :account_deletion
    delete "/accounts/:id/deletion", to: "accounts#cancel_deletion", as: nil
    # docs/dev/API.md: audited token revocation and webhook disabling.
    post "/accounts/:account_id/api_tokens/:id/revocation", to: "api_access#revoke_token", as: :account_api_token_revocation
    post "/accounts/:account_id/webhooks/:id/disabling", to: "api_access#disable_webhook", as: :account_webhook_disabling
    get "/invitations", to: "invitations#index", as: :invitations
    get "/invitations/new", to: "invitations#new", as: :new_invitation
    post "/invitations", to: "invitations#create"
    delete "/invitations/:id", to: "invitations#destroy", as: :invitation
    # Import failures and system diagnostics (docs/dev/ADMIN.md).
    get "/imports", to: "imports#index", as: :imports
    # Remote import connections (docs/dev/REMOTE-IMPORTS.md), before `:id`.
    get "/imports/connections", to: "import_connections#index", as: :import_connections
    post "/imports/connections/:id/revoke", to: "import_connections#revoke", as: :import_connection_revoke
    get "/imports/:id", to: "imports#show", as: :import
    get "/system", to: "system#show", as: :system
    # The audit log (docs/dev/ADMIN.md).
    get "/events", to: "events#index", as: :events
  end
  # Owner-only place-name suggestions for the workout list's autocomplete
  # (DESIGN.md §13). Declared before the resource so it never matches `:id`.
  get "/workouts/place_suggestions", to: "workout_place_suggestions#index", as: :workout_place_suggestions
  # Bulk activity operations (docs/dev/BULK-ACTIONS.md, DESIGN.md §10.19). The
  # static collection paths come before the member `:id` so `/workouts/bulk/
  # apply` and `/review` never resolve as an operation id; everything is
  # owner-scoped in the controller.
  patch "/workouts/bulk/apply", to: "workout_bulk_operations#apply", as: :apply_workout_bulk_operations
  post "/workouts/bulk/review", to: "workout_bulk_operations#review", as: :review_workout_bulk_operations
  get "/workouts/bulk/:id", to: "workout_bulk_operations#show", as: :workout_bulk_operation
  patch "/workouts/bulk/:id", to: "workout_bulk_operations#update"
  get "/workouts/bulk/:id/status", to: "workout_bulk_operations#status", as: :status_workout_bulk_operation
  post "/workouts/bulk/:id/cancel", to: "workout_bulk_operations#cancel", as: :cancel_workout_bulk_operation
  # A workout typed in by hand from the import page (docs/dev/MANUAL-ENTRY.md);
  # it is edited through the workout's own edit page.
  post "/workouts/manual", to: "manual_workouts#create", as: :manual_workouts
  # The M1 single-file import page merged into the one import surface
  # (DESIGN.md §20.5); a redirect keeps bookmarks working, query string
  # included (locale). `POST /workouts` created through it and is gone.
  get "/workouts/new", to: redirect { |_params, request|
    query = request.query_string
    query.present? ? "/workout_imports/new?#{query}" : "/workout_imports/new"
  }
  resources :workouts, except: %i[new create] do
    resources :photos, only: %i[index create show update destroy], controller: "workout_photos" do
      get :gallery, on: :collection
      patch :order, on: :collection
      patch :sort, on: :collection
      patch :time_offset, on: :collection
      post :retry, on: :member
      patch :placement, on: :member
    end
    member do
      post :publish
      post :republish
      post :delivery_refresh
      # Delayed publishing (docs/dev/DELAYED-PUBLISHING.md): leave the safety
      # delay early, move its planned moment, or cancel it with no trace.
      post :activate_publication
      patch :reschedule_publication
      delete :scheduled_publication, action: :destroy_scheduled_publication
      # Automatic publishing (docs/dev/AUTO-PUBLISHING.md): the owner declines a
      # waiting automatic publication before it happens.
      delete :auto_publication, action: :destroy_auto_publication
      get :publication_preview
      delete :publication, action: :destroy_publication
    end
    resource :track, only: :show, controller: "workout_tracks"
    resource :chart, only: :show, controller: "workout_charts"
    resource :toponymy, only: :show, controller: "workout_toponymies"
    resource :segment_selection, only: :show, controller: "workout_segment_selections"
    # Owner-only elevation source switch (docs/dev/ELEVATION.md).
    resource :elevation_source, only: :update, controller: "workout_elevation_sources"
    # Owner-requested weather refresh (docs/dev/WEATHER.md).
    resource :weather, only: :create, controller: "workout_weathers"
    resources :segments, only: %i[new create]
    resources :routes, only: %i[new create]
    resource :original_file, only: :show, controller: "workout_files"
    resource :route_image, only: :show, controller: "workout_route_images"
    # Owner-requested re-render of the owner image (docs/dev/DERIVATIONS.md);
    # the bulk maintenance lives in /settings/data and /admin/jobs. The path
    # deliberately avoids the `/route_image` prefix so the detail page's
    # "no stored image URL" guard stays an unambiguous substring check.
    post "regenerate_route_image", to: "workout_route_images#regenerate", as: :regenerate_route_image
    # The local reaction gesture (docs/dev/REACTIONS.md): one PUT toggles the
    # viewer's reaction on the active publication.
    resource :reaction, only: :update, controller: "workout_reactions"
    # Shared activities (docs/dev/SHARED-ACTIVITIES.md): the owner invites, the participant
    # answers or later links their own recording, either party withdraws.
    resources :participations, only: %i[create update destroy], controller: "workout_participations" do
      patch :convert, on: :member
      patch :dismiss_link_suggestion, on: :member
    end
    # The workout's thread (docs/dev/COMMENTS.md): a reader posts a comment
    # or a reply, the owner closes or reopens it. The index is the thread's own
    # page, the one the phone layout opens (DESIGN.md §10.20).
    resources :comments, only: %i[index create], controller: "workout_comments"
    resource :comment_thread, only: :update, controller: "workout_comment_threads"
  end
  # The author deletes a comment, the thread host removes one: one route, the
  # controller tells them apart.
  resources :comments, only: :destroy
  # Recurring-route suggestions (docs/dev/SEGMENTS.md): the owner dismisses
  # one from its banner; saving the route is the acceptance.
  resources :route_suggestions, only: [] do
    patch :dismiss, on: :member
  end
  # Local publication media: the browser-facing counterpart of the signed
  # federation media endpoints. The browser principal goes through
  # Workouts::PublicationPolicy; the owner source endpoints above stay separate.
  get "/publications/:id/media/gpx", to: "publication_media#gpx", as: :publication_gpx
  get "/publications/:id/media/route-image", to: "publication_media#route_image", as: :publication_route_image
  get "/publications/:id/media/photos/:photo_id", to: "publication_media#photo", as: :publication_photo
  resources :equipments do
    post :refresh, on: :member
  end
  # Personal hub (M4): the owner's analytical home. Its detail pages —
  # /me/stats and /me/records — live under the same path and are reached from
  # here, not from the sidebar. The pulse endpoint serves the older weekly
  # windows the waveform scrolls back to (DESIGN.md §15.1).
  get "/me", to: "me#show", as: :me
  get "/me/pulse", to: "me#pulse", as: :pulse_me
  # In-app notifications (docs/dev/NOTIFICATIONS.md): the topbar bell's badge and
  # dropdown, the paginated inbox, and read state. Owner-scoped throughout.
  resources :notifications, only: %i[index show] do
    collection do
      get :badge
      get :menu
      post :mark_all_read
    end
  end
  # The companion drops its push subscription when it leaves this server
  # (docs/dev/PUSH.md): no session, the device's `auth` secret is the proof.
  post "/push/unsubscribe", to: "push_unsubscriptions#create", as: :push_unsubscribe
  # Stats hub (M4): landing page for the by_time / by_sport datasets.
  get "/me/stats", to: "stats#show", as: :stats
  resources :stats, only: [], path: "me/stats" do
    collection do
      get :by_time
      get :by_sport
      # Time in each heart-rate zone per week or month (docs/dev/HEART-RATE.md).
      get :heart_rate
    end
  end
  # The records hub (M1): the classic record types and the per-distance best
  # efforts.
  resources :records, only: %i[index], path: "me/records"
  # The analytical pages answered at /stats and /records before they moved
  # under /me. Permanent redirects carry the format and the query string
  # (granularity, sport filter), so bookmarks and shared links keep working.
  moved_analytics = lambda do |target|
    redirect do |params, request|
      destination = params[:format].present? && params[:format] != "html" ? "#{target}.#{params[:format]}" : target
      query = request.query_string
      query.present? ? "#{destination}?#{query}" : destination
    end
  end
  get "/stats/by_time", to: moved_analytics.call("/me/stats/by_time")
  get "/stats/by_sport", to: moved_analytics.call("/me/stats/by_sport")
  get "/stats", to: moved_analytics.call("/me/stats")
  get "/records", to: moved_analytics.call("/me/records")
  post "workout_imports/strava_archive", to: "strava_archive_imports#create", as: :strava_archive_imports
  resources :workout_imports, only: %i[new create show] do
    member do
      get :status
      post :cancel
    end
  end
  resources :privacy_zones, path: "settings/privacy-zones", except: :show do
    get :search, on: :collection
  end
  resources :publishing_profiles, path: "settings/publishing-profiles" do
    member do
      post :restore_defaults
    end
  end
  namespace :settings do
    resource :profile, only: %i[show update], controller: "profiles"
    # Generated-avatar shuffle (DESIGN.md §9.4): rotates the persisted seed and
    # answers the preview fragment only.
    patch "profile/avatar", to: "profiles#regenerate_avatar", as: :profile_avatar
    # Appearance (M4): theme and locale. The theme toggle PATCHes update
    # directly; the page edits both through the account.
    resource :appearance, only: %i[show update], controller: "appearance"
    # Units (M4): unit system, time zone, and week start.
    resource :units, only: %i[show update], controller: "units"
    # Elevation (docs/dev/ELEVATION.md): opt in to terrain elevation for workouts
    # without a recorded profile.
    resource :elevation, only: %i[show update], controller: "elevation"
    # Weather (docs/dev/WEATHER.md): explicit consent to send coarsened
    # positions and times to Open-Meteo, and the deletion of stored weather.
    resource :weather, only: %i[show update destroy], controller: "weather"
    # Sports (docs/dev/WORKOUT.md): which variant replaces a detected generic
    # sport (cycling, running, walking) at import time.
    resource :sports, only: %i[show update], controller: "sports"
    # Notifications (docs/dev/NOTIFICATIONS.md): which follow events reach the
    # account's in-app inbox.
    resource :notifications, only: %i[show update], controller: "notifications"
    # Push on the iOS companion (docs/dev/PUSH.md): the current session's own
    # subscription, JSON only.
    resource :push_subscription, only: %i[create update destroy], controller: "push_subscriptions"
    # Data (docs/dev/DERIVATIONS.md): owner-scoped rebuilds of derived data.
    # Every action is scoped to the current account's workouts.
    resource :data, only: :show, controller: "data"
    post "data/rebuild", to: "data#rebuild", as: :data_rebuild
    post "data/route_images", to: "data#route_images", as: :data_route_images
    post "data/segment_images", to: "data#segment_images", as: :data_segment_images
    post "data/places", to: "data#places", as: :data_places
    post "data/elevation", to: "data#elevation", as: :data_elevation
    post "data/weather", to: "data#weather", as: :data_weather
    post "data/loops", to: "data#loops", as: :data_loops
    post "data/heart_rate", to: "data#heart_rate", as: :data_heart_rate
    post "data/route_suggestions", to: "data#route_suggestions", as: :data_route_suggestions
    # Heart rate (docs/dev/HEART-RATE.md): the account's maximum, resting
    # value and zones. Owner-only; nothing here is ever published.
    resource :heart_rate, only: %i[show update destroy], path: "heart-rate", controller: "heart_rate"
    # Account (docs/dev/ACCOUNT.md): the data export and the self-service
    # deletion, with the page a deactivated account lands on.
    resource :account, only: :show, controller: "account"
    resources :account_exports, only: :create, path: "account/exports" do
      get :download, on: :member
    end
    resource :account_deletion, only: %i[show create destroy], path: "account/deletion", controller: "account_deletions"
    # Security (M4): password change, per-session revoke, sign out everywhere.
    resource :security, only: :show, controller: "security"
    patch "security/password", to: "security#update_password", as: :security_password
    delete "security/sessions/:id", to: "security#destroy_session", as: :security_session
    delete "security/sessions", to: "security#destroy_all_sessions", as: :destroy_all_security_sessions
    # Second factors (docs/dev/AUTH.md).
    post "security/reminder/dismiss", to: "security#dismiss_reminder", as: :dismiss_second_factor_reminder
    resource :totp, only: %i[new create destroy], path: "security/totp"
    resources :passkeys, only: %i[create destroy], path: "security/passkeys" do
      post :options, on: :collection
    end
    resource :recovery_codes, only: %i[show create], path: "security/recovery-codes"
    resources :identities, only: :destroy, path: "security/identities"
    # API tokens (docs/dev/API.md, DESIGN.md §20.18).
    resource :api, only: :show, controller: "api"
    resources :api_tokens, only: %i[new create destroy], path: "api/tokens" do
      get :created, on: :collection
    end
    resources :webhooks, path: "api/webhooks", except: :index do
      member do
        get :secret
        patch :toggle
        post :ping
        post :rotate_secret
      end
    end
    post "api/webhook_deliveries/:id/redelivery", to: "webhooks#redeliver", as: :webhook_delivery_redelivery
    # Federation (M5): the operator console took over the diagnostics and
    # controls at /admin/federation for every mutation; this legacy address
    # only redirects an operator and answers 404 to everyone else.
    resource :federation, only: :show, controller: "federation"
  end
  # Settings entry (M4): /settings renders the universal settings hub
  # (DESIGN.md §8.5). From md up the sub-page shell repeats its navigation;
  # below md each sub-page links back to this hub.
  get "/settings", to: "settings/entry#show", as: :settings
  # Connected services (docs/dev/REMOTE-IMPORTS.md, DESIGN.md §8.6): their own
  # area beside /settings, reached from the account menu. The hub lists every
  # remote import source the account may see; each service keeps its own page,
  # so a link or an unlink never refreshes another service's form.
  get "/connections", to: "connections#index", as: :connections
  scope "connections/:provider", controller: "connections",
                                 constraints: { provider: Regexp.union(Allure::RemoteImports::Config.providers) } do
    get "", action: :show, as: :connection
    patch "", action: :update, as: nil
    delete "", action: :destroy, as: nil
    post "link", action: :link, as: :connection_link
    delete "link", action: :cancel_link, as: nil
    post "mfa", action: :mfa, as: :connection_mfa
    post "retrievals", action: :retrieve, as: :connection_retrievals
    post "sync", action: :sync, as: :connection_sync
    post "equipment", action: :sync_equipment, as: :connection_equipment
  end
  # The area moved out of settings: old links, bookmarks and notifications land
  # on the hub, which lists whatever the account may still see.
  get "/settings/connections", to: redirect("/connections")
  resource :federation_follow, only: %i[create destroy], controller: "federation_follows"
  get "/api/v1/trail/:id/media/gpx", to: "federation/media#gpx", as: :workout_publication_gpx
  get "/api/v1/trail/:id/media/route-image", to: "federation/media#route_image", as: :workout_publication_route_image
  get "/api/v1/trail/:id/media/route-image-dark", to: "federation/media#route_image_dark", as: :workout_publication_route_image_dark
  get "/api/v1/trail/:id", to: "federation/workouts#show", as: :workout_publication
  # Course publications (docs/dev/SEGMENTS-FEDERATION.md). The dedicated path
  # is what distinguishes a course Note from a workout Note on the wire.
  get "/api/v1/segment/:id/media/gpx", to: "federation/segment_media#gpx", as: :segment_publication_gpx
  get "/api/v1/segment/:id/media/route-image", to: "federation/segment_media#route_image", as: :segment_publication_route_image
  get "/api/v1/segment/:id/media/route-image-dark", to: "federation/segment_media#route_image_dark", as: :segment_publication_route_image_dark
  get "/api/v1/segment/:id", to: "federation/segments#show", as: :segment_publication
  # A local author's comment as an object (docs/dev/COMMENTS.md).
  get "/api/v1/comment/:id", to: "federation/comments#show", as: :comment_object
  # The public REST API (docs/dev/API.md). Under /api/rest/v1, never /api/v1,
  # which names the ActivityPub objects above. docs/openapi/v1.yaml documents
  # exactly these paths, and a guard spec keeps the two in step.
  namespace :api do
    namespace :rest do
      namespace :v1 do
        get "openapi.:format", to: "documents#show", as: :openapi, constraints: { format: /json|yaml/ }
        get "me", to: "accounts#me"
        get "sports", to: "accounts#sports"
        # PATCH only: a partial update is the one write a workout takes.
        patch "workouts/:id", to: "workouts#update", as: nil
        resources :workouts, only: %i[index show create destroy] do
          member do
            get :track
            get :original
            get :laps
            get :splits
            get :best_efforts
            get :segment_efforts
          end
          resources :publications, only: %i[index create]
        end
        post "workouts/:workout_id/publication_previews", to: "publications#preview", as: nil
        patch "publications/:id", to: "publications#update", as: nil
        delete "publications/:id", to: "publications#destroy", as: nil
        post "publications/:id/activation", to: "publications#activate", as: nil
        # Social reads (docs/dev/API.md): what the account may read on the web.
        get "feed", to: "social#feed"
        get "followers", to: "social#followers"
        get "following", to: "social#following"
        get "workouts/:workout_id/comments", to: "social#workout_comments", as: nil
        get "workouts/:workout_id/reactions", to: "social#workout_reactions", as: nil
        get "publications/:id", to: "reader_publications#show", as: nil
        get "publications/:id/track", to: "reader_publications#track", as: nil
        get "publications/:id/route_image", to: "reader_publications#route_image", as: nil
        get "publications/:id/comments", to: "reader_publications#comments", as: nil
        get "remote_notes/:id", to: "remote_notes#show", as: nil
        get "remote_notes/:id/track", to: "remote_notes#track", as: nil
        get "remote_notes/:id/route_image", to: "remote_notes#route_image", as: nil
        get "remote_notes/:id/comments", to: "remote_notes#comments", as: nil
        resources :records, only: :index
        # Webhooks (docs/dev/API.md).
        resources :webhooks, only: %i[index show create destroy]
        patch "webhooks/:id", to: "webhooks#update", as: nil
        post "webhooks/:id/ping", to: "webhooks#ping", as: nil
        post "webhooks/:id/secret_rotation", to: "webhooks#rotate_secret", as: nil
        get "webhooks/:id/deliveries", to: "webhooks#deliveries", as: nil
        post "webhook_deliveries/:id/redelivery", to: "webhooks#redeliver", as: nil
        resources :imports, only: %i[index show create destroy]
        resources :equipment, only: %i[index show]
        resources :publishing_profiles, only: :index
        match "*path", to: "fallbacks#not_found", via: :all, format: false
        match "/", to: "fallbacks#not_found", via: :all
      end
    end
  end
  # The Model Context Protocol endpoint for AI assistants (docs/dev/MCP.md).
  post "/mcp", to: "mcp#create", as: :mcp
  match "/mcp", to: "mcp#method_not_allowed", via: %i[get delete put patch]
  # The API reference (docs/dev/API.md), members-only.
  get "/developers/api", to: "developers#api", as: :developers_api
  get "/developers/api/reference", to: "developers#reference", as: :developers_api_reference
  get "/developers", to: redirect("/developers/api")
  # Members' help on the product's concepts (DESIGN.md §20.20).
  get "/help", to: "help#index", as: :help
  get "/help/:topic", to: "help#show", as: :help_topic
  # Passkeys in the iOS companion (docs/dev/AUTH.md).
  get "/.well-known/apple-app-site-association", to: "apple_app_site_associations#show",
                                                 as: :apple_app_site_association
  get "/.well-known/webfinger", to: "federation/webfinger#show", as: :webfinger
  # Prometheus text exposition for external Grafana/Prometheus scraping
  # (docs/dev/METRICS.md). The Rack endpoint answers 404 unless METRICS_TOKEN is
  # set, so an instance without metrics configured exposes nothing.
  mount Allure::Metrics::Endpoint.new => "/metrics"
  get "/.well-known/nodeinfo", to: "federation/node_info#discovery", as: :nodeinfo_discovery
  get "/nodeinfo/2.1", to: "federation/node_info#show", as: :nodeinfo_21, defaults: { version: "2.1" }
  get "/nodeinfo/2.2", to: "federation/node_info#show", as: :nodeinfo_22, defaults: { version: "2.2" }
  get "/users/:username", to: "federation/actors#show", as: :user_actor
  get "/users/:username/:collection", to: "federation/collections#show", as: :user_collection
  post "/inbox", to: "federation/inboxes#create_shared", as: :federation_shared_inbox
  post "/users/:username/inbox", to: "federation/inboxes#create", as: :federation_inbox
  # M5 relationships: exact-handle remote profiles (handles contain @ and may
  # carry a port). These must precede the local profile routes below.
  get "/people", to: "people#index", as: :people
  get "/people/search", to: "people#search", as: :search_people
  post "/people/resolve", to: "people#resolve", as: :resolve_people
  patch "/people/follows/:id", to: "people/follow_decisions#update", as: :people_follow
  delete "/people/followers/:id", to: "people/followers#destroy", as: :people_follower
  delete "/people/suggestions/:id", to: "people/suggestions#destroy", as: :people_suggestion
  get "/@:handle", to: "remote_profiles#show", as: :remote_profile,
                   constraints: { handle: /[^@\/]+@[^@\/]+/ }
  get "/@:handle/avatar", to: "remote_avatars#show", as: :remote_profile_avatar,
                          constraints: { handle: /[^@\/]+@[^@\/]+/ }
  get "/remote_notes/:id/media/gpx", to: "remote_note_media#gpx", as: :remote_note_gpx
  get "/remote_notes/:id/media/route-image", to: "remote_note_media#route_image", as: :remote_note_route_image
  get "/remote_notes/:id/track", to: "remote_note_tracks#show", as: :remote_note_track
  get "/remote_notes/:id/chart", to: "remote_note_charts#show", as: :remote_note_chart
  get "/remote_notes/:id", to: "remote_notes#show", as: :remote_note
  # The invited account's answer to another instance's invitation
  # (docs/dev/SHARED-ACTIVITIES.md).
  resources :remote_participations, only: :update
  # The local reaction gesture on a received note (docs/dev/REACTIONS.md).
  put "/remote_notes/:id/reaction", to: "remote_note_reactions#update", as: :remote_note_reaction
  # A comment on a received note, sent to its origin (docs/dev/COMMENTS.md).
  # Its thread's own page comes first and names the helper both share.
  get "/remote_notes/:id/comments", to: "remote_note_comments#index", as: :remote_note_comments
  post "/remote_notes/:id/comments", to: "remote_note_comments#create"
  # Received courses: the same application-mediated boundary as remote notes,
  # with a copy-as-local action and no chart (docs/dev/SEGMENTS-FEDERATION.md).
  get "/remote_segments/:id/media/gpx", to: "remote_segment_media#gpx", as: :remote_segment_gpx
  get "/remote_segments/:id/media/route-image", to: "remote_segment_media#route_image", as: :remote_segment_route_image
  get "/remote_segments/:id/track", to: "remote_segment_tracks#show", as: :remote_segment_track
  post "/remote_segments/:id/import", to: "remote_segment_imports#create", as: :remote_segment_import
  get "/remote_segments/:id", to: "remote_segments#show", as: :remote_segment
  get "/@:username", to: "profiles#show", as: :profile
  get "/@:username/avatar", to: "avatars#show", as: :profile_avatar
  resource :feedback, only: :create, controller: "feedback"
  # Discover map (docs/dev/SEGMENTS.md): the viewport read behind the
  # Découvrir map. Declared before the resource so `discover_map` never matches
  # `:id`.
  get "/segments/discover_map", to: "segment_discoveries#show", as: :segments_discover_map
  # The first step of creating a course (DESIGN.md §20.6): choose the source
  # activity, then select the portion on the workout's own creation page.
  get "/segments/new", to: "segment_sources#new", as: :new_segment
  resources :segments, only: %i[index show edit update destroy] do
    member do
      post :publish
      post :republish
      delete :publication, action: :destroy_publication
    end
    resource :leaderboard, only: :show, controller: "segment_leaderboards"
    # Copies another account's shared course into the copier's private
    # segments, forward or reversed; never the owner's own course.
    resource :copy, only: :create, controller: "segment_copies"
    resource :opt_out, only: %i[create destroy], controller: "segment_opt_outs"
    resources :efforts, only: :index, controller: "segment_efforts"
    resource :track, only: :show, controller: "segment_tracks"
    # The stored course elevation profile, same visibility gate as the track.
    resource :chart, only: :show, controller: "segment_charts"
    # The owner route image, served through the application at the course's own
    # visibility like the track; never a raw storage URL (docs/dev/SEGMENTS.md).
    resource :route_image, only: :show, controller: "segment_route_images"
  end
  # Public publications feed. Canonical address for the feed and the anchor for
  # the future M5 following/federated tabs.
  get "/feed", to: "feeds#show", as: :feed
  # The following stream merged into /feed as a URL-driven switch; the old
  # address stays as a redirect for bookmarks and shared links.
  get "/following", to: redirect("/feed", status: 302), as: :following
  # Root dispatches by session: members land on their personal hub, visitors on
  # the feed. The feed itself never lives at "/".
  root "home#show"

  # Liveness probe for load balancers and uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check

  # ---------------------------------------------------------------------------
  # Federation endpoints (M2). Declared here early because their shape is fixed
  # by the protocol and by what remote implementations expect:
  #
  #   /.well-known/webfinger   discovery
  #   /users/:username         the actor  (Accept-negotiated)
  #   /@:username              the human-readable profile
  #
  # See PLAN.md §3.
  # ---------------------------------------------------------------------------

  # Reached via config.exceptions_app, and directly addressable so the pages can
  # be previewed and tested like any other.
  match "/404", to: "errors#not_found", via: :all, as: :not_found
  match "/410", to: "errors#gone", via: :all, as: :gone
  match "/422", to: "errors#unprocessable_entity", via: :all, as: :unprocessable_entity
  match "/500", to: "errors#internal_server_error", via: :all, as: :internal_server_error

  # Component styleguide (DESIGN.md §22). Development and test only — the
  # controller raises 404 in production. Deliberately outside the navigation
  # tree: it is a tool, not a destination.
  get "/styleguide", to: "styleguide#show", as: :styleguide

  # Installable identity (DESIGN.md §23). Manifest only; no service worker.
  get "/manifest.json", to: "pwa#manifest", as: :pwa_manifest
end
