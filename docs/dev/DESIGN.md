# Allure — Design System & UX Reference

The single source of truth for how Allure looks, reads and behaves.

`[devdoc:<topic>]` marks developer documentation that is not published yet.
The sentence around the marker states the rule that must hold; keep the marker
until the document lands. `grep -rn '\[devdoc:' docs/dev AGENTS.md` lists every
pending topic. Milestone names (M3, M4.5, M5) refer to the roadmap
(`[devdoc:roadmap]`).

This document is **binding**, not aspirational. Where it contradicts a screen
that exists today, the screen is wrong and the document names it in §25.

It is a design reference only. It contains no delivery slices, no exit criteria
and no schedule; those belong to the roadmap and the milestone specifications
(`[devdoc:roadmap]`).

It assumes the tracking-depth dataset described in `[devdoc:tracking-depth]`:
reusable routes, loops, recorded laps, splits, personal bests, shared local
leaderboards, TCX/KML/KMZ import, records and equipment. Statistics, the
calendar dataset, and the navigation/UI consolidation are not shipped yet.
Sections describing statistics and the calendar (§8.4, §15.3, §20.2, §20.10)
therefore specify surfaces that do not exist yet; everything else describes
surfaces that do, and §25 records where they currently deviate.

---

## 1. Scope

### 1.1 What this document binds

Every user-facing surface of the local product:

- authentication and password flows;
- the application chrome (primary navigation, topbar, mobile navigation, footer);
- home feed, personal hub, workouts, import, segments, records,
  equipment, statistics, settings, public profile;
- the shared component vocabulary, its states, its copy and its accessibility;
- the visual language: tokens, sport identity, typography, density, motion,
  dark mode;
- data visualisation rules for maps and charts;
- the mandatory copy patterns around publishing, privacy and deletion.

### 1.2 What this document does not bind

- **Backend contracts.** Units, identifiers, publication lifecycle, GPX
  algorithms, federation identity and geometry axis order are locked by
  [WORKOUT.md](WORKOUT.md), [PUBLISHING.md](PUBLISHING.md), [FEDERATION.md](FEDERATION.md) and
  `AGENTS.md`. Design never overrides them; where a design need conflicts with
  one, the matching developer document is amended first.
- **M5 federation screens.** Remote profiles, follow, the merged `/feed`
  personal stream, operator federation settings, and remote publication and
  course rendering now ship; this document binds their shared vocabulary,
  states and accessibility, and §24 records the rules that keep them from
  forcing a redesign.
- **M4.5 publication availability.** *(Superseded: the followers profile is
  now always publishable, §19.13.)* During M4.5, `public` is the only audience
  available for a new publication or replacement. The `followers` (`abonnés`)
  profile remains stored for the future restricted-federation gate, but is shown
  as `Unavailable` with text and icon, is read-only, and is disabled in
  selectors. `Not published` is the absence of a publication, not a profile.
  The UI must not convert or delete an unexpected active followers-only
  publication; that is a preflight failure.
- **Marketing surfaces.** There are none.

### 1.3 Relationship to the milestones

`[devdoc:tracking-depth]` and `[devdoc:roadmap]` describe *which* screens are
built and *when*. This document describes *what they are*. A milestone may
narrow the design (ship fewer screens); it may not contradict it (ship a
different pattern).

New UI work references this document rather than restating it. When a durable
decision here changes, this file is updated in the same patch as the code.

---

## 2. Product posture

**Personal-first, multi-user-safe.**

Allure is designed for the person whose data it holds. The default reader of
every screen is the owner, looking at their own training. That is the audience
the information architecture, the density and the defaults serve.

But no screen may assume it is the only account. Three consequences bind every
design decision:

1. **The owner boundary is visible, not implicit.** Any surface that shows
   owner-only data (raw geometry, private notes, the original file, unpublished
   workouts, records, equipment) states whose data it is. A second user
   appearing on an instance must never make a screen ambiguous.
2. **Non-owner rendering is a first-class state, not a degraded one.** A public
   workout page seen by a stranger is a designed screen with its own empty
   states — not the owner page with holes in it. It renders exactly the fields
   the publishing profile permits, and says nothing about what was withheld.
3. **Nothing is designed around a populated instance.** A brand-new
   single-account instance is the normal case. Every list has a designed empty
   state (§11), and no screen is meaningless without other people in it.

Social density — followers, discovery, a people directory — is deliberately
absent until M5. Their absence is not a hole to be papered over; the local
product is complete on its own.

---

## 3. Voice and tone

### 3.1 The register

Allure speaks like a knowledgeable friend who respects your time: direct,
concrete, a little wry. Closer to a good independent shop than to a device
manual. Short sentences. Active voice. Real verbs. No corporate hedging, no
exclamation-mark enthusiasm, no fake congratulation.

Personality lives in **word choice and rhythm**, never in volume.

| Do | Don't |
|---|---|
| "Nothing here yet. Import a GPX and this fills up fast." | "No workouts found. Please import a workout to continue." |
| "New record. That's your fastest 10 km." | "Congratulations!!! You have achieved a new personal record!" |
| "That file didn't parse. It looks like a TCX, not a GPX." | "An error occurred during file processing." |
| "37 workouts. 412 km. Not bad for a month." | "Monthly Summary Statistics Overview" |

### 3.2 The hard boundary

**The playful register stops at anything that can hurt someone.**

Copy about publishing, privacy zones, deletion, leaderboard anonymity, account
security and data loss is plain, factual and completely humourless. It states
what happens, what cannot be undone, and what the user can do about it. A joke
next to "remote servers may already hold your home address" reads as not taking
the risk seriously, and undermines the warning it decorates.

| Register | Applies to |
|---|---|
| **Playful** | onboarding, empty states, import success, records and personal bests, statistics headings, the styleguide, the 404 page |
| **Neutral** | all form labels, table headers, metric names, navigation, settings descriptions, the 500 page |
| **Sober** | publishing and publication preview, privacy zones, leaderboard opt-out consent and aliases, every destructive confirmation, session revocation, the 410 page |

Examples of the sober register are fixed in §19 and must be used verbatim.

### 3.3 Gamification

Limited to **copy and micro-celebration**:

- one rule for every place (§10.4): **the shape says who you measure
  against, the colour says the place**. The **trophy** is a personal place,
  you against yourself — gold for the record, silver and bronze for the
  second and third best time. The **laurel wreath** before a numeral is a
  leaderboard place, you against others — gold, silver and bronze for the top
  three, the bare numeral after. The two shapes never swap meanings;
- a record badge on the workout that set it, published only when the profile's
  `records` setting is on; the personal-best (`RP`) pill on the winning effort
  of a segment;
- the second and third best time (silver and bronze trophies) on best efforts
  and on one's own segment efforts — owner-only, never in a snapshot, a Note,
  the feed, a profile or a received note;
- a single, quiet celebration moment when a workout import produces a new
  record — a highlighted card and a sentence, nothing more (not implemented,
  §25).

Explicitly out of scope: points, levels, XP, streak counters, goal tracking,
badges collections, leaderboard-driven notifications, and any mechanic that
creates pressure to train. None of them have a dataset in M3, and none of them
survive the "would this still be kind on a bad week?" test.

Celebration never animates beyond §16's limits and never blocks interaction.

### 3.4 French address form

French copy uses **vouvoiement** (`vous`), consistently, everywhere.

This is deliberate and it is a whole-corpus decision. Every existing French
string uses it ("Vos activités, votre serveur, votre fédération"), a federated
instance may be read by strangers, and mixing registers within one interface is
worse than either choice. Personality in French comes from rhythm and concrete
nouns, not from `tu`.

Switching to tutoiement is possible but is a single atomic rewrite of both
locale files, never a gradual drift.

### 3.4b German, Spanish and Dutch address forms

German, Spanish and Dutch copy uses the **informal** form — `du`, `tú`,
`je`/`jij` — consistently, everywhere, the register these languages' sport
applications already use; the formal `Sie`, `usted` and `u` read as stiff
there. It is a whole-corpus decision per language, as for French: switching is
a single atomic rewrite of that locale file and its help pages.

German capitalises `du`/`dein` only where the sentence does; Spanish keeps the
`tú` verb forms and never mixes `vosotros`; Dutch writes `je`/`jouw`, `jij`
only for emphasis.

### 3.5 Copy mechanics

- **Sentence case** for every heading, label, button and menu item, in every
  language. Never Title Case. German keeps its noun capitals.
- **No terminal period** on labels, buttons, table headers or single-sentence
  empty-state headings. Full sentences in body copy and warnings take periods.
- **Numbers before nouns**: "12 activités", not "activités (12)".
- **Numbers follow the locale.** French prints a decimal comma and a narrow
  no-break space between thousands (« 345,3 km », « 4 381 m », « 12,5 % »);
  English prints a decimal point and comma thousands ("345.3 km", "4,381 m");
  German, Spanish and Dutch print a decimal comma and point thousands
  ("345,3 km", "4.381 m").
  Server output goes through `format_decimal` and the unit formatters built on
  it (`number.format` in both locale files); browser output goes through
  `Intl.NumberFormat` on the page's `lang` (`lib/number_format.js`). Never
  interpolate a raw Float into copy. Machine values — GPX, JSON payloads,
  coordinates in form fields — keep the decimal point.
- **Never leak internals.** No user-facing string contains "ActivityPub",
  "Solid Queue", "ShortUUID", "jsonb", "inbox", "actor", "serializer", "HTTP
  signature" or an exception class. §24 defines the plain-language equivalents.
- **Errors say what happened and what to do next**, in that order, in one or two
  sentences.
- Every user-visible string exists in **every** locale file —
  `config/locales/{fr,en,de,es,nl}.yml` — in the same patch. Missing
  translations raise in development and test; that is a feature, not an
  obstacle. `spec/i18n/locale_completeness_spec.rb` holds every locale to the
  same keys, interpolation variables and help pages.

---

## 4. Glossary

The terminology contract. These words mean exactly one thing each, in code, in
the UI and in every language (§4.1 for German, Spanish and Dutch). Deviating creates a support burden that no amount
of good visual design repairs.

| Concept | English UI | French UI | Notes |
|---|---|---|---|
| Recorded training session | workout | activité | Never "activity" in English (collides with ActivityPub); never "entraînement". |
| The immutable shared copy | publication | publication | Never "share" as a noun. |
| The reverse-chronological stream of publications | feed | publications | The `/feed` surface, and the French label. Never "fil" alone. |
| The act of creating one | publish | publier | |
| Removing it | delete the publication | supprimer la publication | Never "unpublish": the object is withdrawn, not hidden. |
| Publishing again after deletion | replace the publication | remplacer la publication | Creates a **new** publication identity. Wording contract; the `republished` flash key keeps its historic wording. |
| The reusable sharing policy | publishing profile | profil de publication | Never "privacy setting". |
| Who can see a publication | audience | audience | Values: public / abonnés. |
| A workout with no publication | not published | non publiée | Never "private" — there is no private profile. |
| Home-location masking zone | privacy zone | zone de confidentialité | |
| Start/finish trimming | mask the start / mask the finish | masquer le départ / masquer l'arrivée | Two independent controls. |
| One contiguous GPX `<trkseg>` | recording segment | tronçon d'enregistrement | The M1 `TrackSegment`. Never plain "segment" in the UI. |
| Reusable leaderboarded course | segment | segment | The `Segment` model, `kind: segment`. |
| A saved course to follow | route | itinéraire | The `Segment` model, `kind: route`. |
| A course returning to its start | loop | boucle | The `Segment` model, `kind: loop`. |
| One traversal of a segment | effort | effort | Never "attempt", never "passage". |
| Best effort of a person on a segment | personal best | record | Named « Record » / "Record" like every personal first place; abbreviated **RP** / **PB** only inside the segment pill. |
| Second or third personal place | second / third best time | 2e / 3e meilleur temps | Owner-only; `2e` / `2nd`, `3e` / `3rd` inside a pill. |
| A place among athletes | rank | rang | `Rang 3` / "Rank 3"; the list is the leaderboard (classement). |
| File-recorded lap | lap | tour | From the FIT/TCX file. |
| Derived smart lap | detected lap | tour détecté | Detected from loops, route repeats, pauses, or climbs. Owner-only, never published. |
| Detected climb | climb | montée | A sustained ascent found in the elevation profile. Owner-only, never published. |
| Detected descent | descent | descente | A sustained descent found in the elevation profile. Owner-only, never published. |
| Detected stop | stop | arrêt | A near-zero-speed run inside a recording segment. Owner-only. |
| Detected effort block | interval | effort | A sustained fast or powerful block; split stays "intervalle" for distance splits. Owner-only. |
| Computed distance interval | split | split | Computed on demand, never stored. |
| One of the 8 record types | record | record | Always qualified by sport. |
| Best time over a standard distance | best effort | meilleur effort | Distances are canonical labels (`5 km`, `1/2 mile`), never converted. |
| Gear | equipment | équipement | |
| Device or software that recorded the file | device | appareil | Named by the imported file; owner-only until a publishing profile shares it. |
| Ranked list of efforts | leaderboard | classement | |
| Self-declared board category | leaderboard category | catégorie de classement | Values: Women / Men / Not specified — Femmes / Hommes / Non précisé. Never "gender" or "sexe" in the UI. |
| Appreciation gesture on a publication | reaction | réaction | Bière, boisson énergisante, café, or j'aime (§10.17); the neutral j'aime is also what an external Like means. Never "like" as a noun in the UI. |
| Written words under a publication | comment | commentaire | The thread is the workout's (§10.20). The action is « Commenter » / "Comment", never « Publier », which belongs to publications. |
| A comment answering a top-level comment | reply | réponse | One level only. |
| The author taking their comment back | delete | supprimer | |
| The workout's owner taking someone's comment out | remove | retirer | The comment's author still sees it, marked « Retiré par le propriétaire ». |
| Confirmed shared activity | participation | participation | A workout linked to another account after mutual confirmation; either a crédit or a lien. Never "tag". |
| Participation where the workout counts for the participant | credit | crédit | The participant has no recording; the owner's workout is credited to them. Never "copie". |
| Participation where both accounts recorded | link | lien | The two workouts cross-link and nothing is counted twice. |
| Badge naming a workout's participant | Avec @X | Avec @X | The same words in both languages, never a protocol handle. |
| Pseudonymous leaderboard name | alias | alias | §19.5. |
| Someone the instance knows | account | compte | Never "user" in UI copy. |
| Distance/time/elevation values | metrics | mesures | |
| The uploaded file | original file | fichier d'origine | Never "source". |
| Bringing files in | import | importer | Never "upload" as a noun. |
| A second proof after the password | two-step verification | double authentification | `[devdoc:auth]`. Never "2FA" or "MFA" in UI copy. |
| Rotating six-digit codes | authenticator app | application d'authentification | The factor is the app, never "TOTP" in UI copy. |
| Device-held credential | passkey | clé d'accès | Also covers a hardware security key. Never "WebAuthn" in UI copy. |
| Single-use fallback code | recovery code | code de récupération | Ten per generation, shown once. |
| Google, Apple or an OpenID Connect service that signs the person in | identity provider | fournisseur d'identité | Buttons name the provider: « Continuer avec Google ». Never "OAuth", "OIDC" or "SSO" in UI copy. |
| Secret that lets a program use the API for the account | API token | jeton d'API | `[devdoc:api]`. Never "clé", "PAT" or "personal access token" in UI copy. |
| What a token is allowed to do | permission | permission | The `read`/`write`/… scopes; the UI names each in words (« Lire mes activités »), never the scope code alone. |
| A URL Allure notifies of account events | webhook | webhook | `[devdoc:api]`. Same word in both languages. |
| One signed notification sent to a webhook | delivery | envoi | Never "call" or « appel ». |

Discovering a new loop requires at least two complete same-direction tours,
including after an approach. Recognizing an active loop already owned by the
account requires only one complete same-direction traversal. The approach,
return and incomplete tours do not become laps. The existing settings Data and administration Jobs cards say
« Recalculer mes boucles » / "Recalculate my loops" and « Recalculer les
boucles » / "Recalculate loops". Their counts include positioned recordings
without a loop whose detection is out of date; confirmations explain that
publications do not change ([SEGMENTS.md](SEGMENTS.md)).

Sport names are the 38 seeded slugs, translated under `sports.<slug>`. Never
invent a display name in a view.

**"Effort" and "split" stay in their English form in French.** Both are already
the shipped French copy, and both are what French speakers meet in every other
sport-tracking application. A purer translation would be correct French and
wrong terminology: it would fight the user's existing vocabulary and require
rewriting working strings for no gain. "Tour" for lap and "itinéraire" for
route go the other way — those French words are the ones users already expect,
and they are shipped too.

### 4.1 German, Spanish and Dutch

The same contract for the three later locales. The English column of the
table above defines the concept; the notes there apply here too. A row's
"never" column names the near-synonym each language must avoid.

| English UI | German UI | Spanish UI | Dutch UI | Never |
|---|---|---|---|---|
| workout | Aktivität | actividad | activiteit | de « Workout », « Training »; es « entrenamiento »; nl « training » |
| publication | Veröffentlichung | publicación | publicatie | a noun for "share" (« Freigabe », « compartido », « gedeelde ») |
| feed | Feed | Publicaciones | Feed | es « muro » |
| publish | veröffentlichen | publicar | publiceren | |
| delete the publication | Veröffentlichung löschen | eliminar la publicación | publicatie verwijderen | "unpublish" (« zurückziehen », « despublicar », « depubliceren ») |
| replace the publication | Veröffentlichung ersetzen | reemplazar la publicación | publicatie vervangen | |
| publishing profile | Veröffentlichungsprofil | perfil de publicación | publicatieprofiel | "privacy setting" |
| audience (public / followers) | Publikum (Öffentlich / Follower) | audiencia (Pública / Seguidores) | publiek (Openbaar / Volgers) | « Sichtbarkeit », « visibilidad », « zichtbaarheid » for the audience |
| not published | nicht veröffentlicht | no publicada | niet gepubliceerd | "private" (« privat », « privada », « privé ») |
| privacy zone | Privatsphäre-Zone | zona de privacidad | privacyzone | |
| mask the start / the finish | Start ausblenden / Ziel ausblenden | ocultar la salida / ocultar la llegada | start verbergen / finish verbergen | |
| recording segment | Aufzeichnungsabschnitt | tramo de grabación | opnamedeel | plain "segment" |
| segment | Segment | segmento | segment | |
| route | Route | ruta | route | |
| loop | Rundkurs | circuito | lus | de « Runde » (that is a lap); es « vuelta » (that is a lap) |
| effort | Durchgang | esfuerzo | poging | de « Leistung » (that is power) |
| personal best (pill) | Rekord (**PB**) | récord (**RP**) | record (**PR**) | |
| second / third best time (pill) | zweitbeste / drittbeste Zeit (`2.` / `3.`) | segundo / tercer mejor tiempo (`2.º` / `3.º`) | op één na / op twee na beste tijd (`2e` / `3e`) | |
| rank / leaderboard | Rang / Bestenliste | puesto / clasificación | positie / klassement | |
| lap / detected lap | Runde / erkannte Runde | vuelta / vuelta detectada | ronde / gedetecteerde ronde | |
| climb / descent / stop | Anstieg / Abstieg / Stopp | subida / bajada / parada | klim / afdaling / stop | |
| interval (detected block) | Intervall | intervalo | interval | |
| split | Zwischenzeit | parcial | tussentijd | |
| record | Rekord | récord | record | |
| best effort | Bestzeit | mejor esfuerzo | beste prestatie | de « Bestleistung » |
| equipment | Ausrüstung | equipo | uitrusting | |
| device | Gerät | dispositivo | apparaat | |
| leaderboard category (Women / Men / Not specified) | Bestenlisten-Kategorie (Frauen / Männer / Keine Angabe) | categoría de clasificación (Mujeres / Hombres / Sin especificar) | klassementscategorie (Vrouwen / Mannen / Niet opgegeven) | « Geschlecht », « sexo », « geslacht » |
| reaction (beer, energy drink, coffee, like) | Reaktion (Bier, Energydrink, Kaffee, Gefällt mir) | reacción (cerveza, bebida energética, café, me gusta) | reactie (biertje, energiedrankje, koffie, vind ik leuk) | "like" as a noun |
| comment / to comment | Kommentar / kommentieren | comentario / comentar | opmerking / een opmerking plaatsen | nl « reactie » (that is a reaction); the publishing verb |
| reply | Antwort | respuesta | antwoord | |
| delete (author) / remove (owner) | löschen / entfernen | eliminar / retirar | verwijderen / weghalen | swapping the two verbs |
| « Retiré par le propriétaire » | Vom Eigentümer entfernt | Retirado por el propietario | Weggehaald door de eigenaar | |
| participation / credit / link | Teilnahme / Gutschrift / Verknüpfung | participación / crédito / vínculo | deelname / toekenning / koppeling | "tag", "copy" |
| Avec @X | Avec @X | Avec @X | Avec @X | The same words in every language (§4). |
| alias | Alias | alias | alias | |
| account | Konto | cuenta | account | « Benutzer », « usuario », « gebruiker » |
| follower / to follow | Follower / folgen | seguidor / seguir | volger / volgen | |
| instance | Instanz | instancia | instantie | |
| metrics | Messwerte | métricas | meetwaarden | |
| original file | Originaldatei | archivo original | origineel bestand | « Quelle », « fuente », « bron » |
| import | importieren / Import | importar / importación | importeren / import | « hochladen », « subir », « uploaden » as the action's name |
| two-step verification | Bestätigung in zwei Schritten | verificación en dos pasos | verificatie in twee stappen | "2FA", "MFA" |
| authenticator app | Authenticator-App | aplicación de autenticación | authenticator-app | "TOTP" |
| passkey | Passkey | llave de acceso | toegangssleutel | "WebAuthn" |
| recovery code | Wiederherstellungscode | código de recuperación | herstelcode | |
| identity provider (« Continuer avec Google ») | Identitätsanbieter (Weiter mit Google) | proveedor de identidad (Continuar con Google) | identiteitsprovider (Doorgaan met Google) | "OAuth", "OIDC", "SSO" |
| API token | API-Token | token de API | API-token | « Schlüssel », « clave », « sleutel », "PAT" |
| permission | Berechtigung | permiso | machtiging | the scope code alone |
| webhook / delivery | Webhook / Zustellung | webhook / envío | webhook / bezorging | "call" |
| course (a segment, route or loop in general) | Strecke | recorrido | parcours | the §4 kind words when the kind is unknown |
| commute (flag and badge) | Arbeitsweg | trayecto diario | woon-werkrit | « Pendelfahrt », « desplazamiento al trabajo », « woon-werkverkeer » |
| outing (an occasion several people shared) | Tour | salida | tocht | « Ausfahrt » (cycling only) |
| source activity (of a participation) | Ausgangsaktivität | actividad de origen | oorspronkelijke activiteit | « Quellaktivität » |
| the instance's operator | Betreiber | operador | beheerder | |
| weather | Wetter | meteorología | weer | es « tiempo » (that is time) |
| username | Benutzername | nombre de usuario | gebruikersnaam | The one compound where « Benutzer », « usuario », « gebruiker » stay. |
| comment thread | Diskussion | conversación | discussie | |

The §3.5 internals list applies unchanged: no German, Spanish or Dutch string
names a protocol or an implementation detail either.

---

## 5. Design tokens

### 5.1 Principles

Allure styles **Tabler**, it does not replace it. Three rules:

1. **Semantic before literal.** A component references a semantic token
   (`--allure-surface-raised`), never a hex value and never a raw Bootstrap
   variable. Hardcoded colours in ERB, SCSS or JS are a defect.
2. **Tabler variables are the substrate.** Every Allure token resolves to a
   Bootstrap/Tabler custom property so dark mode, contrast and future Tabler
   upgrades are inherited, not reimplemented.
3. **`_brand.scss` stays small.** It sets brand values before Tabler loads.
   Component-level overrides live in `styles/components/`, so Tabler stays
   upgradable. This is already the file's stated contract.

### 5.2 Brand

| Token | Value | Meaning |
|---|---|---|
| `$primary` | `#c5426c` | The Allure rose. Route tracks and metric shades derive from it. |
| `$border-radius` | `6px` | Tabler's default; no override. |
| Typography | system stack | `$font-google: false`, `$font-local: false`. No third-party font request from a self-hosted instance, ever. |
| Icon font | `@tabler/icons-webfont` 3.49.0, woff2 only, served from `/fonts/tabler` | |
| Brand mark | inline SVG partial `shared/_brand_mark`, mirrored in `public/icon.svg` | The Allure monogram: an A holding a shield and two orbital nodes (§23). |
| Wordmark | shared partial `shared/_brand_wordmark` | `allure` in lowercase with a rose full stop: `allure.` The name remains **Allure** in prose, accessible names, page titles and installable identity. |

The wordmark shares the product website's typography: the existing system font,
`1.8rem`, weight `700`, `-0.03em` tracking and a unit line-height. Its letters use
`--allure-text`; only the full stop uses the primary, so both light and dark
themes retain their own ink. It is text, not an image or a downloaded font.
`shared/_brand_wordmark` is the only rendering of this graphical spelling; it
lowercases the existing `app.name` translation and hides the decorative spelling
and punctuation from assistive technology. The containing product-home link
keeps the accessible name **Allure**; the administration link keeps its console
name.

The browser product topbar pairs the existing monogram with this wordmark from
`xl` (1200px), keeping the monogram alone below that width so navigation and
actions retain their space. The denser administration topbar keeps the monogram
alone below 1800px, including where its nine-destination menu expands. The auth shell always shows the pair,
including on phones. The companion's existing native-chrome exclusions do not
change. Favicons, installable icons and the iOS app icon remain the monogram;
mailers and ordinary mentions of the product remain unchanged.

**The primary is restrained.** It marks *the primary action and the product's
own identity* — nothing else. It is not a decorative wash. Specifically:

- primary buttons, active navigation state, focus rings, brand marks: primary;
- data (charts, map lines): **ink or primary per §15.1**, never a decorative
  hue. Sport identity is a neutral icon tile, never a colour (§6);
- status (success, warning, danger, info): Tabler's semantic colours, never
  primary.

If a page looks uniformly primary, the design is wrong.

### 5.3 Semantic surface tokens

Declared once in `_brand.scss` as CSS custom properties resolving to Tabler
variables, so `data-bs-theme` swaps them for free.

| Token | Resolves to | Use |
|---|---|---|
| `--allure-surface` | `--tblr-body-bg` | Page background. |
| `--allure-surface-raised` | `--tblr-bg-surface` | Cards, dropdowns, modals, toasts. |
| `--allure-surface-sunken` | `--tblr-bg-surface-secondary` | Table headers, well/inset areas, code blocks. |
| `--allure-border` | `--tblr-border-color` | Every divider and card edge. |
| `--allure-text` | `--tblr-body-color` | Body text and metric values. |
| `--allure-text-muted` | `--tblr-secondary` | Labels, captions, units, timestamps. |
| `--allure-text-inverted-muted` | 78 % of `--tblr-text-inverted` | Muted lines **on the inverted surface**: tooltips and the hub's selection callouts (§15.1). The theme's own secondary grey is too weak there. |
| `--allure-focus` | `--tblr-primary` | Focus ring; never removed, never restyled to invisibility. |

Tabler 1.6's neutral gray scale is the base: `data-bs-theme-base` stays unset,
and the 1.5 blue-tinted `gray` base is not restored. Contrast (§18.1) is
validated against this scale.

The place colours (`--allure-medal-gold`, `--allure-medal-silver`,
`--allure-medal-bronze`) are the one component-local literal family: they mark
places only — the personal trophy and the leaderboard laurel alike — never a
surface or a status. Gold is the first place of either shape, silver the
second, bronze the third (§10.4). There is no numeral inside a medal, so there
is no ink token.

### 5.4 Status colours

| Meaning | Token | Used for |
|---|---|---|
| success | `--tblr-success` | Import succeeded, published, record set, active zone. |
| warning | `--tblr-warning` | Publication readiness warnings, drifted equipment totals, partial split. |
| danger | `--tblr-danger` | Destructive actions, failed import, validation errors. |
| info | `--tblr-info` | Explanatory panels, "how this works" callouts. |
| muted | `--allure-text-muted` | Not published, inactive, duplicate, cancelled. |

**"Not published" is muted, never danger.** An unpublished workout is the normal
resting state, not a problem.

### 5.5 Elevation and borders

Borders carry structure; shadows carry stacking.

| Layer | Treatment |
|---|---|
| Card, table, panel | 1px `--allure-border`, radius 5px, **no shadow** |
| Dropdown, popover, tooltip | Tabler's default shadow |
| Modal, off-canvas, toast | Tabler's elevated shadow + backdrop where applicable |
| Map, chart canvas | inside a card; the canvas itself carries no border |

A shadow on a resting card is a defect.

### 5.6 Spacing and density

Tabler's 4px-based scale. Vertical rhythm:

- page header → first card: `mb-3`;
- card → card: `row-deck row-cards` gutters, unchanged;
- inside a card: `card-header` / `card-body` / `card-footer`, no ad-hoc padding;
- label → value inside a metric tile: `0`, the label is a `small` above the
  value.

Density is **comfortable on cards, compact on data**:

| Surface | Density |
|---|---|
| Cards, forms, settings | Tabler default |
| Filter bars | Compact controls (`form-*-sm`, `btn-sm`), 44px hit area on coarse pointers (§10.6) |
| Data tables (laps, splits, efforts, leaderboards, records, equipment, import entries) | `table-sm table-vcenter` |
| Sidebar, topbar | Tabler default; no condensed layout variant |

Tabler's condensed layout variants are not used. There is no density preference
setting.

---

## 6. Sport identity system

A sport must be identifiable at a glance in a card, a table row, a chart legend
and a page header — in both themes, at 24px, and for a colour-blind reader.

### 6.1 The two-part rule

**Icon = sport. Text = certainty.**

- **Icon** comes from a per-sport map (§6.3), rendered on a brand-tinted tile
  (§6.5). It is **globally unique**: no two sports share a glyph, because there
  is no colour left to separate them.
- **Text** is the translated sport name. It is the only identifier that is ever
  authoritative.

Sport has **no per-sport colour**. Every tile carries the same brand-primary
tint (surface and glyph), so it reads in both themes and never claims a
per-sport hue. Colour is never the only encoding (§18.6), and neither is the
icon: a sport mark without its name is not a valid component, except the dense
`xs` tile and the workout-card tile, which carry the name in their accessible
label and tooltip.

### 6.2 Icon families

`Sport#colour_group` keeps its historic column name but is an **icon family**,
one of six values: `run`, `ride`, `hike`, `swim`, `ski`, `other`. A family only
supplies the fallback partial for a slug the local catalog does not know (a
remote sport); every seeded sport has its own partial.

| Family | Fallback partial | Sports |
|---|---|---|
| `run` | `families/run` | running, running_virtual, walking, trail, tennis, padel |
| `ride` | `families/ride` | cycling ×6, mountain biking ×2, halfbike, inline skating |
| `hike` | `families/hike` | hiking, snowshoes, mountaineering |
| `swim` | `families/swim` | pool and open-water swimming, swimrun, rowing ×2, kayaking ×2, canoeing ×2, windsurfing, SUP |
| `ski` | `families/ski` | alpine/touring/cross-country ski, snowboarding, ice skating |
| `other` | `families/other` | paragliding |

The six values live only in `SportPalette::GROUPS`, the database check
constraint and the seeds. No colour is attached to them anywhere.

### 6.3 Per-sport icons

Every seeded sport ships its own inline SVG partial under
`app/views/sports/icons/`; `SportPalette::PARTIALS` is the only mapping. The
icon is globally distinct across all 38 sports, and no sport is ever drawn from
the icon font.

**Distinctness rule:** icons must be distinct **across the whole catalog**.
Cross-family reuse is no longer permitted, because the icon is the only
at-a-glance identifier beside the name.

| Family | Slug | Reads as |
|---|---|---|
| run | `running` | running shoe |
| run | `running_virtual` | treadmill |
| run | `trail` | running shoe + lugged sole |
| run | `walking` | shoe |
| run | `tennis_outdoor` | tennis ball |
| run | `padel_outdoor` | tennis ball + P |
| ride | `cycling` | bicycle |
| ride | `cycling_road` | bike + drop handlebar |
| ride | `cycling_gravel` | bike + terrain |
| ride | `cycling_electric` | bike + bolt |
| ride | `cycling_trekking` | bike + pannier |
| ride | `cycling_virtual` | bike + screen |
| ride | `mountain_biking` | peaks + bike |
| ride | `mountain_biking_electric` | peaks + bike + bolt |
| ride | `halfbike` | kick-scooter |
| ride | `inline_skating` | roller skate |
| hike | `hiking` | laced hiking boot |
| hike | `mountaineering` | flagged summit |
| hike | `snowshoes` | snowshoe |
| ski | `skiing_alpine` | skier on a slope |
| ski | `skiing_touring` | skier climbing a slope |
| ski | `skiing_cross_country` | skier + poles |
| ski | `snowboarding` | snowboarder |
| ski | `ice_skating` | skate boot |
| swim | `pool_swimming` | pool |
| swim | `open_water_swimming` | swimmer + waves |
| swim | `swimrun` | swimmer + waves |
| swim | `rowing` | two crossed oars |
| swim | `rowing_virtual` | indoor rowing machine |
| swim | `kayaking` | kayaker, top view |
| swim | `kayaking_whitewater` | kayaker + waves |
| swim | `canoeing` | canoe + paddler |
| swim | `canoeing_whitewater` | canoe + waves |
| swim | `standup_paddleboarding` | paddler on a board |
| swim | `windsurfing` | board + sail |
| other | `paragliding` | wing + pilot |
| other | `strength_training` | barbell |
| other | `fitness` | heartbeat |

The cycling variants stay distinguishable by a small attribute — bolt for
electric, screen for virtual, terrain for gravel, peaks for the mountain bike
with a bolt over them for its electric form, pannier for trekking, a drop
handlebar for road — on the same bike base.

### 6.4 Authoring rules

Sport icons are inline SVG partials, never a webfont extension. Rules —
non-negotiable, so the set stays consistent and reads in both themes:

- the 1000×1000 viewBox with `stroke-width="60"` — the whole set draws at one
  weight; a Tabler-derived icon keeps its original 24×24 geometry scaled by
  1000/24, and its per-path weight overrides scale with the stroke (Tabler's
  2 → 60, padel's 1.5 → 45);
- `stroke="currentColor"`, `stroke-linecap="round"`,
  `stroke-linejoin="round"`, and `fill="none"`, except the filled third-party
  silhouettes (Font Awesome, SVG Repo), which carry one `currentColor` fill
  and no stroke;
- `width="24" height="24"` — the intrinsic size of the one render without a
  sizing wrapper (the hub's segment table); the tile, the filter chips and the
  calendar tooltip scale the SVG to their own box;
- no embedded colour, no `style` attribute, no `id` (they are inlined more than
  once per page) — a shape the drawing would cut with a mask is drawn as its
  visible pieces, since a mask needs an `id`;
- `aria-hidden="true"` — the accessible name always comes from adjacent text or
  the tile's `aria-label`.

The tile scales the SVG to its icon box
(`.sport-tile svg { width: 1em; height: 1em; }`); outside a tile (the calendar
tooltip), `.sport-icon` scales it to the surrounding text.

Import sources are the one place a third-party mark appears: a source with a
partial under `app/views/import_sources/icons/` (Garmin's delta from Simple
Icons, EXR's mark from its own favicon, iGPSPORT's pin traced from its app
icon) shows it, filled in
`currentColor`, monochrome, beside its name on the service's page, its row in
the connected-services hub and the import tabs (`import_source_icon_tag`,
`.import-source-icon`); any other source
keeps its Tabler glyph. A mark identifies the service and never suggests a
partnership, so it never appears alone, in brand colour, or as a badge.

Tabler's icons are MIT-licensed and may be adapted as the starting point: the
family fallbacks and several sports derive from them. No commercial icon asset
ever enters the repository; the sports set is original work inspired by the
recognizable-equipment direction, never a copy of a commercial pictogram.

### 6.5 Sport tile anatomy

```
┌──────────────────────────────┐
│ ▢  Course à pied             │   ▢ = brand-primary tint (10% on the sunken
│    ↑ ti-run, primary ink     │       surface, 25% ring), per-sport glyph
└──────────────────────────────┘
```

The tile is Tabler's avatar component in its **`avatar-square`** shape:
`avatar avatar-square avatar-{size}`, so dimensions, corner radius, and glyph
token all come from Tabler (`--avatar-size`, `--avatar-icon-size`). The
`avatar-square` corner is the interface's rounded square; only people get the
default circle (§9.5). `sport-tile` adds nothing but the brand tint.

One component, four sizes, always beside the translated name except the `xs`
tile in dense group headings and the workout-card tile:

| Size | Tabler class | Tile | Glyph | Radius | Used in |
|---|---|---|---|---|---|
| `lg` | `avatar-lg` | 48px | 32px | 6px | full-width page headers (segment detail) |
| `md` | `avatar-md` | 40px | 24px | 6px | workout detail header, workout cards, feed items, styleguide wall |
| `sm` | `avatar-sm` | 32px | 24px | 6px | segment detail pretitles, filter chips |
| `xs` | `avatar-xs` | 20px | 12px | 2px | table rows, records/stats/leaderboard group headings |

The glyph box is Tabler's `--avatar-icon-size`, which the inline sport SVGs
fill (`.sport-tile svg { width: 1em; height: 1em; }`).

A `xs` tile is never the sole content of a table's identifying column: the
sport name is always adjacent. On a workout card the printed name is gone, so
the tile itself carries the accessible name and a tooltip; on a linked card it
is also a link, stacked above the card's stretched link so tapping the icon
opens the workout like the rest of the card.

---

## 7. Layout and chrome

### 7.1 Desktop (≥ 992px)

Tabler `layout-horizontal` with `data-bs-layout="fluid"`:

```
┌────────────────────────────────────────────────────────────┐
│ brand  MAIN / EXPLORE navigation        import bell theme me│
├────────────────────────────────────────────────────────────┤
│ page header (pretitle / title / actions)                    │
├────────────────────────────────────────────────────────────┤
│ .page-body > .container-xl, fluid width                     │
│ flash                                                      │
│ content                                                    │
├────────────────────────────────────────────────────────────┤
│ footer                                                     │
└────────────────────────────────────────────────────────────┘
```

The primary navigation is a single horizontal bar carrying the Main and Explore
items. Settings is reached from the account menu (and from the phone bottom
bar), never from a topbar dropdown. `data-bs-layout="fluid"` removes the maximum
width from the existing containers while retaining Tabler's page gutters.

### 7.2 Tablet (768–991px)

The horizontal navigation collapses below the topbar. It is opened from the
topbar hamburger and closes when a destination is selected. The topbar keeps
brand, theme toggle and account menu.

### 7.3 Phone (< 768px)

Collapsed primary navigation plus a persistent bottom bar carrying the five
most-used destinations. The bottom bar is thumb-reachable and matches every
fitness application a user has already learned.

```
┌──────────────────────────────┐
│ ☰  (A)          ＋  ◐  (M)  │  topbar (monogram; icon-only ＋ import action, §8.1)
├──────────────────────────────┤
│                              │
│  page header                 │
│  content, single column      │
│                              │
├──────────────────────────────┤
│  🌍     👤     🏃     🏁  👥  │  bottom bar
│Publications Moi Activ. Segments Pers.│
└──────────────────────────────┘
```

Bottom-bar rules:

- exactly five items, never more: Publications / Moi / Activités / Segments /
  Personnes. Settings stays reachable from the account menu; it is labelled
  Paramètres everywhere it appears (entry, its sub-navigation, account menu):
  one word per concept across the shipped corpus. Import is **not** a bar item:
  it is an infrequent file-based action, not a destination, and Segments fixes
  the shared-leaderboard discoverability gap. Import is a persistent topbar `+ Importer` action
  (signed in only) plus the header primary on `/workouts` and `/me` plus the
  empty-state CTAs — reachable in one tap from every main surface without the
  bar. Below `lg` (the breakpoint where the primary navigation collapses)
  the topbar action shrinks to an icon-only `+` tile (36×36, the `btn-icon`
  size, with a 44×44 touch target) carrying `aria-label` and a `title`
  tooltip, so it never crowds the brand, bell, theme toggle and account menu;
  the `Importer` label returns on desktop. This is the one
  icon-only button allowed outside table rows and card headers (§10.3). The
  feed keeps only the Public switch in its header: its empty state carries the
  import CTA instead;
- labels are always shown, never icon-only;
- it is hidden for signed-out visitors, who get a single "sign in" topbar
  action;
- it hides on scroll-down and returns on scroll-up **only** if that can be done
  without motion for `prefers-reduced-motion` users; otherwise it stays fixed;
- it is `role="navigation"` with an `aria-label`, and the active item carries
  `aria-current="page"`;
- content reserves bottom padding equal to its height so nothing is ever
  occluded — including the last row of a table and the sticky form footer;
- the feedback action is never a bar item: on phone and tablet it retracts to
  an icon-only tab on the right edge, above the bar, so it cannot cover a
  destination; the labelled pill returns on desktop. At every size it slides
  off the right edge while the reader scrolls down and returns on the way up,
  so it never sits on the content being read; under `prefers-reduced-motion`
  it stays put.

### 7.4 Page header

One pattern, everywhere:

```
pretitle   ← context: section name, sport badge, audience badge, breadcrumb
title      ← the page's subject, h1, exactly one per page
actions    ← right-aligned; at most one primary, the rest secondary/ghost
```

Rules:

- every page sets `content_for :title` and `content_for :page_header`;
- exactly one `<h1>` per page, and it is the page-header title;
- header actions use `btn-sm`;
- on phones, actions collapse into a single overflow menu when there are more
  than two, keeping the primary action visible outside the menu;
- destructive actions never appear in the header's primary slot; they live in
  the overflow menu or in a dedicated danger zone at the bottom of the page.

The workout detail header (§20.3) is the documented variation: the sport tile
leads the `h1` instead of a pretitle, another account's workout carries its
author line under the title, the sport and date follow under it, and the
owner-only place line and the badge line close the block at the left margin.

### 7.5 Footer

Tagline plus instance domain, and — when the operator configures it — one
"Hosted by {name}" line, linked to the host's public page when one is set. It
is the only place the instance identity appears on every page, which matters on
a federated network where a user may not remember which instance they are on.
The host line never appears when unset: no invented operator identity. The same
configured name and description are exposed in NodeInfo metadata for remote
administrators.

The running version (`Allure 0.2.3`) sits at the end of the meta line of the
members' chrome. For a signed-in account on a release with curated notes it is
a button opening the release notes dialog (§10.9); otherwise it is plain text.
The auth and error layouts keep their own minimal chrome and carry no footer.

### 7.6 Administration view

`/admin` is a second chrome for the single instance operator
(`INSTANCE_OPERATOR_USERNAME`); `[devdoc:admin]` is the binding contract. It is
not part of the product information architecture: it has no bottom bar, no
feedback widget, no import action, and its menu never appears in the product
topbar.

- Entry: the account dropdown's « Administration » item, rendered only when
  `instance_operator?` is true. Exit: « Retour à Allure » in the admin topbar,
  which lands on `/me`.
- Layout `admin`: the same Tabler shell, theme, Vite entrypoint, skip link,
  flash, toasts, confirm modal, release-notes dialog, and footer as the
  product; the primary navigation is replaced by the console menu.
- Menu: a horizontal bar under the brand, declared as the `position: :admin`
  section of `config/navigation.rb`, collapsing behind the hamburger below
  `xxl` (nine destinations plus the exit action do not fit a 1280px topbar).
  Every leaf is policy-gated; a leaf whose route does not exist yet is
  skipped.
- The brand carries an « Administration » badge; each page uses the
  « Administration » pretitle and one `<h1>` like every other page.
- A non-operator requesting any console route receives the standard 404, and a
  member's HTML never contains a console link.
- Panels follow the existing vocabulary: metric tiles (§10.2) for the
  dashboard, DESIGN §12 tables for lists, the shared confirmation dialog
  (§10.10) for destructive operations, and cards for health summaries. The
  live jobs panel updates through a Turbo Frame poll; it has no bespoke visual
  language.

### 7.7 iOS companion

The iOS companion in the separate `allure-ios` repository uses Hotwire Native
to display the same Rails pages, forms, maps and charts. The native shell adds
back navigation, the native bar, the tab bar, and bridges the signed-in topbar
into native controls. Rails owns the navigation entries, labels, account actions
and privacy copy; the native bars derive from the shared navigation contract,
and a client that does not advertise a bridge keeps the web counterpart.

- `hotwire_native_app?` recognises the companion from the `Hotwire Native`
  marker in its user agent and adds `native-app` to `<body>`. It trims
  duplicated chrome only; it never changes what a page may show. The `/me`
  header keeps its avatar there too: it leads the title like every page's
  tile (§8.4). In the companion the topbar drops the brand
  and the theme toggle (Appearance settings keep the choice), keeping the
  menu toggle for destinations outside the bottom bar, then import, bell and
  account menu. The footer is not rendered, and the auth layout drops its
  theme toggle.
- Signed-in clients advertising `topbar` in `bridge-components: [...]` receive
  a hidden topbar with the `bridge--topbar` controller and a Rails-generated
  payload. The native bar renders ☰ on the left for the navigation sections,
  and Import (+) and the account button on the right. The account button shows
  the account's avatar, which the controller draws from the hidden account
  toggle as a PNG and sends in an `avatar` message (generated art stays inline
  SVG on the page, §9.2); `navigation.account_menu` is its accessible label.
  Its menu, under the account name, starts with Notifications, then Public
  profile, Settings, Connected services when the account has an area to open
  (§8.6), Help, About, optional Administration, Server and Sign
  out. Replies
  identify hidden web links/buttons to click, preserving Turbo navigation and
  the Rails sign-out form. Older clients retain the web topbar. The hidden
  badge poll forwards unread state and a localized accessible count: a red dot
  on the account button and the count in the Notifications entry, which opens
  `/notifications` rather than the web dropdown.
- A companion advertising `tabs` receives the phone bottom bar hidden, with
  the payload its native tab bar draws: the same five labelled destinations
  (§7.3), each keeping its own history and loading its own `path`. An older
  companion keeps the web bar. The native bar is the companion's whole bottom
  safe area (the floating island plus the home indicator), so the page
  reserves `env(safe-area-inset-bottom)` at its end: form footers, pagination
  and card actions clear the bar while content still scrolls behind it.
- The companion's own Appearance setting (Automatic / Light / Dark) governs
  its whole app, native chrome and pages alike. The resolved theme arrives in
  `allure_companion_theme`, a cookie read only from `hotwire_native_app?`
  requests, so Rails renders every page in it from the first paint; the
  account theme keeps governing browsers, and the companion therefore hides
  the theme card on `/settings/appearance`.
- The document title is the page name without the ` · Allure` suffix. The
  native bar names the current section instead (from the `tabs` payload) and
  falls back to that document title outside the five sections; the page keeps
  its web heading, pretitle and header rendering, and the web page spacing.
- The account menu carries `Serveur` / `Server`, linking to
  `/native/server`. The companion intercepts that same-origin path and opens
  its server chooser; Rails has no route for it and never renders the link
  outside the companion. The native bar keeps its own Server action on pages
  without a bridged topbar (authentication, Rails errors and older servers)
  and on the page-load error screen.
- The import page's iGPSPORT panel keeps its web controls, labels,
  selection, progress and journal in the companion; when the app registers
  the `igpsport` bridge component, the panel borrows the phone's Bluetooth
  through it (`[devdoc:import-sources]`). The app contributes only the
  device chooser sheet, the Bluetooth permission prompt and its radio errors,
  in the device language; everything else follows the account locale. A
  companion without the bridge reads an update request instead of the
  desktop Chrome/Edge requirement.
- Another app's share sheet or AirDrop can open a track file into the
  companion, which registers GPX, FIT, TCX, KML and KMZ as documents. The app
  stages the file and opens `/workout_imports/new`; when it registers the
  `shared-files` bridge component, the file panel's input receives the bytes
  and names the files it received (`[devdoc:import-sources]`). The fallback
  sport, the notes and the submit stay Rails'; a server without the controller
  receives no file and the app explains that it must be updated.
- Push (`[devdoc:push]`): when the app registers the `push` bridge component
  and the instance configures push, `/settings/notifications` adds the
  « Sur cet iPhone » card under the per-kind switches. « Recevoir sur cet
  iPhone » asks the app, which shows the system permission prompt the first
  time; « Masquer le contenu » is disabled while it is off. Both switches act
  at once — there is no submit, since the permission prompt is itself the
  confirmation — and the card says when the app cannot receive pushes
  (« Cette version de l'app ne peut pas recevoir de notifications »), when
  the iPhone refused them (« Notifications refusées dans les Réglages de
  l'iPhone… »), and when turning it on failed. It ends on the §19.28
  sentence. The card reads "on" only when the app's registration is the one
  this session holds; it is never rendered in a browser.
- The bulk selection and its action bar (§10.19) are a desktop affordance and
  are never rendered in the companion, on any screen size — the companion runs
  on iPad, so the width breakpoint alone cannot express that. This is the one
  case where the native marker removes a control rather than duplicated chrome:
  no data or action becomes unavailable, because the entire workflow is
  pointer-and-keyboard driven and every endpoint stays owner-scoped and
  user-agent blind.

- First launch opens one native server-address form: heading, explanatory
  sentence, visible field label, format example, and one `Continuer` /
  `Continue` action. Invalid input is explained inline and announced to
  VoiceOver. The native shell supports Dynamic Type and both system themes.
- The app remembers one server. Normal builds use HTTPS. Debug builds may use
  HTTP for explicit local development hosts. A page URL or an address carrying
  credentials is rejected rather than silently rewritten into a server URL.
- Opening the server visits `/workouts` through the existing members-only
  sign-in gate. WebKit persists the Rails session between app launches.
  Changing server clears this app's web session and navigation history, as
  stated under the form; it does not delete server data. The chooser has a
  cancel action when reached from an open server.
- In-app navigation matches scheme, hostname **and port**. External links open
  separately. Pages, including main destinations, retain native Back history.
  A Back chevron (accessible as `Retour` / `Back`) and the swipe-back gesture
  return to the previous page. The sign-in page resets the native root so logout
  cannot reveal an authenticated screen. Forms disable pull-to-refresh so it
  cannot discard entered data.
- The native navigation bar has an opaque, system-themed surface in every
  scroll state. The web viewport starts below it, keeping Allure's header and
  controls visible on initial load, navigation and rotation.
- A page-load failure has a native error heading, plain-language explanation,
  and retry action. The native server action appears to correct the address.
- The companion owns its native design reference and strings in
  `Config/locales/{fr,en}.json` in its repository; its Swift exporter writes
  bundled French and English resources. Native forms and errors follow the device
  language; bridged labels and Rails pages follow the account locale. This reference continues to
  govern the reused web UI and the integration behavior described above.

---

## 8. Information architecture

### 8.1 The tree

```
MAIN
  Publications / Feed         /feed                  signed in
  Moi / Me                    /me                    signed in
  Activités / Workouts        /workouts              signed in
EXPLORE
  Segments                   /segments              signed in
  Équipement / Equipment     /equipment             signed in
```

Settings is not a topbar destination: `/settings` is reached from the account
menu and renders the universal settings hub. Each sub-page keeps its own URL;
from `md` up its shell repeats the collection as persistent sub-navigation,
below `md` it links back to the hub (§8.5). Connected services are a sibling
area (§8.6), reached from the same menu.

`/` is a dispatcher: it sends members to `/me`. A visitor is sent through the
sign-in gate and returns to `/` afterwards. `/feed` is the canonical feed
address; no other route duplicates it. Import is **not** a navigation leaf — it
is a topbar action plus contextual CTAs (§7.3).

Deliberately **not** in the primary navigation:

- `/me/stats` and `/me/records` — reached from `/me`, which is their hub.
  Promoting them would give the personal data three competing entry points.
- `/@username` — reached from the account menu (`Profil public` /
  `Public profile`), because it is a *representation* of the account, not a
  section of the app.
- publishing profiles and privacy zones — they live under settings, where every
  other policy lives.

### 8.2 The navigation contract

Rules that `config/navigation.rb` must satisfy:

1. **No leaf may point at an unrouted helper.** Today nine of fourteen leaves
   silently vanish because their helper does not exist. A tree that hides its
   own items is a tree nobody can reason about. If a destination is not built,
   it is not in the tree.
2. **No single-child dropdown.** A parent with one visible child renders as a
   leaf pointing at that child; a collection with no accelerator value stays
   flat.
3. **A branch is a real destination.** Every parent has a landing page; the
   dropdown is an accelerator, not the only way in.
4. **Labels are i18n keys**, never literals, in both locales.
5. **Active state is server-computed** by `NavigationHelper`, path-only, so
   query parameters (filters, pagination) do not break highlighting.
6. **Icons are Tabler names without the `ti-` prefix**, and each is distinct
   within the tree.

M5 destinations (people, federation settings, Wanderer settings) attach where
§24 records; `/people` routes today. The following stream is folded into
`/feed`, not a second destination.

### 8.3 `/feed` — Feed

The feed is a **reverse-chronological publication feed**, not a dashboard.
Viewing requires an account ([ACCESS.md](ACCESS.md)): a visitor opening `/feed`
or any publication link is redirected to sign-in and returned to the requested
page. `/` sends members to `/me`.

Signed-in members see their personal stream: their own active publications —
whatever their audience, always included, each carrying a `Vous` / `You` badge
and its audience badge — plus local publications from accounts they follow and
the remote publications admitted for their account. Every card is rendered
from the immutable publication, never the source workout, owner included;
drafts live in `/workouts`, never here. A **Public** switch in the
page header (URL parameter, default off, and automatically on while the
account follows nobody) adds the instance's public publications, deduplicated
against followed authors and the viewer's own actor. Its info hint lives in an
accessible tooltip, and it applies on change. `/following` redirects here. The
list scrolls endlessly while
keeping the loader's page URLs filter-preserving; the real pagination nav is
the `<noscript>` fallback. The header carries no import button: Import stays in
the topbar and the empty state.

A feed item names its owner — avatar, display name and `@username`, linked to
their profile, with the instance badge for remote accounts — because a
federated feed is a stream of *people publishing*, not an anonymous card wall.

**Item anatomy.** One card (`feeds/_item`) serves a local publication and a
received note alike; provenance is a badge, never a second visual language
(§24). It is the workout card's linked anatomy (§8.4) with an author header,
top to bottom:

- the author header: avatar, display name and handle, all linked to the
  profile — `@username` for a local account, `@user@instance` plus the
  `bg-secondary-lt` « Autre instance » badge for a remote one; the viewer's
  own items add the `Vous` badge (§10.4 Mine) and their audience badge;
- the route image, full width between header and body, or its designed state:
  the 16:9 pending skeleton (`role="status"`, §11.1) while a local image is
  still rendering or a remote one is being fetched, or the muted 16:9
  « médias indisponibles » frame with a warning `ti-photo-off` when a remote
  image could not be fetched (§11.3); a note that declared no image shows
  neither;
- the workout card's top edge: the `md` sport tile (linked, name in its
  tooltip), the `h3` title carrying the card's stretched link — the card
  itself is not a button, the whole card is the link — and, on the right, the
  commute badge and the record badge naming every published record; the
  reaction bar's pills are the one deliberate exception, lifted above the
  stretched link because they act instead of navigating;
- the activity's smart date (`Hier 07:30`, §8.4), never the publication
  instant: the day separators carry that;
- a compact row of the primary metric tiles (§10.2, `allure-feed-metrics`):
  distance, moving time, the sport-preferred pace or speed, and elevation
  gain (average power in place of the speed for a power-led virtual sport,
  and as the fourth tile for a fixed-basis sport), two per row on phones. A
  metric the profile withheld has **no tile** — the card says nothing about
  what was withheld (§2.2) — and a metric the snapshot carries without a value
  renders `—`. A tile whose value is a published record carries the card
  stamp; the badge names the record, the stamp only decorates;
- a three-line excerpt of the published description, plain escaped text
  (never the remote HTML), and the recording device when the profile shares
  it;
- the reaction bar (§10.17) at the foot of the card: toggle buttons for a
  signed-in reader who may react, the non-zero counts only for the owner.

**Day separators.** The stream is sectioned by *publication day* in the
viewer's time zone — `Aujourd'hui`, `Hier`, `Avant-hier`, then the weekday
date — as `h2.hr-text` rules, so an old activity published today is read as
today's news carrying its own date. Item titles are `h3`. The endless scroll
drops a fetched page's leading separator when it repeats the day the column
already ends with (§10.14).

**Members only.** The feed renders only for a signed-in account
([ACCESS.md](ACCESS.md)); an anonymous visitor is redirected to sign-in and
returned to `/feed` afterwards. There is no visitor intro card and no
signed-out empty state: the auth layout owns the pre-session experience.

### 8.4 `/me` — the personal hub

Every "Voir…" link on the hub — the statistics, segments and records card
actions, and *Tout afficher* above the recent workouts — is a small
`btn-ghost-primary` text link closed by a chevron: they are the page's
outbound destinations, quiet enough that a card's content keeps the weight.
The buttons of the selection panels (the pulse's « Voir les N activités », the
calendar day and the sport-mix slice) are `btn-outline-primary`. The hub has no
filled button outside its empty state.

The owner's analytical home, the signed-in landing page, and the counterpart of
the public `/@username`.

The header leads with the account avatar (`lg`, in the iOS companion too),
the display name as the title and, under it, the handle and the account's
workout count (« @marie · 178 activités »); there is no pretitle.

The toolbar is the page's own control row, not a card. From `md` up it
reuses the workout list's **sport pills** (§10.6): *Tous* first, then every sport practised on
the period, most active first, each with its icon, name and the period's
count, plus the active sport even when it has none there; picking one submits
a plain GET form that keeps the period. The **period** is a segmented control
(§10.15) beside them. On phones (§7.3) both become native `form-select`s on
one row carrying the same URLs: *Tous les sports* plus every sport practiced
at least once — names only — on the left, taking the free width and
truncating its label, and the four short labels — *Semaine*, *30 jours*,
*Année*, *Tout* — on the right. The choices are
*Cette semaine* (the viewer's calendar week so far, week start per
`users.week_start`), *30 derniers jours* (rolling, the default), *Cette année*
(January 1st to today) and *Tout*. Only the rolling window rolls; the calendar
periods never do. The sport filter scopes the period summary, its charts and
deltas, the calendar dataset, the sport mix, regularity, the segment efforts,
the records teaser and the recent list; equipment is no longer on this page.

Below the toolbar:

- the period card: a **figure strip** (§10.2) of four bare figures —
  workouts, distance, elevation, time — for the selected period, each with
  its move against the previous window (previous calendar week, previous 30
  days, or the same elapsed period last year); then, below a hairline, the
  **intensity pulse** (§15.1): one mirrored weekly waveform spanning the
  whole history, in which the selected period keeps the primary ramp while
  the rest of the history takes a neutral grey ramp, with an explanatory ⓘ
  hint after its label, the active-week count and navigation buttons on the
  right, a reading line naming the period's peak and its facts, and — as the
  text equivalent — a screen-reader values table plus a keyboard cursor that
  walks the loaded weeks;
- the activity calendar with a metric selector (duration by default, distance,
  activity count), a Less→More legend and a window navigation (§15.3);
- the sport mix donut, with a duration/distance/activity selector and its table,
  shown only with several sports and no active filter; each legend entry
  carries its share, and the plot is shorter on phones so no blank band is
  left under the donut;
- the regularity card: the current week against the four-week average, the
  current and best streaks, active days over twelve weeks, the best week, and
  the link into `/me/stats`;
- the latest segment efforts — date, segment, the effort's sport, time, then
  two places that are never merged: *Perso*, where the effort
  stands among the viewer's own attempts on that segment (`2 / 5`, led by the
  personal-place trophy — gold, silver, bronze — for the three best), and
  *Classement*, the viewer's leaderboard standing shown on the personal-best
  row only (`5 / 12`, the laurel for the top three, never the trophy); each
  header carries a tooltip that says which is which. Below `md` the table
  becomes the §12.3 stacked rows: the sport tile and the truncated name, then
  the date, the time, *Perso* and the laurel. Then the latest records: classic
  types and best-effort distances together, newest workout first, filtered
  like `/me/records`, one list row each — the record name over its sport, the
  value at the end — whose whole row opens the workout that holds it;
- the recent workouts: the twelve latest (four on phones, below `md`) as
  fully clickable cards (no footer
  button; the title's stretched link covers the route image and the pending
  skeleton). The sport tile and the title share the card's top edge with the
  badges, all icon-only (`fit: :icon`) and named by their tooltip: the commute
  badge, the record badge naming every record the workout holds (§10.4), the
  « Avec @X » badge of an activity done with someone (§10.18), and
  the audience badge when the workout is shared or scheduled — an unpublished
  card carries none. The group is lifted above the stretched link for its
  tooltips and stays on one line, so the title keeps the width it needs.
  Below, a smart relative
  day on its own line and, under it,
  the key metrics only — distance, human-scale duration, the sport-preferred
  average speed or pace (average power for a power-led virtual sport), and
  elevation gain — each fact kept whole so the line wraps between facts, never
  inside a value. Rows fill every line at two,
  three or four cards, and the grid breathes one gutter step more than the
  surrounding cards at every width.

The two detail pages live under the hub path, one click away:

- `/me/stats` — the full M3 `by_time` and `by_sport` datasets;
- `/me/records` — the eight record types and the per-distance best efforts,
  grouped by sport.

The calendar lives here, not on `/feed`. `[devdoc:tracking-depth]` places it
on "the dashboard"; `/me` **is** that dashboard. The M3 data contract (client-side
render of `by_time?time=day`, `sport_id`-filterable) is unchanged, and §15.3
defines the calendar: one link per non-empty day.

### 8.5 `/settings` — universal hub and sub-pages

`/settings` is the universal settings hub on every breakpoint, reached from the
account menu; it is never a topbar dropdown. It renders the grouped collection as
full-width cards: one card per group, one full-width link per sub-page with its
Tabler icon, label and chevron, each link at least 44 px high. Every sub-page
keeps its own URL, so deep links and browser history keep working.

The sub-page shell is the Tabler settings pattern (`settings.html` /
`settings-plan.html`): one card holds the grouped section navigation in a
bordered `md-3` column beside the content in the `md-9` column. The page header
is « Paramètres » / « Compte » on every sub-page, the content card-body opens on
the active section as its own `h2`, and each page keeps its own cards — nested
in the shell card, as on Tabler's settings-plan page — and its per-card saves,
whose footers follow the action-group rule of §10.3 (left from `md`, right under
the thumb on phones). From `md` up, the active entry carries Tabler's active
state and `aria-current="page"`. Below `md` the navigation column is hidden and
the page opens with a 44 px « Retour aux paramètres » link to `/settings`, so a
phone reaches the requested form within the first screen instead of scrolling
past a full-height index on every sub-page. The groups are **Compte** (Profil,
Apparence, Unités, Sports par défaut),
**Publication** (Profils de publication, Zones de confidentialité) and
**Système** (Notifications, Données et recalculs, Altitudes when the instance
configures a provider, API et webhooks, Sécurité).

| Sub-page | Contents |
|---|---|
| `/settings/profile` | display name, bio, avatar (§9), leaderboard category (§19.6, [SEGMENTS.md](SEGMENTS.md)), separate opt-ins for whole-history sport statistics and personal records (§19.38, §20.14) |
| `/settings/appearance` | theme, locale, route-image theme (auto/light/dark), workout track smoothing (level) |
| `/settings/units` | unit system, time zone, week start |
| `/settings/sports` | default variant per generic sport (cycling, running, walking) used at import ([WORKOUT.md](WORKOUT.md)) |
| `/settings/notifications` | « Notifications dans l'application »: one switch per kind, saved by the card's submit; then, only in a companion registering the `push` bridge component on an instance with push configured, the « Sur cet iPhone » card (§7.7, §19.28) |
| `/settings/elevation` | terrain elevation opt-in, only when the instance configures a provider (`[devdoc:elevation]`) |
| `/settings/publishing-profiles` | the profile collection (existing route) |
| `/settings/privacy-zones` | the zone collection (existing route) |
| `/settings/security` | three groups (§20.15): two-step verification first (obligation, authenticator app, passkeys, recovery codes); the ways in side by side, password and identity providers; then the active sessions (paginated, sortable table with device, sign-in time and method, last activity and the lifetime rule) with « Fermer toutes les sessions » in its header; closing a session re-authenticates first |
| `/settings/data` | derived-data maintenance for the account's own workouts: rebuild, route images, places, elevation (`[devdoc:derivations]`) |
| `/settings/api` | « API et webhooks »: API tokens and webhooks (§20.18, `[devdoc:api]`); never rendered in the iOS companion's settings navigation |
| `/settings/account` | « Compte »: « Exporter mes données » (a live card: prepare, preparing, ready with size and expiry, failed, expired, cooldown) and « Supprimer mon compte » (§19.29), last in the « Système » group; a deactivated account lands on `/settings/account/deletion` in the auth layout (`[devdoc:account]`) |

Two rules:

- **Preferences save individually and immediately-explicitly.** Each card has
  its own submit; there is no global "save all" that makes a user wonder what
  else they changed.
- **Collections stay collections.** Publishing profiles and privacy zones are
  CRUD resources with their own index/new/edit pages inside the settings shell;
  they are never inlined into a preferences form. Both indexes are the same
  compact `card-table` list: name (linking to the editor) with its avatar and
  state badge, the key figure right-aligned, and ghost icon buttons for edit
  and delete whose `aria-label` names the row. The zone list shows the radius
  and, from `md`, the centre.

`/settings/data` is not a preferences form: it is a small maintenance console.
Each of its four cards states what the rebuild does, how many of the account's
workouts are concerned (`%{count}` with the singular/plural forms), and offers
one button, disabled while the count is zero. Every button is
confirmation-guarded through the shared dialog (§10.10); buttons say
« Recalculer mes activités », « Régénérer mes images », « Recalculer mes
lieux » and « Estimer mes altitudes » — never a bare "Run". The counters
refresh through the shared live-frame polling pattern, with the ordinary
"refreshed at" line; nothing here exposes another account's data, and no copy
implies that a rebuild changes what has already been published. The same image
rebuild is available for one workout from the header `⋯` menu
(« Régénérer l'image »).

M5 shipped federation diagnostics inside this shell; the administration
console (§7.6, `[devdoc:admin]`) now owns them at `/admin/federation`, and
`/settings/federation` redirects there for the operator. A `wanderer` sub-page
remains post-M5, alongside the external-peer interoperability backlog.

### 8.6 `/connections` — connected services

Connected services have their own area beside settings, reached from the
account menu's « Services connectés » item. The item appears only when the
operator enables a remote import source, or when the account still holds a
connection to one the operator has since disabled — that connection must stay
reachable to be unlinked. The area reuses the settings shell (§8.5) unchanged,
so the two read as the same kind of page.

`/connections` is the hub: one full-width row per service the account may see,
with the service's mark, its name, its state badge (§10.4) and, once linked,
the external account and when it last synced. Each row opens
`/connections/:provider`, the service's own page: the shell's navigation lists
the services, and the content is four cards, each with its own save —
**Connexion** (the state badge, the link form or the linked account's facts,
the sync actions and the privacy copy of §19.23–§19.23d), **Récupérer des
activités** (`[devdoc:remote-imports]`), **Préférences**, and
**Déconnecter** as the page's danger zone (§19.24). Only the service's own
cards refresh, through the live-frame pattern, and only while it is linking or
unlinking, so a form being filled in on another service is never replaced.
Below `md` the navigation column is hidden and the page opens with
« Retour aux services connectés ».

A service the operator disabled and the account never linked has no page: an
old bookmark or notification lands on the hub. The batch page's « Reconnecter »
link and the connection notifications open the service's page directly, and
`/settings/connections` redirects to the hub, so the former address and old
bookmarks keep working.

---

## 9. Identity and avatars

### 9.1 The fallback chain

Resolved server-side, in order:

1. **Uploaded image**, if the account has one.
2. **Proxied Gravatar**, if the account opted in and a Gravatar exists.
3. **Generated avatar** — always available, never fails.

The chain is resolved once, server-side, and the view receives a URL. A view
never branches on which source won.

### 9.2 Generated avatars

Deterministic, offline, no network, no third party.

- **No initials, no lettering.** The generated avatar is abstract art; the
  adjacent name is the identifier (§9.5).
- A geometric pink pattern: a deep pink background carrying two to four
  decorative shapes in lighter pinks.
- The seed is drawn at random **once, when the account is created**, and
  persisted on the account (`users.avatar_seed`; a migration backfilled
  existing accounts). The art is therefore random across accounts but never
  changes for one: same account, same avatar, on every page.
- The recipe is derived from `SHA-256` bytes of the seed, never from Ruby's
  `Random`, so the art survives Ruby upgrades. It is rendered locally and is
  not federated.
- The backgrounds come from a **fixed curated pink palette** — not from raw
  HSL arithmetic, which produces muddy and inaccessible colours — chosen so
  white holds **4.5:1** against every entry, in both themes. Contrast is a
  property of the palette, not something computed at render time.
- Rendered as inline SVG, never as a generated image file.

### 9.3 Gravatar

**Opt-in per account, proxied and cached server-side, never hotlinked.**

This follows the rule already applied to fonts (`$font-google: false`) and
planned for M5 remote avatars ("avatar proxy/cache — never hotlink"). A direct
browser request to `gravatar.com` would disclose the viewer's IP address and the
account's email hash to a third party on every page that renders an avatar,
including pages viewed by other signed-in accounts.

Design consequences:

- the setting is **off by default**;
- its label states the trade-off plainly, in the sober register (§19.10);
- when enabled, the instance fetches and caches; the browser only ever talks to
  the instance;
- a fetch failure is invisible to the user — the chain falls through to the
  generated avatar. It never renders a broken image or an error.

### 9.4 Upload

In profile settings: current avatar, replace, remove.

- The picker accepts PNG, JPEG and WebP; the size limit and the accepted
  formats are stated on the page, *before* the dialog opens, not after a
  rejected upload.
- Selecting a file previews it locally, in the same circle, before submit. The
  browser performs a first type/size check; the server performs the
  authoritative one.
- The picked image opens a **crop stage** under the picker: a square window
  over the image at its true proportions, a circular mask showing exactly what
  the avatar will show, and the live circle beside the name following the
  choice. Dragging moves the image; the slider, the wheel and a pinch zoom it;
  the arrow keys move it and `+`/`−` zoom it for keyboard users; **Recentre**
  returns to the centred square. At the smallest zoom the short side fills the
  circle, so the square never leaves the image and never pads it.
- The server validates the real bytes, rejects anything unreadable, larger
  than 20 MB, or wider/taller than 8192 px, decodes the image directly at
  4096 px on its long side (EXIF orientation applied), keeps the square the
  account chose — or the centred one when no placement arrived — then strips
  metadata (including any EXIF location) and stores a normalized 512×512 WebP.
  The original upload is never stored or served.
- While the generated art is the visible source, a **Generate a new avatar**
  control rotates the persisted seed and saves it immediately, without a page
  reload. It is repeatable and not destructive. When an uploaded image or a
  cached Gravatar wins the chain the control is hidden; removing that source
  falls the avatar back down the chain.
- Removing an upload falls back down the chain; it is not a destructive action
  and needs no confirmation.

### 9.5 The avatar component

One component, sizes `xs / sm / md / lg / xl`. It accepts an image URL and a
fallback identity, and it is used identically for the current account, another
local account, and — in M5 — a remote actor. Nothing in it knows about
federation, which is precisely why M5 can reuse it.

Tabler's avatar component is the implementation. A **person's avatar is a
circle**: `.avatar` already carries Tabler's pill radius, so no shape class is
added. `avatar-square` is reserved for marks that stand for something other
than a person — sport tiles (§6.5) and feature icon badges — matching Tabler's
own guidance that a square avatar is "the usual choice when the avatar stands
for a company, a project or an app rather than a person".

Rules:

- an avatar is **never** the only identifier of a person: a name or an alias is
  always adjacent, except in a `xs` avatar stack where the group is labelled;
- `alt` is empty when a name is adjacent (decorative), and the account name when
  it is not;
- an avatar never shrinks: `.avatar` carries `flex-shrink: 0`, so a long
  adjacent text wraps instead of squeezing the circle into an oval;
- an avatar image is **never distorted**: a non-square upload, a cached
  Gravatar or a remote avatar is covered, never stretched (`object-fit:
  cover`), so the circle keeps the image's proportions;
- **anonymous leaderboard rows have no avatar at all** (§19.5) — not a generic
  placeholder, which would still be an identity affordance.

---

### 9.6 Instance supporter badge

While `FUNDING_ENABLED` is true, a local account with a current contribution
may show its tier pictogram (`coffee`, `beer`, `energy`, the reaction icons)
as a small circular overlay at the lower right of its avatar. It is never
baked into image bytes, never federated, and never replaces the person's name.
There is no mark for an account that does not contribute. Anonymous leaderboard
rows keep no avatar and therefore no badge.

The account may hide it or choose primary, blue, teal, orange, purple or slate
from a closed palette. Each filled badge uses white ink with at least 4.5:1
contrast and a surface-coloured separating ring, in either theme. The avatar
keeps its dimensions; the overlay scales with it. Its accessible label is
§19.37 when the avatar is not decorative.

The web account menu links to `/funding` while funding is enabled. This page
explains the voluntary contribution before three equal tier cards (one column
on phones, three from `md`), each naming its drink and linking to the
operator's hosted checkout. Unconfigured tiers have no payment button. No
amount is invented locally. A persistent notice explains manual confirmation.
The automated annual-subscription contract is `[devdoc:funding]` (not yet
implemented). Before enabling an automated provider, the page must explicitly
name **annual automatic renewal**, distinguish subscription management status
from the badge's paid-through date, and offer a web-only hosted management /
cancellation action. Cancellation preserves the already paid badge period;
payment failure never implies losing application access. Manual grants remain
non-renewing and keep the manual-confirmation notice. Subscription management
controls are absent from the iOS companion just like checkout links.
The administration contribution history distinguishes the payment date from
the billed period's start and end, and labels a paid period that has not begun
as upcoming, never active. Cancellation state belongs to the subscription,
not to the already paid contribution's status.
Badge preferences live in a profile-settings card; the operator's account page
offers a manual grant and the funding list offers audited revocation. These
controls and payment links are absent in the iOS companion; badges still show.

### 9.7 Instance operator badge

The configured operator's avatar carries a second overlay: a small circle at
the **lower left**, in the brand primary with white ink, holding the
`user-shield` pictogram. It marks the role, not a contribution: it is shown
whenever `INSTANCE_OPERATOR_USERNAME` is set, independently of
`FUNDING_ENABLED`, and the badge-hide preference never applies to it. An
operator who is also a supporter shows both overlays — operator at the lower
left, supporter at the lower right. Like the supporter badge it is local
display only: never baked into avatar bytes, never federated, and hidden for a
deactivated account. Its accessible label is « Opérateur de cette instance »
/ "Operator of this instance", appended to the avatar's label when the avatar
is not decorative.

## 10. Component vocabulary

Every reusable pattern. If a screen needs something not here, the component is
added here first.

### 10.1 Card

The default container. `card` / `card-header` (title + optional actions) /
`card-body` / `card-footer` (optional). Flat, bordered, radius 5px.

- A card has a title unless it contains a single self-describing visual.
- Card actions are secondary or ghost buttons. Two documented exceptions on
  the workout page: the participants card's « Ajouter un participant » is a
  small primary button, and the comments card's close/reopen switch is a
  small primary ghost button (`btn-sm btn-ghost-primary`), the counterpart
  of the publications card's danger ghost « Retirer toutes les
  publications ».
- Cards in a grid use `row-deck row-cards` so heights match.
- A card never scrolls internally except a map or chart canvas.
- When a card's whole surface is a link (workout cards, feed
  items), hover and focus tint the frame — primary border mixed at 40 % and
  Tabler's hover shadow, over 150 ms (§16) — and never underline the title; the
  state is mirrored on `:focus-within` (§18.4).

### 10.2 Metric tile

The atom of every summary. Label above, value below, optional delta or context
beneath.

```
┌────────────────────┐
│ DISTANCE           │  label: small, uppercase, muted
│ 42,2 km            │  value: h2, tabular figures
│ +12 % vs. 30 j     │  context: small, muted (optional)
└────────────────────┘
```

- Values use tabular figures so columns of tiles align.
- Units are part of the value, muted and smaller than it — `0.7em` in the
  primary grid — never a superscript, never a separate line.
- A primary tile's label may wrap to a second line; its value sits on the
  tile's bottom edge, so every value in a row shares one baseline however the
  labels break.
- A tile or chart label that needs framing may carry a compact ⓘ hint
  directly after it (`.hub-tile-hint`, `ti-info-circle`): a real button whose
  tooltip explains the value or the chart, keyboard-reachable, with its
  invisible hit area meeting the 44×44 touch target (§18.4) without enlarging
  the label row. It is decoration beyond the printed value, never the only
  carrier of a fact.
- The **figure strip** (`.hub-figures`) is the tile's bare sibling for a
  period summary that should read as a sentence — *9 activités · 46,2 km ·
  800 m · 4 h 12 min*: four figures in one row inside a single card, value
  first (`1.75rem`, semibold, tabular), label beneath (small, uppercase,
  muted) with the delta badge beside it, parted by hairlines instead of card
  borders. Two per row on phones. Its distance prints one decimal and its
  time is the human-scale duration (`4 h 12 min`), because a headline figure
  is read, not computed with.
- A primary tile whose value holds a personal record carries Tabler's **card
  stamp** — the gold trophy on a soft gold-tinted disc in the tile's top corner
  (`card-stamp` / `card-stamp-icon.allure-stamp--gold`, `personal_place_stamp`,
  §10.4) — instead of the small trophy marker. The stamp is decoration (`pointer-events: none`); the
  record is named by the tile's tooltip and a visually hidden sentence.
- An absent metric renders `—` (em dash) with an `aria-label` of "not
  recorded"/"non mesuré". It is never `0`, never blank, never hidden — a missing
  heart rate and a heart rate of zero are different facts.

### 10.3 Buttons

| Level | Style | Rule |
|---|---|---|
| Primary | `btn-primary` | **At most one per page region.** The single most likely next action. |
| Secondary | `btn-outline-secondary` | Alternative actions. |
| Ghost | `btn-ghost-secondary` | Tertiary, in card headers and table rows. |
| Danger | `btn-outline-danger`, or `btn-danger` inside a confirm modal | Never adjacent to the primary action. |

Icon-only buttons require `aria-label` and a tooltip, and are only used in table
rows and card headers, plus the topbar import action below `lg` (§7.3). Minimum target size 44×44 CSS px on touch (§18.4).

**Action groups.** Every group of decision buttons — a `form-footer`, a
`modal-footer`, or an `allure-actions` group in a `card-footer` or inline in a
card (confirm / decline, accept / reject, save / cancel) — follows one placement
rule, set in `components/_actions.scss` and nowhere else:

| Width | Group position | Order, left → right |
|---|---|---|
| from `md` (768 px) | left | **primary** · cancel / secondary |
| below `md` | right | cancel / secondary · **primary** (under the thumb) |

The primary action is always **first in the markup**; only CSS
(`row-reverse` below `md`) changes the visual order, so the tab order, the
screen-reader order and the implicit Enter submit stay the same at every width.
Never add `justify-content-end`, `ms-auto` or a reversed markup order to an
action group. Page-header actions, toolbars, filter bars and pagination are not
action groups.

### 10.4 Badges and status pills

| Kind | Shape |
|---|---|
| Sport | §6.5 |
| Audience | One badge (`PublicationBadgeHelper#publication_badge`) for every surface that states a workout's or a course's sharing state — owner cards, the list table, the feed, the workout page, a course, the administration console and the styleguide. **The mark says what it is, the colour and the label say which state**: public `bg-success-lt` + `ti-broadcast`, followers `bg-info-lt` + `ti-broadcast`, scheduled in the tint of the audience it will reach (green for public, blue for followers) + `ti-broadcast` with a slow pulse on the mark, the pulse alone telling it from a live publication beside the « Programmée » label (a publication waiting out its delay — never shown as "not published"; the pulse is dropped under `prefers-reduced-motion`; one badge per scheduled publication when no publication is live yet), not published `bg-secondary-lt` + `ti-broadcast-off`. The label is always in the DOM — never carried by colour alone (§18.6): `fit: :auto`, the default, prints it from `md` up and only hides it visually below, where the badge becomes the square icon pill and a tooltip gated on the same media query names the state and takes the focus stop; `fit: :icon` keeps the icon-only form at every width for the rows that have no room for a word — the workout cards and the phone rows of the list. The cards and phone rows show no badge for the not-published state — it is the default, and only a shared or scheduled workout is marked; the desktop table's state column, the workout page and the sharing card keep it. A course states the same states with its own words (`segment_visibility_badge`, `segments.visibility.*`), and its page header names the audience it is published to. The record and commute badges keep their own icon-only form on the cards. The estimated-elevation marker on the profile title takes the same icon-only form (`ti-mountain`) |
| Mine | The viewer's own item: « À moi » on a course of theirs in the Segments list, « Vous » on their own publication in the feed. `BadgesHelper#mine_badge`, `bg-primary-lt` + `ti-user-circle`, the same responsive rule as the audience badge (label from `md` up, icon and tooltip below) |
| Together | An activity done with someone (§10.18): « Avec @X » on the participant's page, the source's header and card for its owner, the linked recording's header and card, and the credit row's header and card. One badge per workout: every confirmed participant and linked source joins it (« Avec Eva », « Avec Eva et Joan », « Avec Eva et 2 autres », the tooltip naming everyone). `BadgesHelper#together_badge`, `bg-primary-lt` + `ti-users`, a link to the source while it exists and the badge names that single source, never a link to a profile, `bg-secondary-lt` « Avec @X · activité source supprimée » once it is deleted; responsive on headers, icon-only on cards |
| Personal place (record) | **The trophy, you against yourself** (`ti-trophy`, `MedalsHelper#personal_place_*`). Gold is the record (« Record : 10 km »); silver and bronze are the owner's second and third best time (« 2e meilleur temps : 10 km »), shown only on best efforts and on one's own segment efforts, never published. Three sizes, the same everywhere: the **pill** (`bg-secondary-lt`, `personal_place_badge`) holding the trophy and its short label (`Record`, `RP`, `2e`, `3e`) in badge rows — the header and card record pill is gold only and its tooltip names every record held, classic types and best-effort distances; the **bare trophy** (`personal_place_icon`) beside a label — secondary metrics, best-effort rows, climbs, own efforts, the hub's personal column; the **stamp** (`personal_place_stamp`) on a primary metric tile (§10.2). A list made only of records (`/me/records`, the hub's latest-records card) carries no trophy: every row already is one. The trophy never marks a section, a tab or an empty state in a place colour |
| Rank marker | **The laurel, you against others.** A leaderboard place renders its **numeral**; the top three lead with the laurel of their place (`ti-laurel-wreath-1/2/3`) in the place colour — there is no round disc. Every numeral speaks its rank (`Rang 4`), the top three also carry the `1re place` / `2e place` / `3e place` tooltip, so colour is never the only encoding. With a board size it reads `2 / 12`, the suffix rendered by `rank_medal`, on every surface (board, the segment index's « Mon RP » column, the hub, the workout's segment tab). A **podium stamp** (`rank_stamp`, the same laurel on its tier's disc) marks a top-three standing on a summary tile (§20.6) |
| Personal place on a segment effort | The trophy pill of the personal place (`RP` gold, `2e` silver, `3e` bronze), then — only for `RP` and only when the board ranks the effort — the laurel rank with the board size beside it (trophy `RP`, then laurel `2 / 12`). The rank never tints the pill, the pill never takes a laurel |
| Commute | `bg-secondary-lt` with `ti-briefcase` and the translated label; shown wherever the workout (or a publication that shares the flag) is presented |
| Manual entry | « Saisie manuelle » / "Manual entry": `bg-secondary-lt` with `ti-pencil` and the label, on the owner's page header of a workout typed in by hand (`[devdoc:manual-entry]`); its card top states it in place of a route image. Owner-only: a manual entry is never published |
| Import entry status | `bg-*-lt` with icon: imported / failed / duplicate / cancelled / queued |
| Equipment state | active / inactive |
| Segment kind | segment `ti-route` (the one segment icon everywhere: navigation, tabs, pages, empty states), route `ti-route-2`, loop `ti-repeat` |

Every badge carries an icon or text beyond its colour (§18.6).

### 10.5 Data table

`table table-sm table-vcenter`, header in `--allure-surface-sunken`.

- Numeric columns are right-aligned with tabular figures; text columns are
  left-aligned.
- The first column identifies the row and is never icon-only. One exception:
  a multi-selection table may lead with the checkbox column (§10.19), which is
  a control, not the row's identity — the title column keeps that role.
- Sortable headers are buttons with `aria-sort`, and sorting is URL state
  (§13).
- Row actions live in a trailing column, icon-ghost buttons with labels.
- Every table declares its **column priorities** (§12) and its empty state.
- A table never has a horizontal scrollbar on desktop; if it needs one, it has
  too many columns.

### 10.6 Filter bar

Sits between the page header and the content. Contains the filter controls, the
active-filter count, a clear-all action, and the result count.

- A bar with more controls than fit one row (the workout list, §20.4) splits
  them by use. The **toolbar** keeps what is used on almost every visit, always
  visible: on the workout list the **sport select-group** (the account's own
  sports, most practised first, as Tabler's plain `form-selectgroup` checkbox
  group, each pill with its icon, name and count — wrapped from `md` up, one
  sideways-scrolling row with a faded trailing edge below it, the first
  selected pill scrolled into view), then one row with the **period** and the
  **sort** selects (field and direction in one URL value, §13.2), each led by
  its icon, and the drawer toggle at the trailing edge. On phones the sort
  shrinks to its icon square (the native select still covers it and its
  `aria-label` names it) and the toggle keeps its icon and badge only.
- The rarely used filters live in a **drawer** that never opens by itself: a
  Bootstrap off-canvas panel from the right, turned into a bottom sheet below
  `md`, so it never pushes the content down. The toggle carries, as a badge,
  the count of the filters the drawer owns; a filter in the toolbar never
  lands in it. The page header carries no import or new-workout action — the
  topbar import action is the standing entry (§8.1). Without JavaScript the
  drawer is an ordinary block of the form and the toggle is hidden.
- One form carries every control, so changing a filter or the sort never
  drops another one.
- Toolbar controls use the compact size (`form-*-sm`, `btn-sm`), the drawer
  the regular one; on coarse pointers the hit area returns to the 44px touch
  target (§18.4).
- Date-range fields only apply to the custom period: they are disabled — and
  therefore absent from the query string — while a preset is selected. They
  live in the drawer: choosing the custom period opens it on the dates, and
  closing it without applying restores the period the list shows.
- Toolbar controls apply on change. The drawer's controls apply together with
  its « Afficher les résultats » button (Enter in a text field submits too),
  so choosing several of them never reloads the page under the open sheet.
- The drawer's active filters render as removable chips below the toolbar,
  beside the clear-all action; a control that already shows its own state (a
  sport pill, a preset period) gets no chip.
- The result count is a live region so screen readers hear the change; on the
  workout list it sits under the page title and reads « 37 activités sur 178 »
  while any filter is active.
- A filtered-empty result is a **different** empty state from a never-populated
  one (§11.4).

### 10.7 Alerts (inline)

Bootstrap alerts at the top of `.page-body`, in flow, dismissible. Used for
flash messages and for persistent explanatory panels.

- They stay until dismissed or navigated away from; they never auto-hide.
- Form validation summaries are alerts, never toasts.
- An explanatory panel (info) is not dismissible if it carries a privacy
  obligation (§19).

### 10.8 Toasts

Bottom-right on desktop, bottom-centre above the bottom bar on phones. For
**asynchronous outcomes only**: a batch import finishing, a route image becoming
available, a recompute completing, a publication being delivered.

- Rendered into an `aria-live="polite"` region that exists in the layout from
  first paint.
- Auto-dismiss after 6 seconds, pause on hover and on focus, always manually
  dismissible.
- Never used for anything the user must read to proceed, and never for form
  errors.
- Maximum three stacked; older ones collapse.

### 10.9 Modal

Three uses only: **destructive confirmation** (§10.10), **focused creation**
that would otherwise lose page context (adding equipment from a workout page),
and the **release notes dialog** below.

Everything else is a page. Modals are hostile to deep links, Turbo caching and
small screens.

A dialog header keeps vertical padding, so a title that wraps never touches
the dialog's edge. On phones a dialog keeps a 1rem margin plus the device safe
areas (`components/_modal.scss`): its header never sits under the status bar and its
footer never under the bottom bar, the companion's native tabs or the home
indicator. Nothing floating (the feedback button) is drawn over an open dialog.

**Release notes dialog.** Opened at will from the footer's version line (§7.5),
and after a release it opens itself once per account. The seen marker belongs
to the account, never to the browser: a release must not be re-announced on
every device. A release with no curated notes shows a plain footer version and
no dialog at all.

```
┌─────────────────────────────────────────┐
│ Version 0.2.3                      [×]  │  version: the release, muted
│ Nouveautés                              │  title: what's new
├─────────────────────────────────────────┤
│ • one short sentence per change         │  the notes, flat list
│ • …                                     │
├─────────────────────────────────────────┤
│                               [ Fermer ]│  one non-destructive close
└─────────────────────────────────────────┘
```

Rules:

- notes are curated per release in `config/release_notes.yml`, in every locale,
  in the neutral register — no internal jargon (§3.5), no numeric value the UI
  does not itself show;
- no action button and no confirmation verb: this is information, not a
  decision;
- the close button is focused on open, `Escape` and backdrop click dismiss;
- shown at most once per account and per release; the acknowledgement is
  recorded as soon as the dialog appears, so an immediate dismissal counts;
- the footer trigger is a button only when there is something to show.

### 10.10 Confirmation dialog

Turbo's native `data-turbo-confirm` is replaced by a Tabler modal, because a
browser dialog cannot state consequences, cannot be translated beyond one
string, and cannot be styled.

Anatomy:

```
┌─────────────────────────────────────────┐
│  ⚠  Supprimer cette activité ?          │  title: the question
├─────────────────────────────────────────┤
│  Consequence sentence, plain language.  │  what is lost, irreversibly
│  • the publication is withdrawn         │  bullets when several things go
│  • 3 passages de segment sont supprimés │
├─────────────────────────────────────────┤
│ [ Supprimer ]  [ Annuler ]              │  ≥ md: destructive left-most
└─────────────────────────────────────────┘
```

Below `md` the footer sits on the right with the destructive button
right-most (`[ Annuler ] [ Supprimer ]`), as every action group (§10.3).

Rules:

- the title is a question naming the object;
- the body states what is lost and what cannot be undone, in the sober register;
- the confirm button repeats the **verb**, never "OK" or "Yes";
- the cancel button is focused on open;
- `Escape` and backdrop click cancel;
- for irreversible actions affecting shared data (deleting a publication), the
  §19 copy is mandatory and verbatim.
- a **bulk** operation is the documented exception: its review page (§10.19,
  §20.4) is the confirmation. A browser dialog cannot list the exact counts,
  the skipped rows and the §19 copy, and the decision belongs on a page that a
  second look can scroll.
- the **unsaved-changes dialog** (§14.3) is the same anatomy: the question
  names what would be lost, the confirm button repeats the verb of the context
  (« Quitter » or « Enregistrer »), and « Annuler » is focused on open.

### 10.11 Empty state

Tabler `.empty`: icon, heading, one sentence, one action. Detailed in §11.

### 10.12 Map card

Contract already implemented in `shared/_map`, kept: `url`, `colour`, `scope`,
optional `selection`. Card header carries the colour-by selector, which hides
itself when fewer than two metrics exist. Sizing in §15.2.

### 10.13 Chart card

Apache ECharts in a card with loading / empty / error layers. Rules in §15.1.

### 10.14 Pagination

Pagy with the existing hand-rolled Bootstrap nav, rendered **both above and
below** long lists. The top nav is compact (prev / position / next); the bottom
nav is the full page series.

Page navigation preserves all active filters, and page state is a URL parameter
so back/forward work.

**Endless scroll.** `/feed` and the workout list's card view (`/workouts`,
whose cards reproduce the `/me` presentation) scroll endlessly: an intersection
observer loads the next page and appends it, and the real Pagy nav is rendered
inside `<noscript>` only, so the list still pages without JavaScript and for
crawlers. The workout list's table view keeps the nav above and below. The
loader fetches ordinary page URLs, so the Public choice and every filter still
round-trip; a failed load backs off briefly and retries on the next scroll
without any error chrome. The feed's day separators (§8.3) are deduplicated
on append: a fetched page that opens with the day the column already ends
with loses that leading separator.

### 10.15 Segmented control

Tabler's `nav nav-segmented` (with `nav-sm` in toolbars) is the component for a
small, exclusive choice: the `/me` period selector, and the chart
metric selectors. It is never used for actions — those stay buttons.

- **Navigation variants use links** with `nav-link` items, `active` on the
  current one and `aria-current="true"`; the group carries an `aria-label`.
  The `/me` period selector is links: every choice is a URL. On phones it is
  a native `form-select` inside a GET form that submits on change (a
  `<noscript>` button without JavaScript), so the choice stays a URL there
  too. The `/me` sport selector is the workout list's sport pills from `md`
  up and a native select on phones (§8.4, §10.6), not a segmented control.
- **JavaScript selectors use radio inputs** (`.nav-link-input` + a `nav-link`
  label): the checked state is native, arrow-key navigation comes free, and a
  Stimulus controller listens on `change`. The `/me` calendar and sport-mix
  metric selectors are radios. On phones both are native `form-select`s bound
  to the same action, kept in step with the radios by their controller, so
  each card header stays on one line.
- Icon-only items require an accessible name (`aria-label` plus a tooltip for
  pointer users). The sport items carry the shared sport glyph at the
  control's `nav-link-icon` size; a sport tile, with its own surface and
  border, is never nested inside the control.
- The control's own sizing wins: use `nav-sm` in toolbars and never restyle a
  segment's box, so the icon-only and text segments share one height.
- Never duplicate the selection state as ad-hoc `btn-primary` classes; the
  component styles `active`/`:checked` itself.

### 10.16 Notification bell and inbox

Tabler's navbar notification component: a bell left of the account menu, a
count badge, and a `dropdown-menu-card` listing the latest notifications. The
full, paginated list is `/notifications`.

- The trigger is static; only the badge polls (60 s, paused while the tab is
  hidden), and the dropdown body is a Turbo Frame refreshed when it opens, so
  Bootstrap's dropdown binding is never re-initialized.
- The badge is pinned absolutely to the inside top-right corner of the
  trigger's 40×44 box, the bell centred in it (Tabler only pins an empty
  navbar badge and leaves a count badge in the link's row), so it overlaps the
  corner of the glyph and never pokes out of the open-state box; a wide count
  such as « 99+ » may cover more of the bell. The action row keeps its glyphs centred below `lg`, where
  Tabler otherwise left-aligns collapsed-menu links. On phones the card
  becomes a near-full-width sheet under the topbar instead of a
  trigger-anchored menu that would overflow the viewport.
- Item and "view all" links open the full page (`data-turbo-frame="_top"`), and
  item links opt out of Turbo prefetch (`data-turbo-prefetch="false"`), because
  opening a notification reads it — a hover must never do that.
- An unread row carries a dot, a heavier weight and hidden text; the count is
  text, never colour alone (§18.6).
- The trigger's `aria-label` carries the unread count; the visual badge is
  `aria-hidden`, so a poll cannot cause repeated announcements (§18.8). The
  badge never becomes an `aria-live` region.
- Opening a row reads it and opens the account or decision it belongs to.
  "Mark all as read" is explicit and never happens by opening the dropdown.
- Copy obeys §24: a follow event is "wants to follow you" / "accepted your
  follow request", never "Follow activity"; a deleted account renders as
  "a deleted account", not as an error.
- A completed follow decision removes the corresponding request entry; blocking
  or a deleted remote account removes what that account caused.

### 10.17 Reaction bar

The appreciation control on a publication ([REACTIONS.md](REACTIONS.md)): one row of
compact pills at the foot of a feed card and in the social row under the
figures of the workout or received-note page, never a second visual language.

- **Types.** Bière, boisson énergisante, café, and j'aime, in that order, each
  with a Tabler glyph (`ti-beer`, `ti-bolt`, `ti-coffee`, `ti-thumb-up`) and
  its count. "J'aime" is the neutral type an external peer's plain Like maps
  to. The glyph is never the only name: each pill carries an accessible label,
  an empty pill's tooltip names the action for pointer users, and a populated
  one names who reacted.
- **One at a time.** A signed-in reader who may react sees every type as a
  button; the active type is pressed. Activating the active type withdraws it;
  activating another type replaces it in place. The control is a small
  `button_to` inside a Turbo Frame, so only the bar re-renders and the
  surrounding card never navigates; without JavaScript the request redirects
  back to the target.
- **Who may react.** A signed-in account that can see the publication, never
  its owner. The owner gets the non-zero counts only, as plain pills: a card
  never offers a gesture its reader cannot complete (§2.2), and a withheld
  metric analogue does not exist here — counts are public with the
  publication.
- **States.** No counts and no possible gesture: the bar renders nothing. With
  counts and no gesture: one pill per non-zero type. For a reacting reader:
  every type, counts rendered only when positive. A type nobody chose is a
  ghost pill (icon only, no border); a type with at least one reaction,
  whoever gave it, is emphasised (`--active`: body text colour, stronger
  border, semi-bold count). While the frame submits, Turbo marks it busy and
  the bar dims; a failed request leaves the bar unchanged and does not
  fabricate a count.
- **Who reacted.** A populated pill's tooltip names the accounts that chose
  that type, newest first: up to three names, then « et N autres personnes »,
  and the viewer's own name reads « Vous » and leads the list. On the owner's
  workout the sentence names the gesture and addresses it to them (« Éric a
  trinqué à votre activité »); every other reader reads it on this activity
  (« Éric a trinqué à cette activité »). A deleted, blocked or deactivated
  account is never named and counts among the other people, and neither is a
  reaction given through an audience the reader may not read (a follower's,
  for a reader of the public version); when nobody is left to name, the
  sentence counts people (« Une personne a trinqué à cette activité »). An
  empty pill keeps the action tooltip (« Réagir : Bière »).
- **Press state.** `aria-pressed` on the button; the pressed pill uses the
  brand tint plus the pressed attribute, never colour alone (§18.6), and
  stays distinguishable from the neutral emphasis of `--active`. Focus uses
  the standard visible ring, and every pill keeps the 44×44 touch target on
  coarse pointers (§18.4). The tooltip is the shared Bootstrap tooltip
  (`data-controller="tooltip"`), never a native `title`, so it follows
  keyboard focus and touch.
- **Placement.** In a feed card the bar is the last row of the body and its
  pills are aligned to the right edge, closing the card on the side the
  metric grid ends on; wrapped rows keep that right edge. On the workout and
  received-note pages the bar sits in the **social row** right after the
  summary card (`comments/_social_row`), on every screen and once per page,
  its pills aligned to the right edge. Below `lg` the thread's button leads
  the same row on the left (§10.20), the mirror of a sport app's usual order:
  the conversation first, the appreciation closing the row. The row renders
  nothing when it would hold neither.
- **Copy.** The bar prints type names and counts only; the tooltip adds who
  reacted. The counts are numbers, never protocol terms. A reaction never
  creates a toast: the pressed pill is the feedback, and the owner hears about
  it through the notification bell.

### 10.18 Participants card

The shared-activity control (`[devdoc:shared-activities]`): an owner-only card that
records who else did the workout, and the participant's confirmation surface.

- **Owner card.** A full-width card on the owner's workout page, below the
  publications card. The header carries « Ajouter un participant » (`btn-sm
  btn-primary`), which unfolds the add field; the §19.20 sentence stays
  visible under it while folded. One row per participation: avatar, display
  name and handle, the kind (« Crédit » or « Lien », §4), the state (en
  attente, confirmée, refusée), and the remove action — beside the name from
  `sm` up, under it on phones. The add field accepts a username, a local
  handle, or a remote handle (`@nom@instance`). A local account needs an
  accepted follow in either direction. A remote account (`[devdoc:shared-activities]`) must follow the owner and hold the workout's publication, which must
  share the credited figures. A refused remote invitation answers with the
  §19.20 alert that names those conditions. A refusal by the invited account
  is terminal for that account on that workout, and the card states it
  instead of offering the field again.
- **Kinds.** A *crédit* is the default and the only kind an invitation can
  propose; a participant with their own recording turns it into a *lien* by
  naming that workout — in a select above Confirmer (« Votre enregistrement de
  cette sortie », first option « Aucun : créditez-moi cette activité »), or
  later on a confirmed credit (« Vous avez aussi enregistré cette sortie ? »,
  « Lier mon enregistrement », `btn-outline-primary`). Both lists offer the
  participant's recordings starting within six hours of the source, closest
  first, at most ten, never one already linked; with none, the select is not
  rendered. Done together shows on both workouts (§10.4 Together): the
  source's header and card name its confirmed participants for their owner
  in a single badge that links nowhere, and the recording's own header and card carry the « Avec @X »
  badge linking to the source. Several names join one badge: two are both
  printed, from three on the first and a count (« Avec Eva et 2 autres »),
  the tooltip naming everyone. Participants are live state:
  they never enter a publication.
- **Participant face.** An invited or confirmed participant sees the card on
  the source workout with Confirmer / Refuser (pending) or Retirer
  (confirmed). The card is never rendered to visitors. An account invited
  from another instance sees an « Activité partagée » card on the received
  note instead, after the media and before the comments. It names the owner,
  carries the §19.20 remote sentence, and offers Confirmer / Refuser
  (`btn-primary`, `btn-outline-secondary`) while pending, then Retirer behind
  the shared confirmation dialog. It goes away once refused or withdrawn.
- **Credit row.** A confirmed credit gives the participant an activity of
  their own (`[devdoc:shared-activities]`). Its page carries the sport tile, the
  title, sport and date, the « Avec @X » badge (§10.4 Together, linking to
  the source; grey « Avec @X · activité source supprimée » once the source is
  gone), the credited metric set as summary tiles with the hint
  « Cette activité compte pour vous… » (§19.20), and a `⋯` menu holding only
  « Retirer de mes activités » behind the shared confirmation dialog. The map
  is the source's, read through the publication the participant may read and
  laid out as on any workout page (sticky rail from `lg`), without the
  analysis interplay; with no readable publication, a muted `ti-map-off` line
  replaces it (§19.20). While the credit is attached, a card offers « Lier mon
  enregistrement » with the six-hour recording select. The Analysis card
  keeps only its Segments and « Meilleurs efforts » tabs: the participant's
  own rows, places and trophies. No profile chart (the publication's is
  trimmed at its masked ends while the rows measure the full track), no
  publications, comments, reactions, or participants card. In lists it is an
  ordinary card whose badge group carries the icon-only « Avec @X » badge
  (grey once the source is gone); its image is the
  source publication's, when the participant may read it, and otherwise the
  image area is left out (no pending skeleton). The table view offers no
  selection box for it. A credit from another instance reads the same way.
  Its badge links to the received note, and its map and image are the
  note's while the account may read it. Once the note is deleted, the badge
  turns grey and the route-gone line appears.
- **Detected outings.** A detection is a *lien* both accounts answer, each
  from their own workout's card: the row reads « Suggérée » with Confirmer
  / Refuser for the side still to answer, under the §19.20 suggestion
  sentence; once one side answered, Retirer. A recording's card also lists
  the links naming it (a detection to answer, a confirmed link to withdraw),
  each naming the other account. A pending detection never opens the other
  account's workout and never shows its distance, place or score.
- **Link suggestion.** When a credited participant's own recording of the
  outing is found, an `alert-info` banner sits at the top of that recording
  and of the credit row: « Vous avez enregistré cette sortie », the §19.20
  sentence naming both titles and the date, « Lier mon enregistrement »
  (`btn-primary`) and « Ignorer » (`btn-outline-secondary`), which closes it
  for good.
- **Route suggestion.** When the owner has recorded the same complete route at
  least three times without saving it, an `alert-info` banner sits at the top
  of each of those activities: « Un parcours que vous refaites souvent »,
  « Vous avez fait ce parcours *N* fois, la dernière le *date*. Enregistrez-le
  en itinéraire : chacune de ces activités y comptera comme un effort, avec
  votre record et votre progression. », « Enregistrer en itinéraire »
  (`btn-primary`) and « Ignorer » (`btn-outline-secondary`). The first opens
  the ordinary route form, its name proposed from the departure and arrival
  places and a note stating that the group's activities will be attached;
  saving the route closes the suggestion. « Ignorer » closes it for good, and
  later repeats of the same route join it silently. The banner is owner-only
  and never published or federated.
- **Metrics-only presentation.** When the source is unpublished, the
  participant page renders the credited metric set as summary tiles under the
  header and nothing else: no map, no chart, no analysis, no original data. A
  one-line hint carries the §19.20 sentence. When the source is published to
  them, the standard publication presentation applies and the badge
  « Avec @X » sits on the header metadata line.
- **States.** No participation: the owner sees the header action and the
  sentence; the
  participant never sees the card. Pending: the row is muted with its state.
  Confirmed: full-strength row. Refused: kept on the owner's card with its
  state, never re-invitable. Withdrawn: removed from the active list, and the
  open request notification is withdrawn. Removing a row asks for the shared
  confirmation dialog.
- **Copy.** Sober, like publishing copy: no location, no distance, no score.
  The badge is « Avec @X » in both languages, using display names; a deleted
  account renders as « un compte supprimé ».

### 10.19 Multi-selection and bulk action bar

The desktop bulk workflow on the workout list (`[devdoc:bulk-actions]`). It is a
power feature for the owner's own history: it exists only in the table view,
only from `lg` up, and never in the iOS companion. It changes no single-workout
rule — every action delegates to the service the workout page already uses.

```
┌ carte tableau ────────────────────────────────────────────────────────┐
│ 3 sélectionnées   ☐ Sélectionner les 137 activités filtrées           │
│ Action rapide [ Choisir une action ▾ ] [Appliquer]                    │
│                            [Changer le sport…]  [Supprimer…]          │
├───┬────────────────────┬──────┬─────────┬────────┬────┬───────────────┤
│ ☑ │ Titre              │ Date │ Dist.   │ Durée  │ D+ │ État          │
│ ☑ │ Sortie du matin    │ …    │ …       │ …      │ …  │ …             │
```

- **Selection column.** The table's first column is a checkbox, and its header
  cell is the tri-state page selector (checked when every row on the page is
  checked, indeterminate otherwise). The cell and the column never render below
  `lg`; the row keeps its own link on the title, so a checkbox click is never a
  navigation. Each checkbox carries an accessible name naming the workout.
- **The bar.** A `card-header` above the table, hidden while nothing is
  selected and revealed as soon as a box is checked (CSS `:has()`, enhanced by
  `bulk_selection_controller.js`). It is a single plain form: the checkboxes
  are associated by `form=` so the table markup stays intact, and every control
  is a submit button. JavaScript adds the live count, the tri-state and the
  button enablement; without it the same controls still submit, exactly like
  the list's other forms.
- **Selection scope.** Checking rows selects those rows. When the page does not
  contain the whole filtered result, the bar offers « Sélectionner les N
  activités filtrées » (the list's own filters, replayed by the server). Above
  the 500-workout cap the switch is disabled and the bar says the selection is
  limited and the filters should be narrowed. Selection is never URL state and
  never survives navigation: a new page starts empty.
- **Quick actions.** One select, grouped: Trajet (marquer / ne plus marquer),
  then one Ajouter and one Retirer option per equipment. « Appliquer » runs it
  on the spot and the flash reports how many activities actually changed.
- **Reviewable actions.** « Changer le sport… » and « Supprimer… » open a
  review page (§20.4) instead of applying anything: the exact selection is
  frozen server side, and the page states what will happen, what will be
  skipped, and the mandatory §19 copy. Destructive review is the page, not the
  shared confirmation modal: the decision needs numbers, exclusions and the
  irreversible §19.9 sentence in front of it.
- **Progress.** A confirmed operation has its own page (§20.4): progress bar,
  the four counters (modifiées / ignorées / échouées / annulées, named per
  operation), the per-activity outcome table, cancellation while it runs, and a
  toast on the transition to the terminal state, like the batch import. A
  skipped row always names its reason in plain language (missing original file,
  already deleted…), never an error class.
- **Copy.** Sober and numeric: counts, dates, sports, publication state.
  No federation vocabulary, no "job", no internal identifiers. The bar's count
  is a polite live region; a terminal operation announces itself through the
  existing toast region.

### 10.20 Comments card

The conversation under a publication ([COMMENTS.md](COMMENTS.md)): one full-width card
on the workout page from `lg` up, first of the full-width cards for the owner
(before « Partage » and the participants card), after the participants card
for a participant, last for every other reader (§20.3, §24). Below `lg` the
page carries no card: the thread lives on its own page (see **Phones**).

```
┌ 3 commentaires ────────────────────── [🔒 Fermer les commentaires] ┐
│ (◍) Paul Martin  @paul  Aujourd'hui 14:30                          │
│     Belle sortie ! On y retourne quand ?                            │
│     [↩ Répondre] [🗑 Supprimer]                                    │
│   │ (◍) Marie Dufour  @marie  Aujourd'hui 15:02                    │
│   │     Dimanche prochain.                                          │
├─────────────────────────────────────────────────────────────────────┤
│ Votre commentaire                                                   │
│ [                                                         ]         │
│ §19.21 sentence                                     [ Commenter ]   │
└─────────────────────────────────────────────────────────────────────┘
```

- **Who sees it.** Every reader the publication serves, and the owner. A
  workout that was never published has no card; the owner of a withdrawn
  publication keeps reading the thread with no composer and the line « Cette
  activité n'est plus publiée… ». Nobody else ever sees a thread whose
  publication they cannot see.
- **Thread.** Top-level comments in posting order, each with its replies one
  level down behind a rule. Each comment is the avatar (§9.5), the account's
  display name linking to its profile, its handle (`@marie`, or
  `@user@instance` for another instance, §24 rule 2), the moment as the
  stream's relative day and clock, and the plain text with its line breaks.
  The text never renders markup; long words wrap.
- **Gestures.** One row of ghost buttons under the text: « Répondre » on a
  top-level comment when the reader may write, « Supprimer » on the reader's
  own comment, « Retirer » on someone else's for the owner. Both removals go
  through the shared confirmation dialog (§10.10). « Répondre » opens a reply
  composer under the comment (a Bootstrap collapse) and moves focus into it.
  Every gesture keeps the 44×44 touch target on coarse pointers (§18.4).
- **Composer.** Label, plain textarea limited to 2 000 characters, the
  mandatory §19.21 sentence as its description, and « Commenter » (the
  region's primary action) or « Répondre » in a reply composer. While the
  frame submits, the button reads « Envoi… » and the card dims. A refused
  text comes back in its field, marked invalid with its reason; a success
  re-renders the thread with an empty field. No toast: the thread is the
  feedback, and the owner hears through the bell (§10.16).
- **Withdrawn comments.** A top-level comment that left the thread while
  replies remain becomes a muted italic stub — « Commentaire supprimé par son
  auteur. », « Commentaire retiré par le propriétaire de l'activité. » — and
  disappears with its last reply. The author of a removed comment still sees
  it, muted, badged « Retiré par le propriétaire ».
- **Closed.** The owner's primary ghost header button (`btn-sm
  btn-ghost-primary`) closes and reopens the thread;
  closing keeps every comment. A closed thread replaces the composer with « Les
  commentaires sont fermés sur cette activité. ». When the publication's
  profile closed comments, the button is absent and the owner reads which
  profile did it and that replacing the publication opens them.
- **States.** Empty and open: « Pas encore de commentaire. À vous de lancer la
  conversation. » above the composer. Empty and closed: the closed line only.
  Error: the refused text with its reason (§11.2). There is no loading
  skeleton: the card renders with the page.
- **Received note.** The same card sits on `/remote_notes/:id` (§20.16), above
  the provenance line. The origin hosts that thread: this instance shows what
  it holds — the origin's own comments and replies, and the reader's own
  comments — and the composer carries the received §19.21 sentence. A
  comment the origin refused stays visible to its author only, muted, badged
  « Refusé : les commentaires sont fermés » or « Refusé par le propriétaire »;
  one the origin took out reads « Retiré par le propriétaire ». A remote
  author's words render as their sanitized subset, never as raw markup, and
  nobody here removes them: only the origin hosts that thread.
- **Feed.** A feed card with comments carries the count in the reaction pill
  atom (§10.17), `ti-message-circle` and the number, leading the reaction row
  and linking to the thread's page. No composer in the feed.
- **Phones.** Below `lg` the workout and received-note pages hide the card and
  lead their social row (§10.17) with the thread's button, in the reaction
  pill atom: `ti-message-circle` and the count, or « Commenter » while the
  thread is empty; its accessible name is « Commenter », « Voir le
  commentaire » or « Voir les N commentaires ». It opens the thread's own
  page (`/workouts/:id/comments`, `/remote_notes/:id/comments`): « ‹ Retour à
  « titre » » as the pretitle, « Commentaires » as the title, then this card
  alone with every gesture it carries on the workout page. The page serves
  exactly the readers the card serves, on every screen, and answers 404 to
  anyone else; a reader reads the publication's title, never the workout's.
  The feed's count pill and the comment notifications open that page too.
- **Mechanics.** The card is one Turbo Frame; every gesture re-renders it and
  works without JavaScript by returning to the thread's page.

### 10.21 Heart-rate zone bar

The time a recording spent in each of the five heart-rate zones
(`[devdoc:heart-rate]`), in the « Zones cardiaques » tab of the owner's
analysis card only.

- **Shape.** Tabler's stacked `progress progress-separated`, 1.5 rem high,
  one `progress-bar` per non-empty zone, width = its share of the sampled
  time, the zone number printed inside from an 8 % share.
- **Colour.** The five steps of the calendar's primary ramp (§15.3), Z1 the
  palest and Z5 the full primary (`.allure-zone-1` … `.allure-zone-5`), solid
  mixes against the sunken surface so both themes read alike. Never a new hue,
  never a traffic-light scale. The same swatch leads each table row and the
  zone table of `/settings/heart-rate`.
- **Accessibility.** The bar is one `role="img"` whose name lists every zone
  with its name, time and share; the table that follows (zone, name, bpm
  range, time, share) is its text equivalent. Colour never carries the zone
  alone.
- **Where.** A zone row is an analysis row (§20.3): hovering, focusing or
  pinning it shades every stretch ridden in that zone, in the ink band on the
  profile and the ink slice on the map, at once. Stretches closer than 50 m
  are joined and slivers under 20 m left out, so a heart rate wavering on a
  threshold reads as one stretch.
- **Basis.** One muted line above the bar names how the zones are computed
  (« Zones en pourcentage de votre fréquence maximale (190 bpm). ») with
  « Modifier mes zones » to `/settings/heart-rate`.
- **Coverage.** Coverage is read against the time the device recorded, pauses
  excluded (`[devdoc:heart-rate]`), so a paused timer never reads as a
  lost strap. Under 95 %, one muted sentence under the bar says how much
  carried a heart rate and that zones and load cover that time only. Frozen
  values left out are named with their duration; a heart-rate finding of the
  anomaly pass points to « Qualité des données ».
- **Unusable.** Under 50 %, or with points too far apart, the tab stays and
  says why in one sentence, with no bar, no table and no badge count — never
  a tab that silently disappears.
- **Load.** Under the table: « Charge de la séance : N points », the method in
  one muted line, the time under the load floor, and, under 95 %, that the
  time without heart rate counts nothing.
- **Names.** Récupération, Endurance, Tempo, Seuil, Maximal (Recovery,
  Endurance, Tempo, Threshold, Maximum); ranges read « < 114 bpm »,
  « 114–132 bpm », « ≥ 171 bpm ». `/settings/heart-rate` adds one line of
  description under each name, and its table follows the form as it is typed.

---

### 10.22 Workout photos

The owner-only Photos card (`[devdoc:photos]`) follows the analysis
and weather, before comments, full width. It also appears on manual entries,
never credit rows or a reader preview. It is a glance, not a workspace: the
header carries the count (« Photos · 3 »), « Ajouter des photos » (the picker)
and « Gérer » (the manager, §20.24); the body carries the §19.34 line, a
compact intake zone and a square grid of the same thumbnails readers see. The
whole card accepts a drop, and the obvious refusals — too large, wrong type,
no slot left — are answered before anything is sent. Each file has its own
progress and error; a completed row leaves the list, since its tile is the
confirmation. The quota appears only from 80 % of the account's storage. The
gallery polls only while a photo is processing, leaving the upload picker
undisturbed, and refreshes by morphing the frame so an open viewer survives.
Empty, processing, failed (Retry/Delete) and ready states are explicit.

Clicking a thumbnail opens a native dialog on a dark surface in both themes:
the image fits without cropping, the caption is visible and supplies its alt
text, a counter names the photo's place in the set, and the second line gives
the capture time and the distance along the route when the gallery has them.
Previous/next buttons, arrow keys, swipe and Escape work, focus returns to the
opener, and « Voir sur la carte » closes the viewer and flies the map to the
same photo's marker. An original-download link and « Modifier » (the photo's
row in the manager) are owner-only. Caption editing, ordering and placement
live on the manager, never in the lightbox. All listeners, pending uploads and
object URLs are released on Turbo disconnect.

**On the route** (recordings with a track only). The manager (§20.24)
names each photo's placement in one muted pin line — how it was placed
(« Placée d'après la position GPS de la photo », « … l'heure de la prise de
vue », « Placée par vous », « Hors du parcours », « Position retirée par
vous ») and the distance along the route — and offers « Placer sur le
parcours », « Retirer la position » when placed, and « Placer automatiquement »
once the owner took over. « Placer sur le parcours » scrolls the map into view
and arms it, framing it with a dashed primary outline and a crosshair. The map
itself carries the instruction (« Cliquez sur le parcours pour placer
« Légende ». ») and a « Annuler » button; a click too far from the line is
refused in the same place, leaving the map armed for the next try. Échap
cancels too. A camera-clock correction field (minutes) shows once a photo
carries a capture time; it says what moves (time-placed photos) and what
stays (the owner's).

The owner's map draws each placed photo as a 36 px round thumbnail with a
primary ring; thumbnails closer than one marker share one, with the first
photo and a count badge, and clicking a group zooms until it splits. The
owner's profile draws a camera pill per photo along the top of the plot, on
the plot's scale. Every marker and pill is a labelled button opening that
photo in the card's lightbox; the card's tiles stay the text equivalent.
Nothing of this renders for a reader, a reader preview or a publication.

**Published**. The publish and replace forms carry the photo
choice (§19.35) only when the selected profile shares photos: a grid of ticked
thumbnails, the sensitive ones unticked and badged. A profile that shares none
gets « Ce profil ne partage pas les photos. » and a link to the profiles
instead of ticks that would share nothing. The §19.1 shared / not-shared lists
name « Photos », « Légendes des photos » and « Position des photos sur le
parcours ». A reader — and the
owner's reader preview — gets a read-only « Photos » card (count in the
header, the same grid and lightbox, no original, no form) before the
comments, thumbnail markers on the published map where distances were
shared, and no profile pills. Feed and profile cards show the first three
thumbnails in a strip under the route image, with a « +N » pill beyond three.

### 10.23 About dialog

One dialog (§10.9) for signed-in members, rendered once by the application
and administration layouts (`shared/_about_modal`), opened from the account
menu's « À propos » entry (bridge item `about`, so the companion's native menu
opens it too, icon `info-circle`) and the footer's meta line. It loads
nothing when it opens. Four blocks, in order:

- **Cette instance** — name, domain, description, host and the operator's
  handle (linking to their profile), each line absent while unset, like the
  footer (§7.5).
- **Services utilisés par cette instance** — only the outside services the
  operator switched on (`AboutHelper#about_services`): maps, place names,
  terrain elevation, weather, the push relay, identity providers, connected
  import services, other instances. Each line says in plain words what
  reaches the service and names its hosts, so a member sees where their data
  may go; an opt-in service says « si vous l'activez ». Never protocol words.
- **Logiciel libre** — the AGPL in one sentence and « Code source », the
  instance's `ALLURE_SOURCE_URL` (the upstream repository by default: an
  instance running modified code points it at its own), then Help, API and
  the operator documentation.
- **Crédits** — the attributions the data owes (OpenStreetMap, OpenFreeMap,
  Open-Meteo while weather is on) and the main free software.

### 10.24 Language switcher

Signed-out pages only, in the authentication layout (`layouts/
_language_switcher`): a small ghost dropdown beside the theme toggle, its
button showing the `language` icon and the current language, its menu every
offered language **named in itself** (Français, English, Deutsch, Español,
Nederlands — the `settings.appearance.locales` names, identical in every
locale file), each item carrying `lang` and `hreflang`, the current one marked
`aria-current`. Choosing one reloads the same page with `?locale=`, which the
application remembers in the browser for a year. It is absent for a signed-in
account, whose language is the Appearance setting, and in the iOS companion,
whose web view already sends the phone's languages.

A signed-out page's language is, in order: `?locale=`, the switcher's choice,
the browser's best supported Accept-Language, then English — a visitor whose
language is not offered more likely reads English than French. An account
created from the registration form starts in the language it was read in.

### 10.25 Paged panels

A selector over whole pages, one page visible at a time, shared by the public
profile's statistics and records (§20.14) and the owner's records page (§20.8):
Tabler sport pills or a `nav-segmented` control above, the pages below in a
native scroll-snap strip. The `paged-panels` Stimulus controller owns it.

- **Selection:** native radios, one checked, arrow-key navigation free; a pill
  always reaches its page without a gesture. The selected pill follows a
  completed swipe, and a polite status names the page.
- **Pages:** one page per choice, each the full width of the strip
  (`grid-auto-columns: 100%`); this pages whole pages and never horizontally
  scrolls their columns (§12). Only the selected page is focusable and
  exposed; the others are `inert` and `aria-hidden`. A single choice has no
  selector and no swipe hint.
- **Heights:** by default every page keeps the tallest one's height, so
  changing pages never moves what follows — the profile's rail. A page that
  owns its whole card (the owner's records page) fits the selected page's
  height instead (`data-paged-panels-fit-value="true"`), so a short page leaves
  no blank space; a taller inactive page is clipped until the swipe settles.
- **Without JavaScript** the selector is hidden and every page remains readable
  in sequence; Turbo teardown releases the resize observer and the pending
  scroll callback and restores that baseline before caching.

---

## 11. The four states

Every list, table, card, map, chart and asynchronous surface documents four
states. A surface with fewer is incomplete.

### 11.1 Loading

**Skeletons for content shapes; spinners only for canvases.**

- Lists, tables and cards render a skeleton matching their real shape — same row
  count where known, same column widths. Never a centred spinner in a card that
  will contain a table.
- The map and elevation chart keep their current spinner-in-overlay treatment:
  their content has no predictable shape to skeletonise.
- Skeletons animate only for users without `prefers-reduced-motion`; otherwise
  they are static muted blocks. Tabler's `.placeholder`/`placeholder-glow`
  blocks are the primitive: the animation is already disabled under
  `prefers-reduced-motion`, and every decorative block is `aria-hidden` while a
  `role="status"` sentence carries the meaning.
- Anything expected to take over ~2 seconds also states what is happening
  ("Analyse du fichier…"), because an unexplained skeleton reads as broken.

### 11.2 Error

Icon, what failed, why if known, and a retry action. Never a raw exception, a
status code, or a class name.

- A component-level failure degrades that component only: a failed chart never
  blanks the workout page.
- The map's existing behaviour is the reference — a failed basemap keeps the
  themed grid background and still draws the track.
- Errors are announced to assistive technology via the component's live region.

### 11.3 Partial

A distinct, named state for "this worked, but not completely":

- a workout with no elevation data (chart absent, map colouring falls back;
  the owner's summary names the cause and the one corrective action);
- a trailing partial split, flagged rather than padded or dropped;
- a batch import that finished with some failed entries;
- equipment totals that have drifted and need a refresh;
- a segment candidate that produced no effort because the interval spans a
  recording gap — [SEGMENTS.md](SEGMENTS.md) makes explaining this a UI
  requirement, not a silent omission.

Partial states use the warning colour, explain the cause in one sentence, and
offer the corrective action where one exists.

### 11.4 Empty

Two distinct kinds, never conflated:

| Kind | Voice | Action |
|---|---|---|
| **Never populated** | playful | the one action that populates it |
| **Filtered to nothing** | neutral | clear the filters |

Examples:

- Never populated, workouts: *"Rien ici pour l'instant. Importez un GPX et ça se
  remplit vite."* → `Importer une activité`
- Filtered, workouts: *"Aucune activité ne correspond à ces filtres."* →
  `Effacer les filtres`

An empty state names exactly **one** next action. Two actions means the design
has not decided what the user should do.

---

## 12. Tables and responsive data

M3 adds many tabular surfaces. One rule governs all of them.

### 12.1 The priority-column rule

Every table declares an ordered column priority. Above the breakpoint, all
columns render. Below it, the table becomes a **list of stacked cards**: the
priority-1 column is the card title, priority-2 and 3 are the card's primary
values, the rest move into a secondary line or are dropped.

The breakpoint is `md` (768px) unless the table has three or fewer columns, in
which case it stays a table at all sizes. The workout analysis card is the
exception: it sits in the narrow right column of the desktop layout, so its
tables switch on the card's own width (a 36rem container query) and keep the
dropped columns of §12.2 for cards at least 56rem wide. Its stacked rows are
compact: the title and time, then every secondary value on one wrapping line.

Horizontal scrolling is not used. Scroll-hunting on a phone is worse than a
different layout.

### 12.2 Declared priorities

| Table | 1 (title) | 2 | 3 | Secondary | Dropped below `md` |
|---|---|---|---|---|---|
| Segment efforts | segment | time + gap to personal best | distance | pace/speed (power for a power-led ride), D+/D− | date, deviation, HR, cadence, power |
| Detected laps | source + name | time | distance | pace/speed (power for a power-led ride), D+/D− | HR, cadence, power |
| Recorded laps | lap number | time | distance | pace/speed (power for a power-led ride), D+/D− | HR, cadence, power, trigger |
| Climbs | climb number | time | distance | D+/D−, avg grade, max grade, VAM | HR (power stays for a power-led ride) |
| Descents | descent number | time | distance | D+/D−, avg grade, max grade, descent rate | HR |
| Stops | stop number | time | distance | D+/D− | HR |
| Efforts | source + number | time | distance | pace/speed (power for a power-led ride), D+/D−, avg power | HR, cadence |
| Splits | split number | time | pace/speed (power for a power-led ride) | D+/D− | — (partial flag stays on the title) |
| Leaderboard | rank (laurel + numeral for the top three) + name/alias | time | date | speed/pace | — |
| Records | record type | value | date | — | sport (it is the page heading) |
| Best efforts | distance | time | date | personal-place trophy (gold record, owner's silver/bronze), hover range | sport (it is the page heading) |
| Workout list | title (with sport, commute, place) | date | distance | duration, state badge | D+ |
| Equipment | label | total distance | workouts | type, active state | total duration |
| Import entries | file name | status | sport | error message | path, distance |
| Active sessions | device / user agent | last seen | IP | — | — |
| Publishing profiles | name (audience, built-in, unavailable badges) | active publications | — | — | — |

The workout list's leading selection column (§10.19) is outside the priority
system: it is a control column that exists only in the table view from `lg` up.

The analysis tables share one column vocabulary: the sport-preferred pace or
speed (`pace_speed_display`; `pace_and_speed` adds the speed as a quiet
secondary), the grade-adjusted pace for qualifying sports as a quiet second
line labelled `GAP` under the pace, D+ and D−, then source-specific columns
(grade, VAM, descent rate, deviation, trigger), then HR, cadence and power. A
secondary column renders only when at least one row of that table carries the
value.
The segment efforts table follows the time with « vs RP »: a slower effort
shows its gap to the owner's personal best on that segment and sport, muted
(`+8 s`, `+1:12`); the record shows its margin over the second best time in
the success colour (`−8 s`); a first effort shows `—`. Derived on read
(`Segments::PersonalBestGaps`), owner-only, never published. The stacked row
prints the same value beside the time. The GPS deviation is match quality,
not a figure for the athlete: it is a wide-card column only.
A sport with a fixed pace basis (`pace_basis_metres`, rowing's 500 m) renders
its pace over that distance (`m:ss /500m`, in either unit system) and never
shows speed, in every cell and tile; its summary tiles prefer average power
when the file recorded it. Records and stats follow the same basis through the
shared formatters. See [WORKOUT.md](WORKOUT.md).

A **power-led virtual sport** (`Sport#power_led?`: `cycling_virtual`) leads
with average power in place of its speed when the recording carries it, in the
summary tiles, the activity card, the chart's default secondary line and the
analysis tables' effort column: the platform's speed is a game output, the
watts are the athlete's effort ([VIRTUAL-PLATFORMS.md](VIRTUAL-PLATFORMS.md)). The fourth tile stays the
elevation gain; speed keeps its place in the secondary metrics, the tables'
quiet second line and the chart selector. A publication whose profile withholds
power, and the credited metric set, fall back to speed.

The effort column's header names what its cells print — *Allure*, *Vitesse* or
*Puissance moyenne* — instead of the fixed *Allure*. A power-led ride's tables
drop their separate power column; the climb table keeps it and shows it on
phones too. Each split carries its own average power, the same sample mean as
the recorded and detected laps.

### 12.3 Card-mode anatomy

```
┌────────────────────────────────────┐
│ Tour 3                    12:04    │  priority 1 + 2
│ 3,21 km · 4:12 /km                 │  priority 3 + secondary
│ ↑ 42 m                             │  secondary
└────────────────────────────────────┘
```

The card mode is a `<ul>` of `<li>`, not a table with `display: block` rows —
so screen readers get a list, not a broken table.

---

## 13. Filtering, sorting and URL state

### 13.1 Everything is a URL parameter

Filters, sort field and its direction (one value, §13.2), page and view mode
are query parameters.
Consequences that make this worth the discipline: the back button works, a
filtered view is shareable and bookmarkable, Turbo caching is correct, and
pagination cannot silently lose a filter.

No filter state lives in `localStorage`, session, or a Stimulus value that is not
reflected in the URL. One display preference is the exception: the
**card/table view toggle**, which may persist in `localStorage` — but it is
still reflected in the URL when set explicitly, so a shared link keeps its
shape. The filter drawer (§10.6) is never remembered open.

### 13.2 Workout list filters

Sport (multi-select pills over the account's own sports, most practised first
with counts), date range (preset + custom), publication state (all / published
/ not published), commute, free text over title and description, recorded place
(autocomplete over the owner's place names), and sort. The period presets are
the hub's calendar windows (§8.4) — this week, the last 30 days, this year,
any time — plus the custom range, so `/me` and the list always agree on what a
period means. The sort is one `sort` value combining field and direction
(`date_desc`, `date_asc`, `distance_desc`, …), written both by the sort select
and the table headers (§10.5).

### 13.3 Interaction rules

- Toolbar selects and toggles apply on change; the drawer's filters, text
  included, apply on its submit button (§10.6). A text filter never reloads
  the page while the visitor types.
- The **place filter** is a combobox over every place the owner's workouts
  recorded — the displayed places and the markers beyond them — not only the
  three a workout shows. Its suggestions are fetched on focus and while typing
  (debounced, ≥300ms, ten names by frequency) from the owner-only
  `/workouts/place_suggestions` endpoint, which returns names only; the field
  applies on selection or submit, never on input, so the list survives the
  keystrokes. It matches a case-insensitive substring of any recorded place
  name, arrow keys move the active option, Enter selects it or submits the
  typed value, and Escape closes the list. The list is a Tabler `dropdown-menu`
  with `dropdown-item` options and a `dropdown-header` empty state, so its
  surface, dark mode and option states are Tabler's own. Without JavaScript the
  field is an ordinary text input of the same GET form.
- The result count updates in a live region.
- Active filters render as removable chips; each chip's remove button is
  labelled with the filter it removes, not just "remove".
- A "clear all" appears only when at least one filter is active.
- Filtering never changes the sort, and clearing filters never changes the page
  size.
- **Only the view switch changes the view mode.** Filtering, sorting, clearing
  the filters and paginating all preserve it: the filter bar's one GET
  form carries the mode as a hidden field, and every link the page generates
  (chips, clear-all, the filtered empty state's action, table headers, the
  `<noscript>` pager, the endless-scroll next URL) round-trips it. A visitor who chose the
  table stays in the table until they choose otherwise.
- **Selection is not filter state.** The bulk selection (§10.19) lives in the
  rendered checkboxes only: it is not a URL parameter, never survives
  navigation, and the alternate « select all filtered » scope travels in the
  request, not in the address bar.

---

## 14. Forms and validation

### 14.1 Structure

- **Labels are always visible.** A placeholder is never a label. Placeholders
  show format examples only ("48,8566"), and many fields have none.
- Help text sits under the label, above the input, when it is needed to fill the
  field correctly; under the input when it is a consequence or a caveat.
- Required fields are marked; optional fields are marked instead when most
  fields are required — whichever set is smaller.
- Related fields group into `card` sections with headings; long forms
  (publishing profile, privacy zone, equipment) use one card per concern.
- `form-footer` carries the actions: primary submit first in the markup,
  cancel next to it, destructive actions never in the footer. From `md` the
  group sits left with the primary left-most; below `md` it sits right with the
  primary right-most (§10.3, action groups).

### 14.2 Validation

- Server-side validation is authoritative. Client-side checks are conveniences
  and never the only barrier.
- Errors render **both** inline (`is-invalid` + `invalid-feedback`, tied by
  `aria-describedby`) **and** as a summary alert at the top of the form listing
  each error as a link to its field.
- On submit failure focus moves to the summary alert, which is
  `role="alert"`.
- Validation messages say what is wrong and what is acceptable: *"Le rayon doit
  être compris entre 1 et 10 000 mètres."*
- Field-level validation on blur is permitted; validation on every keystroke is
  not.

### 14.3 Unsaved changes

A settings form holds entries the server has not seen until its submit, so
leaving the page would drop them silently. The guard is the dialog alone: a bar
pinned to the bottom of the viewport was tried and removed, because it competed
with the on-screen keyboard on a phone and made every form page heavier while
each form already carries its own submit at its end.

**The dialog.** A link, a reload, a closed tab, or another form's save that would
replace the page asks before it happens. The form's own save never asks, and
neither does a Turbo Frame submission, which leaves the rest of the page and its
entries alone. The dialog is the §10.10 anatomy with its verb and style swapped
by context — « Quitter », destructive, for a navigation; « Enregistrer »,
primary, when the entries are kept — and « Annuler » focused on open. Its
wording is the companion's own « Quitter cette page ? » / « Les informations
saisies ne seront pas enregistrées. », so both surfaces say the same thing.

Rules:

- **"Changed" is measured against the server.** Every named field is compared
  with the value the page was rendered with, so undoing an edit makes the form
  clean again. Hidden and password fields are never read; an unnamed control — a
  map's search box, a zoom slider — is a way to fill the form in, not part of
  what it submits, and is ignored.
- **Nothing follows the fields while typing.** The check runs when the page is
  about to be left, never on every keystroke, and no surface is pinned to the
  viewport: the guard costs nothing on a page a reader is only filling in.
- **Every form that saves is covered**, not a curated list. A form opts out with
  `data-unsaved-changes="off"` when its fields hold a transient choice rather
  than work — today the workout list's bulk selection. A GET form is a filter or
  a search: navigation, never entry.
- **A re-rendered form is unsaved.** A validation summary carries
  `data-unsaved-changes="forced"`, and an invalid field its `is-invalid` class:
  the server rendered the submitted values back as the new defaults, so the
  dialog stays active until the form is saved.
- **A save is never mistaken for leaving.** A submitted form stops counting as
  unsaved until the page changes, so its own redirect passes without a prompt.
- **Back never shows an unsaved choice as saved.** Turbo caches the page it
  leaves with the fields' current values; the cached copy is reset to the
  server's values. A form carrying a validation summary keeps its state, since
  its errors belong to the values it shows.
- **Two gaps are deliberate.** Native Back and the edge swipe never reach the
  page, so the companion's own unsent-work check covers the tab return and a
  native Back guard remains to be added there; and a Turbo Frame reloading over
  a form being edited is not covered, because the live-frame pattern already
  stops while a form is being filled in.

### 14.4 The privacy zone map picker

Typing latitude and longitude by hand at five decimal places is unusable and it
is a safety problem: a mistyped digit silently fails to mask a home address.

The zone editor is a map, preceded by a place search:

```
┌──────────────────────────────────────────────┐
│  Rechercher une adresse ou un lieu           │
│  [ Rue, ville, lieu…        ] [ Rechercher ] │
│  ▸ résultats (listbox, 5 au plus)            │
│  [ map, 24rem ]                              │
│      ◎  draggable centre marker              │
│     ( ) radius circle, live                  │
├──────────────────────────────────────────────┤
│  Nom (optionnel)  [                       ]  │
│  Rayon            [====●======] 250 m        │
│  Latitude  [48,85661]  Longitude [2,35222]   │
└──────────────────────────────────────────────┘
```

Rules:

- dragging the marker updates the numeric fields; editing the numeric fields
  moves the marker. The numbers are never hidden — they are the accessible,
  keyboard-operable equivalent of the map, and they remain the source of truth
  on submit;
- the radius is a slider **and** a number input, in metres, bounded 1–10 000 to
  match the model;
- the circle is drawn in the warning colour at low opacity, so it reads as
  "protected area", not as a route;
- **no geolocation control.** Asking a user to click "find me" to place a
  privacy zone is exactly the wrong instinct, and `[devdoc:maps]` already
  excludes `GeolocateControl`;
- the place search is the deliberate alternative: the owner types an address,
  picks one of at most five results, and the marker, the fields and the map
  move to it (zoom 16) for a manual check. It runs only on Enter or the
  button, never per keystroke — the public Nominatim usage policy forbids
  autocomplete — and goes through the owner-only
  `GET /settings/privacy-zones/search`, which asks the instance's
  `GEOCODING_BASE_URL` provider (30 searches a minute per account, no cache,
  the `privacy_zone_query` parameter filtered from the logs). The browser
  never contacts the provider. The search is absent while geocoding is not
  configured and hidden without JavaScript. Under the field: « La recherche
  est transmise au service de géocodage de l'instance ; seul le point choisi
  est enregistré. » / "The search is sent to this instance's geocoding
  service; only the point you choose is saved.";
- the map is an enhancement: with JavaScript unavailable, the numeric form still
  works and still validates.

---

## 15. Data visualisation

### 15.1 Charts

Apache ECharts only (SVG renderer, `[devdoc:charts]`). No second charting library.

| Dataset | Chart |
|---|---|
| Workout profile | elevation area in primary, optional secondary line |
| Course (segment) profile | elevation area in primary, single series |
| Course progression | the viewer's own efforts over time: one point per effort, the three best times as their gold, silver and bronze trophy, a thin muted trend line (dotted where it rests on too few outings), a reversed time axis (faster reads higher), no legend, chronological table as the equivalent |
| Speed / pace over distance | line on the configurable secondary axis |
| Stats by time — totals | column |
| Stats by time — trend | line, overlaid on the column when comparing |
| Stats by sport | horizontal bar, one bar per sport, identified by its label |
| `/me` intensity pulse | a mirrored weekly waveform over the whole history — one capsule per week around a baseline, height and tint both carrying the 0–100 score, rest weeks as muted dots, the selected period in the primary ramp and the rest of the history in a grey ramp — X labels, a "week · score / facts" tooltip, a peak named by the reading line below, navigation buttons and an explanatory ⓘ hint |
| `/me` sport mix | donut, one slice per sport, legend at its side, primary shade ramp |
| `/me` training load | the last 90 days of every sport (`[devdoc:heart-rate]`): fitness as a primary line over a light primary area, fatigue as a thin muted line, form as faint muted bars around zero on the same axis, a legend naming the three; above it the three figures of today (form signed), a short ⓘ hint naming the method and the unit as Allure's own, the first six weeks of the history shaded when they fall in the window (with a sentence), the counts of sessions without and with partial heart rate, « Comment lire ces chiffres » folded, and a table per calendar week of the account behind « Voir les données », the unfinished week marked. Shown once a recording carries usable heart rate; without a heart-rate profile, the invitation to set one |
| Heart-rate zones per period | `/me/stats/heart_rate`: an introduction naming the zones' basis with « Modifier mes zones »; one stacked column per week (last 26) or month (last 24), in hours or in shares of each period (« Heures » / « Répartition »), Z1 at the foot, the zone ramp of §10.21, empty periods kept on the axis; the hub's toolbar (§8.4) — from `md` the sport pills with each sport's recordings with heart rate in the window and « Semaines » / « Mois » as a segmented control, on phones one row of two native selects — while « Heures » / « Répartition » sits in the chart card's header (§10.15, a native select on phones); a three-figure strip low / moderate / high (Z1–Z2, Z3, Z4–Z5) with a landmark-not-prescription hint; a table of the periods that hold heart rate, newest first, in time or in shares, and on phones a list of the same periods, each with its total, a thin zone bar and the five values; on a phone-wide chart the legend names the zones by number |
| Activity calendar | not a chart library — a CSS grid (§15.3) |

Rules:

- **Primary for the primary series.** Multi-sport charts label each series by
  sport name; the elevation area is primary. Where two series must be told
  apart, use an explicit label or pattern, never an invented hue or a sport
  colour.
- **Minimal chrome**: horizontal gridlines only, no vertical gridlines, no chart
  border, no drop shadow, no 3D, no donut with a decorative centre.
- **Elevation axes are never truncated to exaggerate a climb.** The y-axis
  starts at a rounded value at or below the minimum, and the range is shown.
- The workout profile gives the plot the card's whole width. Its y axes float
  over the plot and reserve no label column: only the top value of each axis
  is printed, with its unit, inside the plot's top corners (elevation at the
  left, the secondary metric at the right; a reversed pace axis prints its
  fastest value), and dashed horizontal gridlines carry the rest. Both axes
  snap to round steps (50, 100, 150 m — never 117 or 183; pace on the clock),
  bounded on the 2nd–98th percentile of the secondary readings so a stop never
  flattens the line. The legend names the series only when there are two; the
  y axis requests at most four intervals on phones, five on larger viewports.
- The distance axis ends exactly at the workout distance, so the profile
  touches the axis edge with no trailing blank. Its ticks are whole
  kilometres (or miles) at a round step (1, 2, 5, 10…), placed at their true
  distance on the plot's own scale — never tenths, never evenly spaced
  decimals — and recomputed on every redraw and zoom.
- The profile opens fitted to the whole activity and zooms by selecting a
  range: a mouse drag on desktop, or on a touch screen a press held still for
  a moment then dragged (a drag that starts at once still scrolls the page).
  While zoomed, a « Vue d'ensemble » button over the plot's top-right corner
  returns to the fitted view; the markers are redrawn after every zoom. There
  is no zoom button pair and no detailed (wider-than-the-card) view.
- On an owner workout page, elevation occupies the left axis when available.
  One optional secondary series occupies the right axis: sport-appropriate
  speed or pace, heart rate, cadence, or power. It is a thin (1.25 px),
  muted grey, slightly transparent solid line — a trend under the profile,
  told apart from the elevation area by its shape and its legend entry — and
  it is drawn display-smoothed over a window that follows the plotted span
  (about 1 % of it, 1/60 on phones, never under the map's medium window,
  `[devdoc:maps]`): same point count, gaps preserved, run endpoints
  fixed. The tooltip and the data table keep the recorded values, so the
  trend is a drawing and the numbers stay data. The selector is absent
  from non-owner pages; detailed point signals remain owner-only until the
  publication privacy filter preserves source-point provenance. A power-led
  virtual ride ([VIRTUAL-PLATFORMS.md](VIRTUAL-PLATFORMS.md)) opens on its power; the selector keeps the
  speed, and its stored choice is kept apart from the other charts' so neither
  kind overrides the other's default.
- A profile with no elevation may still show an available owner-only secondary
  series; drawn alone, it takes the primary colour and the normal stroke.
  Missing readings are never converted to zero: a sensor's short hole (up to
  100 m or 2 % of the plotted span, inside one recording segment) is bridged
  for the drawing only, while a longer hole or a recording gap stays a gap and
  the tooltip keeps the recorded value or « — ».
- A **course profile** is a single frozen elevation area: no secondary axis, no
  selector, no toponymic route story. It follows the course's own visibility
  like its map, and a course without a stored profile shows the unavailable
  state instead of an empty chart.
- **Every chart has a text or table equivalent** reachable from the same card
  (§18.7) — a disclosure containing the underlying values (on the workout
  profile, a « Voir les données » disclosure from `md` up and a
  screen-reader-only list on phones), or, for the `/me`
  pulse whose weekly history spans years, the screen-reader table and
  keyboard cursor defined below.
- Tooltips are keyboard-reachable, or the equivalent data is in the table.
- **A floating popup wears one surface.** Bootstrap tooltips, every ECharts
  tooltip (`.allure-echarts-tooltip`), the pulse and calendar **selection
  callouts** and the Découvrir map's course bubbles (§20.6) all take Tabler's
  inverted surface — dark on the light theme, light on the dark one — and its
  muted ink (`--allure-text-inverted-muted`), never the page's own surface, so
  a hover and a click read as the same object. A selection callout keeps the
  card's stacking shadow and its arrow; its one action is tinted for that
  surface (`light-dark()` flipped pair), not with the theme's link colour. The
  `allure-floating-surface` mixin (`components/_map.scss`) carries the three.
  A popup inside a map inverts the **map's** theme (§15.2), which may not be
  the page's.
- The chart re-reads its foreground colour on `allure:theme-changed`, as
  implemented today.
- Chart animation is retained (§16) but disabled under `prefers-reduced-motion`.
- The `/me` **intensity pulse** is a weekly waveform over the whole history,
  read like an audio waveform: every week is a capsule mirrored around a
  baseline, and height and tint both carry its score — the strongest week is
  full primary, a light week a pale nuance of it (the calendar ramp's logic),
  a rest week a muted dot on the baseline — so the rhythm of a history, and
  the gaps in it, read at a glance. The waveform is always weekly and spans
  the whole history: the selected period is the only thing that moves, its
  weeks keeping the primary ramp while the rest of the history takes a
  neutral grey ramp, so switching windows never redraws the shape. A week is
  highlighted when it overlaps the period, so the week carrying the period's
  first days is included and the current week is always pink. The score
  (`Allure::Stats::Intensity`) is the mean of the week's moving time,
  distance and ascent, each as a share of the history's strongest week for
  that component, rescaled so the strongest week is 100; a component nobody
  ever recorded is left out. Drawn height is compressed (square root) so a
  quiet week stays visible beside an exceptional one, while the tooltip and
  the values table keep the linear score. Capsules never exceed 28 px nor
  60 % of their slot, end in true half-circles, and the X axis prints one
  label per ~90 px, the year on the first week of each year. The period's
  peak is named below the waveform only: the reading line carries its facts
  (*Pic : semaine du 14 septembre · 2 activités · 67,1 km · 767 m ·
  2 h 51 min*), even when the peak sits in an older fetched window, or says
  that the period holds no activity. When the period spans a single week
  (*Cette semaine*, or a one-week history), the wording drops: the line
  prints the week and its facts alone, since a peak of one is not a peak. No
  *Pic* mark is drawn on the chart, so the capsule field stays uninterrupted. The active-week count (*4 semaines
  actives sur 5*) sits at the label row's end. The waveform is wider than the
  card: the newest window is anchored at the right, `‹`/`›` page by a window,
  an *Aujourd'hui* button returns to the present, and older years load as the
  viewer reaches the left edge. Every fetched window is scored against the
  same whole-history basis, so the shape already drawn never changes. The
  tooltip reads "week · score" over the facts line, every string formatted by
  the server in the viewer's units and locale. A week that mixed sports says
  so without widening its capsule: from the second sport on, the facts line
  adds *2 sports* (tooltip, reading line, screen-reader table and keyboard
  announcement). Every week is a **selection target**, never a link (the
  select-then-open rule of §18.4): a tap or click anywhere in a week's full
  column — not only on its capsule, and rest weeks included — selects it,
  draws the dashed cursor, and opens that week's **selection callout** over
  the card, pointing at the week (*Semaine du 21 septembre · 26 % · 5
  activités · …*) with one **Voir les 5 activités** button to the workouts
  list filtered to that week
  (`/workouts?period=custom&from=…&to=…`), carrying the page-level sport
  filter exactly like a calendar day (§15.3); a week holding a single
  activity opens that activity itself (**Voir l'activité**), never a one-row
  list. A rest week shows *Repos* and no button. The button exists only for
  a week the viewer chose: with no selection the line names the peak as
  information, with no button and no gesture hint. Tapping the selected week
  again, the callout's ✕ or Escape closes the selection. A
  **long press then slide** scrubs the selection week by week under the
  finger without scrolling; a swipe that moves before the press settles
  scrolls the history and selects nothing. The keyboard cursor is the same
  selection, and its Enter key opens the selected week. The floating tooltip
  follows a hovering mouse only; touch screens read the callout.
- The pulse remains equal without colour: the screen-reader values table
  lists every week of the selected period (week, score, facts) and the chart
  container takes focus, the arrow keys walking the loaded weeks and
  announcing each week's state (*Dans la période* / *Hors période*), score
  and facts through a polite live region. This keyboard cursor plus the
  hidden table is the deliberate exception to §18.7's visible disclosure: a
  multi-year weekly history would print a table nobody reads.
- The pulse carries one explanatory ⓘ hint after its label (§10.2): the
  weekly grain over the whole history, how the score is built, what the pink
  and grey ramps mean, the leftward scroll, and the basis of the delta
  badges. It is keyboard-reachable and disposed on Turbo navigation like
  every tooltip.
- The `/me` sport mix is a donut of the sports practiced in the period, with
  its legend at the side, the active metric's total in the centre (and the
  hovered slice's formatted value while hovering), shown only with at least
  two sports and no sport filter. It opens on **duration**. Every slice is a
  **nuance of the brand primary**, strongest for the leading sport down to the
  lightest step — the calendar ramp's logic, never an invented hue and never a
  sport colour — with percentage tooltips and the standard table disclosure.
  Tapping or clicking a slice or its legend entry selects that sport (the
  legend never hides a series): the centre names it with its value, and a
  panel under the chart repeats value and share with one **Filtrer sur
  Course à pied** button to the hub filtered to that sport over the same
  period. *Autres* has no button. The selected slice again or ✕ clears it.
- An owner profile may carry a **toponymic route story**. Start and finish render
  as `Valmorin → Rochelune` below the card title, or `Boucle à partir de Rochelune` when
  the route returns to its starting place; they are never repeated as graph
  annotations. Between zero and five intermediate steps are numbered **on the
  elevation curve** — a surface dot carrying the rank, with their names in the
  hover tooltip and the route timeline. Analysis pictograms are **rose pills of
  the same size**, also anchored on the curve: climbs and descents both mark
  their **summit** (the climb's end, the descent's start) with the summit icon,
  since a segment is a range and only its top is a point; stops carry the pause
  icon. The profile stays the reference the markers annotate. Only a pictogram
  that crowds another marker (closer than 4% of the route) moves, alternating
  above and below the curve; place numbers never leave the curve, so a cluster
  never piles up and a marker at the top of the range stays inside the plot. A
  proportional route timeline below the chart names every
  step and is the keyboard/text equivalent: its dots are the same circles as
  the numbered places, each step dot filled primary and carrying its icon
  (summit for climbs and descents, pause for stops). A loop has one combined
  `Départ et arrivée` endpoint instead of repeating the same place. Ordinary
  place kinds are not printed (`Cimefroide`, not `Cimefroide (town)`); only a pass or
  summit is qualified when useful. Hover, focus, and click synchronize by
  cumulative distance with the map. The cursor is one object on both surfaces:
  the same ink ball with a surface ring marks the hovered point on the map and
  on the curve, and the profile adds the thin dotted vertical rule behind it,
  whichever side the pointer is on. The map reveals it from a generous screen
  band around the route, not only on the line, and hides the pointer while it
  is inside that band, so the ball is the cursor. No vertical label,
  overlapping callout,
  coordinate, or raw geocoder response appears in the chart surface. The loop
  presentation uses the first and last source points with a 250 m closure
  threshold; this is separate from persisted loop-segment detection. Short
  rural routes prefer useful local names (hamlets, localities, neighbourhoods,
  named routes, and relevant natural or historical landmarks) over a broad
  containing town, including for their start and finish. Longer routes prefer a
  broad containing settlement for their endpoints. A settlement crossed near
  its mapped centre is anchored to the closest route point; the centre itself
  is never exposed.
- **Workout place** — a separate owner-only line assembled from the same
  stored toponymy: the departure, the ranked route markers and the arrival,
  deduplicated, capped at three entries and kept in route order. The workout
  header, the owner's cards and the owner table render it as a quiet
  `ti-map-pin` line — `Valmorin · Cimefroide · Rochelune`, a lone name when the list
  collapses, and nothing when no place is known. Kinds are not printed and a
  coordinate never appears. It is never rendered on a public publication, and
  it is not the chart's route story: the header line lists where the workout
  went, the chart annotation belongs to the profile.
- The chart follows the active analysis tab. Toponymy places stay visible on
  every tab; climb and descent summits appear only through their own tab's
  markers; every other layer (boundaries, stop panels) belongs to
  the selected tab alone. The route timeline lists the toponymy steps plus the
  active tab's discrete events (climbs, descents, stops, detected and recorded
  laps, segment efforts); uniform splits and intervals stay in their table. The
  proportional timeline scrolls horizontally when its steps do not fit on
  desktop — the documented exception to §12's no-horizontal-scrolling rule —
  and stacks vertically on phones. Hovering or
  focusing a timeline step highlights its range on the chart and the map; the
  pinned table row wins again when the pointer leaves. Best-effort rows follow
  the same rule but draw nothing at rest: their windows would overlap and
  clutter the chart, so the range appears only while the row is active.

### 15.2 Maps

The component contract in `[devdoc:maps]` stands. Design adds only sizing and
placement.

| Modifier | Height | Used on |
|---|---|---|
| `--compact` | 12rem | workout card previews, equipment detail |
| default | 24rem | workout detail, segment detail, privacy zone editor |
| `--tall` | 36rem | fullscreen-intent surfaces, segment creation workspace |
| `--discover` | 36rem; below `md` `clamp(18rem, 100dvh − 19rem, 36rem)` | the Découvrir page, whose card fits the phone's first screen above the bottom bar |

- **The basemap variant follows the account**, not only the page: the
  `/settings/appearance` choice « Fond des cartes et images des parcours »
  (`users.route_image_theme`) governs every interactive map as well as the
  route images (§15.4). **Selon le thème** (the default) follows the page
  theme and swaps live on `allure:theme-changed`; **Toujours claires** /
  **Toujours sombres** force one basemap whatever the page theme, and a theme
  toggle then leaves the map alone. The map element carries the resolved
  theme as its own `data-bs-theme`, painted by the server
  (`ApplicationHelper#basemap_theme`) so the first frame is right, and every
  token read inside it — the control skin, the markers, the arrow halo, the
  grid behind a tile-less map, a popup — follows the basemap. Charts keep the
  page theme.
- **A virtual world draws its own map** ([VIRTUAL-PLATFORMS.md](VIRTUAL-PLATFORMS.md)): the world's
  published image replaces the basemap, on a background in the world's own
  colour, and the attribution names `© Zwift`. The dark variant dims the same
  image rather than swapping a second one, so the toggle still works and the
  track keeps the same contrast; the world's background colour dims with it,
  so no bright halo surrounds the image. A world with no image, a real-world
  sport (even where a world shares the city) and a profile whose `basemap`
  setting is off keep the ordinary basemap.
- The colour-by selector hides itself when no metric varies.
- The default track is one primary line for every sport (the same value as the
  rendered route image, `RouteImageRenderer::TRACK_COLOUR`). The start is a
  green dot and the finish a black/white checkered disc. The colour-by selector
  offers *Couleur unie* (the default) plus every metric that varies; choosing a
  metric shades the line light to dark in the primary hue. The selector appears
  whenever at least one metric varies, and the selection highlight is ink so it
  stays visible on the track and its shades.
- **The metric shades a value, and the legend says which.** A power-led virtual
  ride offers *Puissance* first ([VIRTUAL-PLATFORMS.md](VIRTUAL-PLATFORMS.md)); every other map offers
  elevation, speed, then power. Speed and power are noisy readings, so the ramp
  spans their 2nd–98th percentile and each colour stop takes the mean of its own
  slice of the route — one stop or one sprint never flattens the rest of the
  ride. Elevation keeps its true extremes and its sampled stops, which preserve
  summits. While a metric is selected, a compact legend over the map's top-left
  corner names it and prints the ramp's two ends in the viewer's units
  (`0 W — 378 W`); the chart and its data table remain the text equivalent. The
  choice is remembered per kind of map (a separate key for a power-led ride), so
  neither kind overrides the other's default.
- The direction of travel uses small full arrows: a 14 px shaft and open head,
  with rounded 1.5 px track-coloured strokes over a subtle 2.8 px surface halo. Their centres sit
  12 screen pixels outside a detected loop, about every 320 screen pixels,
  above the ink highlight and clear of the start dot and checkered finish.
  Each arrow is placed on the
  straightest point of its slot rather than at a blind interval, so it never
  sits on a corner. Direction is a shape, never
  colour-only, and the arrows survive the flat line, the metric gradient and
  both themes. Repeated passes over a loop share the first pass's arrows:
  later anchors within an approximately 13 px corridor and 30° of an already marked route
  window are omitted, including across recording gaps. Opposite directions
  remain distinct; on open portions their right-side offsets separate them.
  A loop need only be traversed once: its winding selects the exterior side
  (left for clockwise travel, right for counterclockwise travel). Approach and
  exit portions stay on the right. Each lobe of a figure eight is evaluated
  independently, including crossings between sparse recorded points. This is
  display-only topology from the drawn geometry, not a stored loop segment;
  no recording gap is bridged. Ambiguous, near-zero-area or retraced portions
  keep the default right-side placement. The small size and gap stay constant
  through zoom and rotation.
  If fewer than three arrows remain over the whole route after deduplication,
  all direction arrows are hidden. The threshold is global, not per recording
  segment, and is recalculated at each zoom change; zooming back in restores
  the arrows as soon as at least three can be placed. Route images use the
  same threshold at their fitted scale.
- Workout maps carry an options icon in the card header (a Tabler
  `ti-adjustments` ghost button) holding only the on/off « Lisser le tracé »
  checkbox; the display updates immediately and the account preference is
  persisted. The button is the small icon size (`btn-sm btn-icon`) and shares
  one flex row with the colour-by selector, aligned on its centre; on a narrow
  phone the row may wrap. The intensity is chosen on `/settings/appearance`
  (*Léger*, *Moyen*, *Fort*), default off at medium. Course (segment) maps are
  always smoothed at medium and carry no options icon. Smoothing is display-only:
  the point count is preserved so hover, selection, the colour ramp and the
  metrics stay aligned, and the recorded geometry is never changed.
- On feeds and lists the map is never the first element on a phone: the title
  and key metrics come first, because a map is heavy and slow and a reader
  scrolling a feed needs the facts first. The workout detail page is the
  exception (§20.3): its map leads the page under the header.
- On touch screens the interactive map uses cooperative gestures: one finger
  scrolls the page, two move the map, and a short localised hint says so. The
  fullscreen control lifts the restriction while the map fills the screen.
  Without the Fullscreen API (iPhone Safari, the iOS companion) the map pins
  itself over the page, its controls clear the safe areas, and the page
  behind it does not scroll; a gesture at the map's edge never continues as a
  page scroll or a pull-to-refresh.
- Attribution is mandatory and always comes from the style document; on the
  interactive map it is compact by default and expands on demand. It is never
  suppressed or replaced by a hand-written string.
- A route PNG is used wherever a static image suffices; MapLibre is only
  instantiated where the user can interact.
- On the workout page the map's text summary (distance, ascent, recording
  segments) stays in the page for assistive technology only: the summary
  tiles right after it already print the same figures.

### 15.3 Activity calendar

A CSS grid of day cells on `/me`, built client-side from the M3
`by_time?time=day` dataset. No new endpoint, no new table.

- The window is **width-driven with a fixed cell size**: the 13px square is
  the constant, and a wider card shows more week columns instead of bigger
  cells, down to a twelve-week floor on a phone. There is never a horizontal
  scroll. It ends on the viewer's current week; the card's `‹`/`›` controls
  page by the visible span, an *Aujourd'hui* reset brings it back, and the
  visible range is printed below the grid. A resize re-lays the same buckets.
- **Year anchors** sit under the grid on the same 13px column pitch: each year
  is labelled on the column holding its first visible day (the window's first
  column, and every column where January 1st falls). They are decorative
  (`aria-hidden`) — the printed range below the grid is their text equivalent —
  and they re-render on paging and resize.
- The card title carries an explanatory ⓘ hint (the card-header ghost button
  of §10.3, like the feed's Public hint): one cell per day, the metric-selector
  encoding, the window paging, and the per-day tooltip. It is keyboard-reachable
  and disposed on Turbo navigation like every tooltip.
- Intensity encodes the selected metric for the day, in five steps of the
  primary colour ramp: **duration** (default), **distance**, or **activity
  count**. **The step is also encoded in the cell's accessible name**, so
  intensity is never colour-only. Distance and duration steps are quartiles of
  the viewer's own non-zero days, so the ramp stays informative at any volume;
  the count steps are the fixed one-to-four ramp. A Less→More legend names the
  scale.
- Each non-empty cell carries the link to that day's workouts
  (`/workouts?period=custom&from=…&to=…`), with an accessible name of the form
  "12 mars, 2 activités, 24,3 km". When the page-level sport filter is active,
  the metric selector follows it and the day link keeps it as `sports[]`.
  A day holding a single activity links to that activity itself.
  Following the select-then-open rule (§18.4), a tap, a click or Enter
  **selects** the day — an ink ring, never a new hue — and opens its
  **selection callout** over the card: the tooltip's content plus one **Voir
  les activités du jour** button. Enter on the selected day, the button, or a
  modified click (new tab) follows the link. A tap on an empty day says
  *Aucune activité ce jour-là*. A long press then slide scrubs across the
  days; the selected day again, ✕ or Escape clears it, and paging it out of
  the window clears it.
- Every non-empty cell opens a rich tooltip on mouse hover and on keyboard
  focus: the day, the cell's intensity swatch, one row per sport (icon, name,
  distance and duration) and the day total. The tooltip stays icon + text
  only, like every sport identity — never a sport colour. Touch screens read
  the same content in the selection callout instead.
- Weeks start per `users.week_start` (Monday or Sunday) — the same setting that
  bins the weekly statistics.
- Days with no activity are surface-sunken, not white, and are not links.

### 15.4 Route images

Every server-rendered route image exists in **two variants, light and dark**,
generated together and carrying one generation marker. The owner image is a
1600 × 900 MapLibre render of the configured vector style with the single
primary track (`RouteImageRenderer::TRACK_COLOUR`, the live map's default), a
green start dot and a checkered finish flag, and provider attribution. The
light variant falls back after bounded browser retries to the raster and then
tile-less Ruby renderers; the dark variant uses the configured dark style and
falls back to the **dark tile-less** renderer only — the raster basemap is a
light OSM render, so a dark image never composites it. The publication image is
rendered **asynchronously** on the same worker from its immutable sanitized
track with the same chain; when the profile's `basemap` setting is off it is
drawn tile-less by choice, never as a failure fallback. A virtual world's
route image uses the world's own map image instead of the tile style
([VIRTUAL-PLATFORMS.md](VIRTUAL-PLATFORMS.md)), in both variants, and its Ruby fallbacks paint the
world's colour (dimmed on the dark variant) instead of the application
surface. Its federation delivery
waits for the images so the Note always carries them. In dark mode the image is
placed on `--allure-surface-sunken` with the same border treatment as any other
media.

The viewer chooses the variant on `/settings/appearance` (« Fond des cartes
et images des parcours », the same choice that sets the interactive basemap,
§15.2): **Selon le thème** (the default) follows the page theme — the same
`data-bs-theme` the layout renders and every chart follows — so the
server paints the matching variant on the first frame, and a small controller
swaps the image live when the theme changes, in the browser or in the
companion through the shared `allure:theme-changed` event; **Toujours claires**
and **Toujours sombres** force one variant regardless of the theme. A themed
URL always serves the other variant when the requested one is missing, so a
card whose variant lags behind the page theme still renders. Federation
advertises both images as two `Image` attachments — the light one first, the
dark one marked `allure:theme: dark` — so a peer that predates the property
keeps the light image and a current peer stores and serves both.

Every route PNG carries the same offset full direction arrows as the live map, drawn
from the sanitized geometry alone, so a card, a feed item or a received note
reads the sense of travel at a glance; the raster and tile-less fallbacks draw
them too. Course (segment) images are smoothed at the medium level before they
are drawn, matching the live course map; workout images keep the recorded
geometry, since a server-rendered PNG cannot know the viewer's preference.

On workout detail, the interactive map is the primary route representation and
leads the page under the header. The generated route image is not rendered on
the detail page; route images remain available in timeline and dashboard cards
and through authorized publication media. From `lg` (992 px) up, when other
detail content is present, the map occupies a sticky left rail and fills the
viewport height while the right column scrolls, pinned for as long as the
summary, profile and analysis content scrolls beside it. Below the two-column
grid, the comments, the publications card and the participants each take the
full content width. The document remains the single scroll container. Narrower
viewports read map, summary, description, profile, analysis, comments,
publications and participants in that order. Route-image generation remains
asynchronous for the cards and media that use it.

### 15.5 Data anomalies

Readings the analyzer flags as looking wrong in the original file
([WORKOUT.md](WORKOUT.md)) are shown to the owner only, never to a reader, in a
reader preview, or in a publication. They are flagged, never corrected, and the
copy says so.

Nearly every recording holds a finding, so the page puts forward only those
that make a figure wrong (`major`, [WORKOUT.md](WORKOUT.md)); there is no header
badge.

- **Summary tile**: a contested figure keeps its recorded value and gains one
  small mark beside its label, like the record trophy, `ti-alert-triangle` in
  the warning colour being its only colour: the sentence (« Probablement ≈
  11,9 km/h, sans les sauts GPS · exclue des records ») lives in the mark's
  tooltip, which never grows the tile. The tooltip is the shared Bootstrap one
  (hover, focus, or a tap on touch) and the mark carries the same sentence as
  its accessible name; the analysis tab holds the sentence and the stretch as
  text, like every other finding. The reason says where the plausible value
  comes from (the device's measured speed, the track without the GPS jumps,
  without the suspect peak). A contested ascent has no plausible value to
  name, so its sentence says « Probablement surestimé : jusqu'à 24 m d'écart
  aux mêmes endroits · exclu des records »; the descent carries the same
  sentence without the exclusion, since no record reads it.
- **Inspection switch**: the tab's « Montrer toutes les anomalies sur la carte
  et le profil » switch, off by default and remembered on the browser. Off,
  the map and the profile draw the major findings only; on, every flagged one.
- **Map**: short warning-colour dashes (`--warning`, 3 px, dash 1.2 × width)
  over the stretch of each GPS or timing finding, at least 40 m long; a
  rejected position is a hollow warning dot joined to its kept neighbours by
  the same dashes, so the reader sees the path the analysis left out. Heart
  rate, elevation, power and cadence findings are not drawn on the map.
- **Profile**: every finding is a row of short warning dashes along the foot of
  the plot, on the plot's own scale (true when zoomed), at least 6 px wide, one
  row per kind of reading (positions and timing, heart rate, elevation, power
  and cadence) so two findings at the same place never hide each other. The
  dash names the finding through the shared Bootstrap tooltip, never a native
  `title`, and the curve's reading tooltip takes the same inverted surface,
  padding and type, so the profile shows one tooltip style; hovering it previews its range on the chart and the map like an
  analysis row. The dashes are decorative (`aria-hidden`): the tab is their
  text equivalent.
- **Analysis tab** « Qualité des données » (`ti-alert-triangle`, last, its
  count the flagged findings): one sentence saying only the figures they make
  wrong are signalled and kept out of records and nothing is corrected, the
  inspection switch, then « Chiffres faussés » (one line per contested
  figure, previewing its stretch), then one group per kind — the kinds holding
  a major finding first, their icon in the warning colour, the others
  secondary — each row its distance, its moment, its detail and, when major,
  a « Fausse un chiffre » `bg-warning-lt` badge. Rows preview their range like
  every analysis row; a kind holding more findings than stored ends with « Et
  N autres, non détaillées. ». A tab holding an elevation mismatch ends with
  the one correction available, the terrain-profile switch, and only where the
  instance configured a provider and the account opted in (`[devdoc:elevation]`). Last, folded in a `<details>`, « Habituel pour
  cet appareil » lists the device's signature kinds, which are not flagged.

---

## 16. Motion

Minimal, purposeful, and interruptible.

| Allowed | Duration |
|---|---|
| State transitions (hover, focus, active, disabled) | ≤ 150ms |
| Disclosure open/close, dropdown, off-canvas | ≤ 200ms |
| Toast enter/leave | ≤ 200ms |
| Skeleton shimmer | continuous, subtle |
| **ECharts** series animation | library default, retained where a chart animates |
| **MapLibre** pan/zoom/`flyTo` | library default, retained |

Not allowed: page transitions, parallax, scroll-triggered reveals, animated
illustrations, confetti, number count-ups, and anything that delays reading.

One exception: the weather condition icons (Meteocons, §20.3) keep their own
slow loop — a drifting cloud, falling rain, a turning sun — on the weather
card, the header badge and the analysis markers. The hourly table draws them
static, since a column of moving icons competes with the figures.

### `prefers-reduced-motion`

When set, **all** of the above is disabled, including the two library
exceptions: ECharts `animation: false`, MapLibre `jumpTo` instead
of `flyTo`, no skeleton shimmer, no toast slide, the static weather icons.
This is checked at
initialisation and is not merely a CSS rule, because both libraries animate in
JavaScript.

---

## 17. Dark mode

Dark is a **first-class peer** of light, not a filter over it. Every component,
state, chart, map style and screenshot in this document exists in both.

- The theme is server-resolved into `<html data-bs-theme>` on first paint
  (`ApplicationHelper#current_theme`), so there is no light flash. That must not
  regress.
- The toggle broadcasts `allure:theme-changed`; the map swaps to a real dark
  style document, the chart re-reads its colours. Neither uses a CSS filter.
- **The user's theme choice persists to their account.** Today it does not:
  `theme_controller.js` only PATCHes when `settings_appearance_path` exists, and
  that route does not exist, so the choice survives only in `localStorage`.
  §25 records this.
- Dark surfaces use `--allure-surface-*`; no component hardcodes a light
  assumption. Reviewing a component means reviewing it twice.
- Contrast requirements (§18.1) apply identically in both themes. The sport
  palette, the generated-avatar palette and the chart ramp are each validated
  against both backgrounds.
- Route PNGs are theme-neutral (§15.4). Uploaded avatars are not; they sit on a
  bordered surface so a white-background image does not bleed into a dark page.

---

## 18. Accessibility

**Target: WCAG 2.1 level AA.** This is a commitment, not an aspiration. Where a
canvas cannot comply, an equivalent that does is mandatory (§18.7).

### 18.1 Contrast

- Body text and metric values: **4.5:1** minimum against their surface.
- Large text (≥ 24px, or ≥ 19px bold): **3:1**.
- UI component boundaries, focus indicators, chart series, map track lines,
  badge borders: **3:1**.
- Validated in **both themes**. The generated-avatar palette and chart ramp are
  fixed sets precisely so this can be checked once rather than computed per
  render.

### 18.2 Focus

- Focus is **always visible**. `outline: none` without a replacement indicator is
  a defect.
- The focus ring uses `--allure-focus` at 3:1 against both the component and its
  surface.
- Focus order follows reading order. Modals trap focus and restore it to the
  trigger on close.
- Skip-to-content is the first focusable element on every page.

### 18.3 Keyboard

Every interactive element is reachable and operable by keyboard, including:

- the sport and date filter controls;
- table sorting and row actions;
- the privacy zone editor — via its numeric fields, which are the sanctioned
  keyboard equivalent of dragging the marker;
- the segment selection workspace — via numeric start/end inputs, which are the
  keyboard equivalent of the chart brush;
- the map's zoom and fullscreen controls (MapLibre's own controls, already
  labelled through `map_control_locale`).

No keyboard trap. `Escape` closes every overlay.

### 18.4 Targets and pointers

- Touch targets: **44×44 CSS px** minimum, including table row action buttons
  and bottom-bar items.
- No hover-only affordance: anything revealed on hover is also revealed on focus
  and is present for touch users.
- Drag interactions (privacy zone marker, chart brush) always have a
  non-drag alternative.
- **Select, then open.** On the `/me` charts (pulse, activity calendar, sport
  mix) no mark navigates by itself, for every input alike: a tap or click
  selects the item and shows its detail in a panel under the chart, whose
  full-size button is the only way into the filtered list. The hit zone is
  the item's whole slot, not its drawn mark. A long press then slide (about
  400 ms, under 10 px of movement) scrubs the selection without scrolling;
  a finger that moves first scrolls. The panel's actions and the chart's
  paging buttons meet the 44 px target on coarse pointers, and the sport
  switch grows its hit area there through an invisible overlay (§10.15).
  Floating chart tooltips follow a hovering mouse only.

### 18.5 Structure and semantics

- One `<h1>` per page; heading levels never skip.
- Landmarks: `banner`, `navigation` (primary navigation and bottom bar, distinctly
  labelled), `main`, `contentinfo`.
- Lists are lists; tables are tables with `<caption>` or an `aria-labelledby`
  pointing at the card title, and `<th scope>` on every header.
- Card-mode tables (§12.3) become real lists, not restyled table markup.
- Icon-only controls have `aria-label`; decorative icons are `aria-hidden`.

### 18.6 Colour is never the only encoding

Every one of these carries an icon, a shape, a label or a pattern in addition to
its colour: sport, audience and publication state (one mark in four states,
each named by its own label), import entry status, record
badge, equipment state, segment kind, calendar intensity, chart series, map
gradient legend, form validation state.

### 18.7 Maps and charts

A canvas cannot be made conformant by adding attributes to it. The design's
answer is an **equivalent, not an excuse**:

- every chart card contains a disclosure ("Voir les données") revealing a real
  table of the plotted values — on the workout profile a phone reads it as a
  screen-reader-only list, the visible disclosure starting at `md` — or — for
  the `/me` pulse, whose weekly history
  spans years — a screen-reader-only table of the selected period plus a
  keyboard cursor that walks every loaded week and announces its values
  (§15.1);
- every map card is accompanied by the metrics that describe the route —
  distance, ascent, bounds, recording-segment count — as text;
- the elevation chart's hover synchronisation is an enhancement; the data is
  fully available without it;
- the map's `<canvas>` is `aria-hidden`, and the card carries a text description
  of what it shows. Announcing a canvas as an unlabelled image is worse than
  hiding it and describing it.

### 18.8 Live regions

- Toast container: `aria-live="polite"`, present from first paint.
- Batch import progress: `aria-live="polite"` on the status region, announcing
  only meaningful transitions — not every 2-second poll.
- Filter result counts: `aria-live="polite"`.
- Form error summaries: `role="alert"`.

### 18.9 Motion and language

- `prefers-reduced-motion` is honoured in CSS *and* in both charting and mapping
  libraries (§16).
- `<html lang>` reflects the active locale (already implemented) so screen
  readers pronounce every language correctly; a language named in itself
  (§10.24) carries its own `lang`.

---

## 19. Privacy-critical copy

**These strings are mandatory, verbatim, and non-dismissible where stated.**
They exist because [PUBLISHING.md](PUBLISHING.md) and [SEGMENTS.md](SEGMENTS.md) identify specific
ways this application can harm someone, and copy is the only mitigation the user
actually reads. They are written in the sober register (§3.2) and may not be
softened, shortened, made playful, or moved behind a disclosure.

The French and English texts below are the reference. The German, Spanish
and Dutch texts live only in their locale files, under the same keys: each is
a faithful translation of the English — every fact, condition and
irreversibility kept, nothing softened or summarised — and a change to a
reference text changes all three in the same patch. They are the first strings
a native reviewer reads.

### 19.1 Publication preview — before publishing

Placement: in the publish form, visible without a disclosure, updating live
when the profile selection changes. The workout is never projected (no
preview card, no second map): the sentence is laid out as two short lists. The
first is headed by its opening words, « Voici exactement ce qui sera
partagé : », and lists the selected profile's shared fields with a check mark;
the second, « Non partagé avec ce profil : », lists the optional fields it
leaves out with a cross, and closes with the sentence's second half, verbatim
— « Le fichier d'origine, vos notes privées et les points masqués par vos
zones de confidentialité ne sont jamais partagés. ». The owner reads the
published page itself through « Voir comme vos lecteurs ».

> **FR** — « Voici exactement ce qui sera partagé : {liste des champs}. Le
> fichier d'origine, vos notes privées et les points masqués par vos zones de
> confidentialité ne sont jamais partagés. »
>
> **EN** — "Here is exactly what will be shared: {field list}. Your original
> file, your private notes, and the points hidden by your privacy zones are
> never shared."

### 19.2 Publication is irrevocable — in the delete-publication confirmation

Placement: the confirmation modal body. Non-dismissible.

> **FR** — « La publication est retirée de cette instance et un avis de
> suppression est envoyé aux serveurs qui la connaissent. Les copies déjà
> récupérées par d'autres serveurs ne peuvent pas être rappelées. »
>
> **EN** — "The publication is withdrawn from this instance and a deletion
> notice is sent to the servers that know about it. Copies already fetched by
> other servers cannot be recalled."

### 19.3 Profile changes are not retroactive — on the publishing profile form

Placement: persistent info panel at the top of the form.

> **FR** — « Les modifications de ce profil s'appliquent aux publications
> futures. Les publications existantes ne changent pas : pour appliquer de
> nouveaux réglages, supprimez la publication et republiez. »
>
> **EN** — "Changes to this profile apply to future publications. Existing
> publications do not change: to apply new settings, delete the publication and
> republish."

### 19.4 Source edits do not update a publication — on the workout edit form

Placement: shown only when the workout has an active publication.

> **FR** — « Cette activité est publiée. Modifier le titre, la description ou le
> sport ne modifie pas la publication existante. Supprimez-la et republiez pour
> partager la version à jour. »
>
> **EN** — "This workout is published. Editing the title, description or sport
> does not change the existing publication. Delete it and republish to share the
> updated version."

Changing the sport is not a metadata edit: the sport selector carries its own
permanent hint, and a missing original file is refused.

> **FR** — « Changer le sport réanalyse l'activité (temps de mouvement, dénivelé,
> allure ajustée) et recalcule les meilleurs efforts, les records et les
> segments. Les publications existantes ne changent pas. »
>
> **EN** — "Changing the sport re-analyses the workout (moving time, elevation,
> grade-adjusted pace) and rebuilds best efforts, records, and segments.
> Existing publications do not change."

The bulk review page (§10.19) carries the same obligations in their plural
form, with the exclusion it already knows:

> **FR** — « Changer le sport de {N} activités les réanalyse (temps de
> mouvement, dénivelé, allure ajustée) et recalcule leurs meilleurs efforts,
> leurs records et leurs segments. Les publications existantes ne changent pas.
> Les activités sans fichier d'origine seront ignorées. »
>
> **EN** — "Changing the sport of {N} workouts re-analyses them (moving time,
> elevation, grade-adjusted pace) and rebuilds their best efforts, records, and
> segments. Existing publications do not change. Workouts without an original
> file will be skipped."

> **FR** — « Le fichier d'origine de cette activité n'est plus disponible ; son
> sport ne peut pas être modifié. »
>
> **EN** — "This workout's original file is no longer available; its sport
> cannot be changed."

### 19.5 Leaderboard aliases — on every leaderboard a non-owner reads

Placement: persistent, non-dismissible info panel. Required by
[SEGMENTS.md](SEGMENTS.md), which makes the residual risk a UI obligation rather
than internal documentation.

> **FR** — « Les alias ne sont pas des identités : ils masquent le nom, mais
> l'administrateur de l'instance peut les rattacher à un compte, et sur une
> petite instance un alias peut être devinable par élimination. Les dates sont
> volontairement réduites au mois. Un classement reste une donnée personnelle. »
>
> **EN** — "Aliases are not identities: they hide the name, but the instance
> administrator can link them to an account, and on a small instance an alias
> can be guessable by elimination. Dates are deliberately coarsened to the
> month. A leaderboard is still personal data."

A shorter version of this already ships as `segments.leaderboard.residual_risk`,
covering administrator identification and recognition by elimination. Two
obligations in [SEGMENTS.md](SEGMENTS.md) are missing from it and must be added: that
dates are deliberately coarsened to the month, and that a leaderboard remains
personal data. It also renders as muted text at the foot of the card, which
reads as a footnote; it belongs above the table, as a persistent info panel, so
it is seen before the data rather than after it.

### 19.6 Leaderboard participation is opt-out — on the segment page

Placement: inside the **Classements** container on the segment page, rendered to
every signed-in viewer of a shared course — the owner included. The toggle sits
in the container header, on the right, duplicated at the top of the page `⋯`
menu; the state and the participation note render **below the board tables**.
The container states what participation means: the board follows its reader
— an athlete appears as soon as their workout is published with its route,
to whoever can see that workout — and only followers read names.

> **FR** — « Vous figurez au classement dès que votre activité est publiée
> avec son parcours : chacun vous y voit s'il peut voir cette activité. Vos
> abonnés lisent votre nom ; les autres lisent un alias et la date réduite au
> mois. »
>
> **EN** — "You are on the leaderboard as soon as your workout is published
> with its route: anyone who can see that workout sees you here. Your
> followers read your name; others read an alias and the date coarsened to
> the month."

Above that note, an athlete with an effort on the course reads their own
line: the §10.4 badge naming who sees them — « Visible par tout le monde »
(green, publication mark), « Visible par vos abonnés » (blue, publication
mark) — or, grey under the cut mark, why nobody does, with
one sentence:

| Reach | Badge | Sentence |
|---|---|---|
| `unpublished` | Visible par vous seul | Publiez l'activité avec son parcours pour apparaître au classement. |
| `route_hidden` | Absent du classement | Votre activité est publiée sans son parcours, donc ce segment ne révèle pas votre passage. |
| `zoned` | Absent du classement | Une de vos zones de confidentialité touche ce segment, donc vos passages n'y apparaissent jamais. |
| `opted_out` | Vous avez quitté ce classement | Vos passages n'apparaissent plus ici, quelle que soit leur publication. |

Leaving ("Ne plus figurer au classement") writes an exclusion and removes the
row immediately; rejoining destroys it. The owner is not a special case and
never sees another athlete's efforts outside the board. The publishing
profile's **Parcours** setting is the general consent — its hint says it also
puts passages on segment boards; the per-segment exclusion lives here.

**Leaderboard category — on `/settings/profile`.** A « Classements » card
holds three radios (Non précisé, Femmes, Hommes; `unspecified` by default),
a hint naming the threshold, and a persistent info panel:

> **FR** — « Toute personne qui lit un classement où vous figurez peut voir
> que vous avez déclaré cette catégorie, même sous un alias. Elle ne quitte
> pas cette instance et ne figure sur aucune publication. Revenir à « Non
> précisé » vous retire aussitôt de ces vues. »
>
> **EN** — "Anyone who reads a leaderboard you appear on can see that you
> declared this category, even under an alias. It never leaves this instance
> and is part of no publication. Switching back to “Not specified” removes you
> from those views at once."

### 19.7 Privacy zones — on the zone index and editor

Placement: persistent info panel.

> **FR** — « Une zone de confidentialité supprime les points GPS situés à
> l'intérieur de son rayon dans tout ce que vous publiez. Le départ et l'arrivée
> suivent les réglages du profil de publication : un masque désactivé les laisse
> visibles, même dans une zone. Elle ne modifie ni vos données d'origine, ni les
> publications déjà créées. Créez vos zones avant de publier. »
>
> **EN** — "A privacy zone removes the GPS points inside its radius from
> everything you publish. The start and the finish follow the publishing
> profile's settings: an unchecked mask leaves them visible, even inside a zone.
> It does not change your original data, and it does not change publications you
> have already created. Create your zones before you publish."

### 19.8 Deleting a privacy zone

> **FR** — « Les publications existantes ne sont pas modifiées. Vos prochaines
> publications ne masqueront plus cette zone. »
>
> **EN** — "Existing publications are not changed. Your future publications will
> no longer hide this area."

### 19.9 Deleting a workout

> **FR** — « L'activité, son fichier d'origine, ses tronçons et ses passages de
> segment sont supprimés définitivement. Si elle est publiée, la publication est
> retirée ; les copies déjà récupérées par d'autres serveurs ne peuvent pas être
> rappelées. »
>
> **EN** — "The workout, its original file, its recording segments and its
> segment efforts are permanently deleted. If it is published, the publication is
> withdrawn; copies already fetched by other servers cannot be recalled."

The bulk review page (§10.19) states the same consequences for the whole
selection:

> **FR** — « Les {N} activités, leurs fichiers d'origine, leurs tronçons et
> leurs passages de segment sont supprimés définitivement. Les publications
> retirées ne peuvent pas être rappelées sur les autres serveurs. »
>
> **EN** — "The {N} workouts, their original files, their recording segments
> and their segment efforts are permanently deleted. Withdrawn publications
> cannot be recalled on other servers."

### 19.10 Gravatar opt-in — on the profile setting

> **FR** — « Activer Gravatar autorise cette instance à récupérer votre avatar
> depuis un service tiers à partir de l'empreinte de votre adresse e-mail.
> L'image est mise en cache ici : votre navigateur et ceux des personnes qui
> consultent votre profil ne contactent jamais ce service. »
>
> **EN** — "Enabling Gravatar allows this instance to fetch your avatar from a
> third-party service using a hash of your email address. The image is cached
> here: your browser, and the browsers of people viewing your profile, never
> contact that service."

### 19.11 Publication readiness warnings

The six `Workouts::PublicationReadiness` warnings, rendered next to the profile
selector, updating live:

| Warning | FR | EN |
|---|---|---|
| `no_interior_points` | « Les zones de confidentialité actuelles ne masquent aucun point intérieur. Vérifiez que ce profil partage volontairement le parcours visible. » | "No interior points are removed by the current privacy zones. Verify that this profile intentionally shares the visible route." |
| `endpoint_mask_start` | « Le départ sera masqué. » | "The start will be hidden." |
| `endpoint_mask_finish` | « L'arrivée sera masquée. » | "The finish will be hidden." |
| `endpoint_visible_start` | « Le départ est dans une zone de confidentialité active et restera visible, car ce profil ne le masque pas. » | "The start is inside an active privacy zone and will stay visible because this profile does not mask it." |
| `endpoint_visible_finish` | « L'arrivée est dans une zone de confidentialité active et restera visible, car ce profil ne la masque pas. » | "The finish is inside an active privacy zone and will stay visible because this profile does not mask it." |
| `route_unavailable` | « Aucun parcours ne peut être partagé avec ce profil. » | "No route can be shared with this profile." |

### 19.12 Signing out everywhere

> **FR** — « Toutes vos sessions sont fermées, y compris celle-ci et celles de
> vos autres appareils. Vous devrez vous reconnecter partout. »
>
> **EN** — "All your sessions are closed, including this one and those on your
> other devices. You will need to sign in again everywhere."

### 19.13 Followers publications — on the built-in followers profile

The followers profile is always available: accepted followers on this instance
read its publications whatever the federation switches say
([FEDERATION.md](FEDERATION.md)). Non-dismissible info panel on the profile page, naming
exactly who receives them under the instance's current switches
(`PublishingProfilesHelper#followers_reach_notice`). The owner cannot choose
which instances are approved; the operator does, and the copy must not imply
otherwise.

Federation off (`local`):

> **FR** — « Seuls vous et vos abonnés acceptés sur cette instance voient ces
> publications. Cette instance ne communique pas avec les autres. »
>
> **EN** — "Only you and your accepted followers on this instance see these
> publications. This instance does not communicate with others."

Federation on, restricted federation off (`not_federated`):

> **FR** — « Seuls vous et vos abonnés acceptés sur cette instance voient ces
> publications. Vos abonnés des autres instances ne les reçoivent pas :
> l'opérateur de cette instance n'a pas activé leur envoi. »
>
> **EN** — "Only you and your accepted followers on this instance see these
> publications. Your followers on other instances do not receive them: this
> instance's operator has not enabled sending them."

Restricted federation on (`federated`):

> **FR** — « Vos abonnés acceptés sur cette instance voient ces publications.
> Sur les autres instances, seuls les comptes des instances approuvées par ce
> serveur les reçoivent. Une instance approuvée en reçoit une copie et peut la
> conserver ; retirer la publication plus tard ne rappelle pas les copies déjà
> récupérées. »
>
> **EN** — "Your accepted followers on this instance see these publications.
> On other instances, only accounts on instances this server has approved
> receive them. An approved instance receives a copy and may keep it; removing
> the publication later cannot recall copies already fetched."

The profile form explains the reserved audience the same way: custom profiles
are always public, and the followers audience belongs to the built-in profile.

### 19.14 Sharing a course through a privacy zone — on the segment edit form

Placement: persistent non-dismissible info panel, shown when the course
corridor intersects an active privacy zone and the segment is being shared.
The acknowledgment checkbox sits under the copy and is required before the
change is accepted. A segment corridor is not filtered like a workout
publication: the owner chose the line, so the control is informed consent.

> **FR** — « Ce parcours traverse une de vos zones de confidentialité.
> Contrairement à une publication d'activité, les points situés dans la zone ne
> sont pas retirés du tracé : le segment partagé passera à l'intérieur. Ne
> confirmez que si le tracé que vous partagez ne révèle rien que vous voulez
> garder privé. »
>
> **EN** — "This course passes through one of your privacy zones. Unlike a
> workout publication, the points inside the zone are not removed from the
> course: the shared segment will pass through it. Confirm only if the course
> you are sharing reveals nothing you want to keep private."

The acknowledgment is stored (`segments.privacy_zone_acknowledged_at`) and is
invalidated by a corridor change (geometry or match tolerance), so a later edit
asks again. A validation failure states the same consequence in one sentence.

### 19.15 Course publication — on the segment sharing card

Placement: the owner's publication state is the segment page header badge
(the §10.4 badge, green with the audience it is published to);
the preview names what leaves the instance and what never does and lives, with
the stale hint, the blocking warnings, and the private hint, as non-interactive
text in the page header `⋯` menu above the publish, republish, and withdraw
actions. Withdrawal reuses the §19.2 irrevocability wording.

> **FR** — « Ce qui sera partagé : le tracé, le nom, la description, le sport et
> les métriques du parcours. Les efforts, les athlètes et le classement ne sont
> jamais partagés. »
>
> **EN** — "What will be shared: the course geometry, name, description, sport,
> and course metrics. Efforts, athletes, and the leaderboard are never shared."

The withdrawal confirmation body is the §19.2 body verbatim: copies already
fetched by other servers cannot be recalled.

### 19.16 Copying a remote course — on the remote course page

Placement: persistent non-dismissible info panel above the copy action. The
copy is a local, private segment; the only irrevocable fact to state is that it
survives the remote course's withdrawal or an unfollow, and that the origin
leaderboard is not copied.

> **FR** — « La copie devient un segment privé qui n'appartient qu'à vous : il
> est chronométré localement et survit au retrait du parcours distant ou à un
> désabonnement. Le classement d'origine n'est pas copié. »
>
> **EN** — "The copy becomes a private segment that belongs to you only: it is
> timed locally and survives the remote course's withdrawal or an unfollow. The
> origin leaderboard is not copied."

### 19.17 Remote course withdrawn — on the deleted state

Placement: the tombstone empty state, shown to former recipients only.

> **FR** — « Ce parcours a été retiré sur son instance d'origine. Les copies
> déjà récupérées ne peuvent pas être rappelées. »
>
> **EN** — "This course was removed on its origin instance. Copies already
> fetched cannot be recalled."

### 19.18 Elevation enrichment — on the elevation setting

Placement: the elevation settings page, under the opt-in toggle. Persistent and
non-dismissible while the setting is editable. `%{provider}` is the configured
service URL, rendered as plain text.

> **FR** — « Activer l'altitude estimée autorise cette instance à envoyer les
> coordonnées échantillonnées de vos parcours sans altitude à %{provider}. Les
> altitudes renvoyées sont mises en cache ici et servent à analyser l'activité ;
> votre navigateur et ceux des personnes qui consultent vos activités ne
> contactent jamais ce service. Vos zones de confidentialité ne filtrent pas
> cet envoi. »
>
> **EN** — "Enabling estimated elevation allows this instance to send sampled
> coordinates of your elevation-less tracks to %{provider}. The returned
> elevations are cached here and used to analyse the workout; your browser, and
> the browsers of people viewing your workouts, never contact that service. Your
> privacy zones do not filter this request."

### 19.19 Scheduled publication — on the scheduled publication card

Placement: the scheduled card at the top of the sharing section of the owner's
workout page, visible for the whole safety delay. Non-dismissible. The card
states what the delay means; the two confirmations state the consequences of
leaving it early or cancelling it.

> **FR** — « Rien n'est partagé avant cette date. Modifier l'activité, ce profil
> ou vos zones de confidentialité ne modifie pas la publication programmée. »
>
> **EN** — "Nothing is shared before that date. Editing the workout, this
> profile, or your privacy zones does not change the scheduled publication."

Publishing now is immediate and irrevocable. The confirmation body is:

> **FR** — « La publication devient immédiatement visible et un avis est envoyé
> aux serveurs qui la connaissent. Les copies déjà récupérées par d'autres
> serveurs ne peuvent pas être rappelées. »
>
> **EN** — "The publication becomes visible immediately and a notice is sent to
> the servers that know about it. Copies already fetched by other servers
> cannot be recalled."

Cancelling inside the delay shared nothing. The confirmation body is:

> **FR** — « Rien n'a été partagé. La publication programmée est supprimée ;
> vous pourrez republier à tout moment. »
>
> **EN** — "Nothing was shared. The scheduled publication is deleted; you can
> publish again at any time."

The publishing profile form explains both states in the same register: without
a delay the publication is shared immediately and irrevocably, and with a delay
nothing is shared before it ends, with publish now, reschedule, and cancel
available during it.

### 19.20 Participation — on the participants card and the participant view

Placement: the owner's add form, the participant's confirmation view, and the
metrics-only presentation. Non-dismissible, sober register.

The owner's card states, under the add field:

> **FR** — « La personne devra confirmer. Elle verra les mesures de l'activité ;
> la trace reste régie par votre profil de publication. »
>
> **EN** — "The person must confirm. They will see the activity's metrics; the
> route stays governed by your publishing profile."

The participant's confirmation view states, above Confirmer:

> **FR** — « En confirmant, votre nom apparaît sur cette activité. La trace
> reste régie par le profil de publication de son propriétaire ; elle peut
> donc ne pas être visible. Vous pouvez retirer votre participation à tout
> moment. »
>
> **EN** — "By confirming, your name appears on this activity. The route stays
> governed by its owner's publishing profile, so it may not be visible. You
> can withdraw your participation at any time."

An account invited from another instance reads, on the received note's
card:

> **FR** — « En confirmant, elle comptera pour vous avec ses mesures :
> distance, durée, dénivelé et vitesse. Sa trace reste régie par la
> publication de son propriétaire. Vous pourrez retirer votre participation à
> tout moment. »
>
> **EN** — "By confirming, it counts for you with its metrics: distance,
> duration, elevation and speed. Its route stays governed by its owner's
> publication. You can withdraw your participation at any time."

When the owner's invitation of a remote handle is refused, the alert names
the conditions:

> **FR** — « Ce compte ne peut pas être invité. Sur une autre instance, il
> doit vous suivre, avoir reçu la publication de cette activité, et la
> publication doit partager la distance, la durée, le temps en mouvement, le
> dénivelé et la vitesse moyenne. »
>
> **EN** — "This account cannot be invited. On another instance, it must
> follow you and have received this activity's publication, and the
> publication must share distance, duration, moving time, elevation and
> average speed."

The metrics-only presentation carries, under the tiles:

> **FR** — « Les mesures de cette activité sont partagées avec vous. Son
> itinéraire reste régi par le profil de publication de son propriétaire. »
>
> **EN** — "This activity's metrics are shared with you. Its route stays
> governed by its owner's publishing profile."

The participant's own credit row carries, under its tiles:

> **FR** — « Cette activité compte pour vous. Elle ne garde que ses mesures :
> la trace et les données de l'appareil restent à la personne qui l'a
> enregistrée. »
>
> **EN** — "This activity counts for you. It keeps its metrics only: the route
> and the device's data stay with whoever recorded it."

When no publication of the source shows its route to the participant, the
summary adds:

> **FR** — « Le parcours n'est pas visible pour vous : il reste régi par le
> profil de publication de la personne qui a enregistré cette sortie. »
>
> **EN** — "The route is not visible to you: it stays governed by the
> publishing profile of whoever recorded this outing."

and once the source is deleted, « Le parcours n'est plus disponible :
l'activité source a été supprimée. » / "The route is no longer available: the
source activity was deleted."

A detected outing (lot 3) states, above the suggested rows of either card:

> **FR** — « Allure a trouvé une activité enregistrée au même moment, au même
> endroit. Si vous avez fait cette sortie ensemble, confirmez : les deux
> activités seront liées une fois que vous aurez confirmé tous les deux. »
>
> **EN** — "Allure found an activity recorded at the same time, in the same
> place. If you did this outing together, confirm: the two activities are
> linked once you have both confirmed."

The detection switch in the notification settings states:

> **FR** — « Allure compare vos enregistrements avec ceux des comptes que vous
> suivez et qui vous suivent, s'ils l'acceptent aussi. Une suggestion ne
> montre ni lieu, ni distance, ni score ; rien n'est lié sans votre
> confirmation. »
>
> **EN** — "Allure compares your recordings with those of accounts you follow
> and that follow you, if they accept it too. A suggestion shows no place, no
> distance and no score; nothing is linked without your confirmation."

The link suggestion banner states, under « Vous avez enregistré cette sortie »:

> **FR** — « « *recording* » (*date*) semble être votre propre enregistrement
> de « *credit* ». Liez-le : il remplacera le crédit. En attendant, cette
> sortie compte deux fois. »
>
> **EN** — "“*recording*” (*date*) looks like your own recording of
> “*credit*”. Link it: it will replace the credit. Until then, this outing
> counts twice."

### 19.21 Comments — on the composer and the closed thread

Placement: under every comment and reply composer, as the field's
description (§10.20); in place of the composer on a closed thread.
Non-dismissible, sober register. The sentence names the widest audience the
comment reaches once the thread federates ([COMMENTS.md](COMMENTS.md)).

On a public publication:

> **FR** — « Votre commentaire est visible par toutes les personnes qui
> voient cette activité, ici et sur les autres instances qui l'ont reçue. »
>
> **EN** — "Your comment is visible to everyone who can see this workout,
> here and on the other instances that received it."

On a followers publication:

> **FR** — « Votre commentaire est visible par les personnes qui suivent ce
> compte, ici et sur leurs instances. »
>
> **EN** — "Your comment is visible to the people who follow this account,
> here and on their instances."

On a received public note, whose origin hosts the thread and passes every
comment it takes on to the other instances the workout went to:

> **FR** — « Votre commentaire est envoyé à l'instance de @handle, qui le
> transmet aux autres instances qui ont reçu cette activité. Le supprimer ici
> en demande la suppression partout, sans garantie. »
>
> **EN** — "Your comment is sent to @handle's instance, which passes it on to
> the other instances that received this workout. Deleting it here asks for
> its deletion everywhere, without guarantee."

On a received followers-only note, whose origin keeps the thread to itself:

> **FR** — « Votre commentaire est envoyé à l'instance de @handle, qui en
> conserve une copie. Le supprimer ici en demande la suppression là-bas, sans
> garantie. »
>
> **EN** — "Your comment is sent to @handle's instance, which keeps a copy.
> Deleting it here asks for its deletion there, without guarantee."

On a closed thread:

> **FR** — « Les commentaires sont fermés sur cette activité. »
>
> **EN** — "Comments are closed on this workout."

### 19.23 Garmin Connect — on the Garmin Connect connection card

Placement: the Garmin Connect page of `/connections`, under the link
form and on the connected card. Persistent and non-dismissible.

> **FR** — « Garmin ne propose pas d'API publique : cette connexion utilise
> votre compte Garmin et peut cesser de fonctionner à tout moment. Votre mot
> de passe sert une seule fois à établir la connexion : il est conservé
> chiffré pendant l'exécution de la tâche (quelques minutes au plus), puis
> effacé ; seuls les jetons de session sont conservés, chiffrés. Les activités
> importées restent privées jusqu'à ce que vous les publiiez. »
>
> **EN** — "Garmin offers no public API: this connection uses your Garmin
> account and may stop working at any time. Your password is used once to
> establish the connection: it is kept encrypted while the task runs (a few
> minutes at most), then deleted; only the session tokens are stored,
> encrypted. Imported activities stay private until you publish them."

### 19.23b EXR — on the EXR connection card

Placement: the EXR page of `/connections`, under the link form and on
the connected card. Persistent and non-dismissible
(`[devdoc:remote-imports]`). Without equipment, the unlink checkbox of
§19.24 names the workouts only.

> **FR** — « EXR ne propose pas d'API publique : cette connexion utilise votre
> compte EXR et peut cesser de fonctionner à tout moment. Votre mot de passe
> sert une seule fois à établir la connexion : il est conservé chiffré
> pendant l'exécution de la tâche (quelques minutes au plus), puis effacé ;
> seul le jeton de connexion durable d'EXR est conservé, chiffré. Vous
> déconnecter du site EXR peut l'invalider : il faudra alors reconnecter EXR
> ici. Les activités importées restent privées jusqu'à ce que vous les
> publiiez. »
>
> **EN** — "EXR offers no public API: this connection uses your EXR account
> and may stop working at any time. Your password is used once to establish
> the connection: it is kept encrypted while the task runs (a few minutes at
> most), then deleted; only EXR's long-lived sign-in token is stored,
> encrypted. Signing out of the EXR site may invalidate it: you will then need
> to reconnect EXR here. Imported activities stay private until you publish
> them."

### 19.23c Withings — on the Withings connection card

Placement: the Withings page of `/connections`, under the sign-in
form (e-mail and password only; the range is the connected card's retrieval
form) and on the connected card. Persistent and non-dismissible
(`[devdoc:remote-imports]`). Without equipment, the unlink checkbox of
§19.24 names the workouts only. The session is the only credential and
Withings grants it for a day: the form asks for the password again at each
reconnection, and the copy says so plainly instead of hiding it. The
preferences form also carries the « N'importer que les séances avec un
parcours GPS » switch (`[devdoc:remote-imports]`, on by
default): an Apple Health-fed account lists auto-detected sessions without a
route beside real workouts, and only the route tells them apart.

> **FR** — « N'importer que les séances avec un parcours GPS. Les séances sans
> position (détections automatiques d'Apple Santé, tapis, vélo
> d'appartement, aviron) sont ignorées. »
>
> **EN** — "Import only sessions with a GPS track. Sessions without a
> position (automatic Apple Health detections, treadmill, stationary bike,
> rowing) are skipped."

> **FR** — « Withings ne propose pas d'API publique pour les parcours : cette
> connexion utilise votre compte Withings et peut cesser de fonctionner à
> tout moment. Votre mot de passe sert une seule fois à établir la connexion :
> il est conservé chiffré pendant l'exécution de la tâche (quelques minutes au
> plus), puis effacé ; la session Withings expire au bout d'un jour, vous
> resaisirez votre mot de passe à chaque reconnexion. Les activités importées
> restent privées jusqu'à ce que vous les publiiez. »
>
> **EN** — "Withings offers no public API for routes: this connection uses
> your Withings account and may stop working at any time. Your password is
> used once to establish the connection: it is kept encrypted while the task
> runs (a few minutes at most), then deleted; the Withings session expires
> after a day, so you will type your password again at each reconnection.
> Imported activities stay private until you publish them."

### 19.23d Zwift — on the Zwift connection card

Placement: the Zwift page of `/connections`, under the sign-in form
(e-mail and password only; the range is the connected card's retrieval form)
and on the connected card. Persistent and non-dismissible
(`[devdoc:remote-imports]`). Without equipment, the unlink checkbox of
§19.24 names the workouts only. The refresh token is the only credential and
lasts eight days without a sync: the copy says so, and the connected card's
« Connexion valable jusqu'au » shows its end. Zwift exposes only the newest
250 activities, which the copy also says.

> **FR** — « Zwift ne propose pas d'API publique : cette connexion utilise
> votre compte Zwift et peut cesser de fonctionner à tout moment. Votre mot
> de passe sert une seule fois à établir la connexion : il est conservé
> chiffré pendant l'exécution de la tâche (quelques minutes au plus), puis
> effacé ; seul le jeton de renouvellement est conservé, chiffré, et il expire
> après huit jours sans synchronisation. Zwift n'expose que vos 250 dernières
> activités. Les activités importées restent privées jusqu'à ce que vous les
> publiiez. »
>
> **EN** — "Zwift offers no public API: this connection uses your Zwift
> account and may stop working at any time. Your password is used once to
> establish the connection: it is kept encrypted while the task runs (a few
> minutes at most), then deleted; only the refresh token is stored, encrypted,
> and it expires after eight days without a sync. Zwift exposes only your 250
> newest activities. Imported activities stay private until you publish
> them."

### 19.24 Disconnecting a service — in the unlink confirmation

Placement: the « Déconnecter » card of the service's page, above its button: the deletion
checkbox, checked by default with the live counts, and its consequence as the
hint; the confirmation dialog (§10.10) repeats the first sentence and the
withdrawal of publications.

> **FR** — « Déconnecter %{provider} révoque l'accès de cette instance.
> ☑ Supprimer aussi les %{workouts} activités et %{equipments} équipements
> importés depuis %{provider}. Les publications de ces activités sont
> retirées ; ce qui a déjà été reçu ailleurs ne peut pas être rappelé. Les
> activités conservées deviennent des activités ordinaires et ne seront pas
> réimportées. »
>
> **EN** — "Disconnecting %{provider} revokes this instance's access.
> ☑ Also delete the %{workouts} workouts and %{equipments} equipment items
> imported from %{provider}. Their publications are withdrawn; what was
> already received elsewhere cannot be recalled. Kept workouts become
> ordinary workouts and will not be imported again."

### 19.25 Automatic publishing — on the publishing profile form

Placement: the « Publication automatique » card of the profile form, as a
persistent `alert-warning` above the switch ([AUTO-PUBLISHING.md](AUTO-PUBLISHING.md)).
Non-dismissible. The switch is off by default; while the profile is not yet
automatic, turning it on also requires the acknowledgement checkbox. The values
interpolate `WorkoutAutoPublication`'s constants. Under the commute switch, a
sport exclusion fieldset offers every active sport as the workout list's own
`form-selectgroup` pills (§10.6); none ticked excludes nothing, and the hint
says so.

> **FR** — « Seules les activités de moins de 7 jours importées après
> l'activation sont concernées. Les imports de plus de 5 fichiers et les
> récupérations par période depuis un service connecté ne sont jamais publiés
> automatiquement. Vos zones de confidentialité et les réglages de ce profil
> s'appliquent comme pour une publication à la main ; si la publication est
> refusée, rien n'est partagé et vous êtes prévenu. »
> « Sans délai, l'activité est partagée dès la fin de son analyse, et les
> copies reçues par d'autres instances ne peuvent pas être rappelées.
> Choisissez un délai pour garder le temps de vérifier, reprogrammer ou
> annuler. »
> ☐ « Je comprends que mes nouvelles activités seront publiées sans autre
> confirmation de ma part. »
>
> **EN** — "Only workouts less than 7 days old imported after you turn it on
> are affected. Imports of more than 5 files and date-range retrievals from a
> connected service are never published automatically. Your privacy zones and
> this profile's settings apply as for a publication by hand; if publishing is
> refused, nothing is shared and you are told."
> "Without a delay, the workout is shared as soon as its analysis completes,
> and copies received by other instances cannot be recalled. Choose a delay to
> keep time to check, reschedule or cancel."
> ☐ "I understand that my new workouts will be published without any further
> confirmation from me."

While a profile is automatic, the import surfaces (`/workout_imports/new`,
`/connections` and each service's page) carry an `alert-warning` naming each
automatic profile with its audience, delay and exclusions (commutes and
sports), the same rules, and a link to the profiles; the profile list carries
it too, or introduces the option in an `alert-info` while every profile is off.
A waiting automatic publication leads the workout's sharing card with « Ne pas
publier », whose confirmation reads:

> **FR** — « Rien n'a été partagé. L'activité reste non publiée ; vous pourrez
> la publier à la main à tout moment. »
>
> **EN** — "Nothing was shared. The workout stays unpublished; you can publish
> it by hand at any time."

### 19.26 API tokens and webhooks — on `/settings/api`

Placement: the token creation form carries the first text as a persistent
`alert-warning` above its submit; the page that shows a new token carries the
second beside the secret; the webhook form carries the third as a persistent
`alert-warning`. None is dismissible (`[devdoc:api]`).

> **FR** — « Un jeton d'API agit en votre nom, sans double authentification,
> avec les permissions que vous cochez — y compris sur vos activités non
> publiées. Avec la permission de publier, un programme peut partager vos
> activités sans autre confirmation de votre part. Ne cochez que ce dont le
> programme a besoin. »
>
> **EN** — "An API token acts on your behalf, without two-step verification,
> with the permissions you tick — including on your unpublished workouts.
> With the permission to publish, a program can share your workouts without
> any further confirmation from you. Tick only what the program needs."

> **FR** — « Copiez ce jeton maintenant : il ne sera plus jamais affiché.
> Gardez-le comme un mot de passe ; s'il fuit, révoquez-le. »
>
> **EN** — "Copy this token now: it will never be shown again. Keep it like a
> password; if it leaks, revoke it."

> **FR** — « Allure envoie à cette adresse, à chaque événement choisi, un
> résumé signé : identifiants, mesures, noms des comptes qui commentent ou
> réagissent. Jamais de tracé ni de fichier. Ce qui a été envoyé ne peut pas
> être rappelé. »
>
> **EN** — "For each chosen event, Allure sends this address a signed summary:
> identifiers, metrics, the names of accounts that comment or react. Never a
> track or a file. What has been sent cannot be recalled."

### 19.27 Location for AI assistants — on the token creation form

Placement: under the « Localisation pour les assistants IA » radio list of the
token creation form, a persistent `alert-warning`, not dismissible
(`[devdoc:mcp]`). The creation mail repeats the level in one sentence
for `filtered` and `raw`.

> **FR** — « Allure ne peut pas savoir où un assistant envoie ce qu'il lit :
> c'est le détenteur du jeton qui décide. Un modèle qui tourne sur votre
> propre machine y garde vos tracés ; un assistant commercial les envoie à son
> fournisseur. »
>
> **EN** — "Allure cannot know where an assistant sends what it reads: whoever
> holds the token decides. A model running on your own machine keeps your
> tracks there; a commercial assistant sends them to its provider."

### 19.28 Push content — on the « Sur cet iPhone » card

Placement: the last line of the card (§7.7), muted, with a lock glyph, always
visible while the card is (`[devdoc:push]`). With « Masquer le contenu »
on, the iPhone shows the generic sentence instead of the inbox's.

> **FR** — « Le contenu est chiffré pour cet iPhone ; ni le relais d'Allure ni
> Apple ne peuvent le lire. »
>
> **EN** — "The content is encrypted for this iPhone; neither Allure's relay
> nor Apple can read it."

> **FR** — « Vous avez une nouvelle notification »
>
> **EN** — "You have a new notification"

---

### 19.29 Account export and deletion — on `/settings/account`

Placement: the export card states what the archive holds and what it never
holds; the deletion card states the window, then what leaves, then what stays
on other servers, above the username field, the acknowledgement checkbox and
the danger button, whose confirmation dialog (§10.10) repeats the window
(`[devdoc:account]`). The values interpolate
`Users::DeletionSchedule::GRACE`.

> **FR** — « Elle ne contient aucun secret : ni mot de passe, ni double
> authentification, ni jeton d'API, ni identifiant de service connecté. »
> « La suppression a lieu 7 jours après votre demande. Pendant ce délai, votre
> compte est désactivé : vos publications et vos segments ne sont plus
> visibles, rien n'est envoyé aux autres serveurs, et vous pouvez annuler en
> vous reconnectant. » « Les autres serveurs qui ont reçu vos publications sont
> prévenus de la suppression, mais les copies déjà récupérées ne peuvent pas
> être rappelées. Votre nom d'utilisateur ne pourra plus être utilisé sur cette
> instance. »
>
> **EN** — "It holds no secret: no password, two-step verification, API token
> or connected-service credential." "Deletion happens 7 days after your
> request. During that time your account is deactivated: your publications and
> segments are no longer visible, nothing is sent to other servers, and you
> can cancel by signing in again." "The other servers that received your
> publications are told about the deletion, but copies already fetched cannot
> be recalled. Your username can never be used again on this instance."

### 19.30 Manual entry — on the manual panel and the entry's page

Placement: the `alert-info` note leading the « Saisie manuelle » panel of the
import page, and the muted line under the summary of the entry's page
(`[devdoc:manual-entry]`). Both say what a typed figure counts for and
that the entry cannot be published.

> **FR** — « Saisissez une activité sans fichier, une séance en salle ou une
> sortie dont la montre n'a rien enregistré. Elle compte dans vos totaux et vos
> statistiques, mais ni dans vos records ni sur les segments, et elle ne peut
> pas être publiée. » « Saisie à la main : cette activité compte dans vos
> totaux, vos statistiques et l'usure de votre équipement, mais ni dans vos
> records, ni dans vos meilleurs efforts, ni sur les segments. Sans parcours,
> elle ne peut pas être publiée. »
>
> **EN** — "Enter an activity without a file: an indoor session, or an outing
> your watch did not record. It counts in your totals and statistics, but not
> in your records or on segments, and it cannot be published." "Entered by
> hand: this activity counts in your totals, your statistics and your
> equipment wear, but not in your records, your best efforts or on segments.
> Without a route, it cannot be published."

### 19.31 Weather — on `/settings/weather` and the weather card

Placement: under the consent switch of `/settings/weather` ([devdoc:weather]), the sentence naming what leaves the instance; on the profile form,
the `weather` setting's hint; on a sensor-only card, the warning that a
device's reading is not the air temperature.

> **FR** — « Activer la météo autorise cette instance à envoyer à Open-Meteo,
> pour chaque activité, des positions arrondies à environ 10 km, leur altitude
> et les heures de l'activité. Rien n'est partagé sans votre accord dans un
> profil de publication. » « Partage un résumé de la météo rencontrée
> (conditions, températures, vent, précipitations, part de vent de face).
> Jamais la météo heure par heure. Désactivé par défaut. » « Mesurée par votre
> appareil : au soleil ou contre le corps, il indique souvent plus chaud que
> l'air. »
>
> **EN** — "Enabling weather allows this instance to send Open-Meteo, for each
> workout, positions rounded to about 10 km, their elevation and the workout's
> hours. Nothing is shared unless you choose it in a publishing profile."
> "Shares a summary of the weather met (conditions, temperatures, wind,
> precipitation, headwind share). Never the hour-by-hour weather. Off by
> default." "Measured by your device: in the sun or against the body, it often
> reads warmer than the air."

### 19.32 Heart rate — on `/settings/heart-rate` and the publishing profile form

Placement: at the foot of `/settings/heart-rate` (`[devdoc:heart-rate]`),
with the lock glyph; under the « Capteurs » metric group of the publishing
profile form, described-by of both heart-rate boxes (§3.6). New profiles start
with both boxes unticked.

> **FR** — « Ces réglages et tout ce qui en découle — zones, temps par zone,
> charge — restent privés : ils ne sont jamais publiés ni fédérés. » « La
> fréquence cardiaque est une donnée de santé : elle n'est partagée que si
> vous cochez ces cases. Vos zones et votre fréquence maximale ne le sont
> jamais. »
>
> **EN** — "These settings and everything derived from them — zones, time in
> zone, load — stay private: they are never published or federated." "Heart
> rate is health data: it is shared only if you tick these boxes. Your zones
> and maximum heart rate never are."

### 19.33 Training load — what the figures are

Placement: the « Comment lire ces chiffres » fold of the `/me` training-load
card, the short ⓘ of the same card, and the load line of the « Zones
cardiaques » tab (`[devdoc:heart-rate]`). The figures are never
presented as comparable with another application or another person, and a
missing heart rate is never presented as estimated.

> **FR** — « Ces points sont propres à Allure : ils ne se comparent ni à la
> charge, ni à la condition ou à la forme d'autres applications, ni d'une
> personne à l'autre. Suivez leur évolution. » « Une séance sans fréquence cardiaque
> compte pour zéro ; une séance où elle n'a été enregistrée qu'en partie ne
> compte que cette partie. Rien n'est estimé à sa place. »
>
> **EN** — "These points are Allure's own: they compare neither with another
> application's load, nor with its fitness or form, nor from one person to
> another. Follow how they change." "A session without heart rate counts as
> zero; a session where it was recorded only in part counts that part only.
> Nothing is estimated in its place."

### 19.34 Owner photo originals

On the owner's Photos card, always:

- FR : « Ces photos restent privées. Les originaux sont conservés pour vous,
  avec leurs métadonnées, dont leur éventuelle position GPS. »
- EN: “These photos stay private. Originals are kept for you with their
  metadata, including any GPS location.”

Photo deletion confirms that the original and resized copies will be deleted,
and that a publication sharing the photo keeps its own copy until it is
withdrawn (« Une publication qui partage cette photo garde sa propre copie
jusqu'à ce que vous la retiriez. »). It never claims a source deletion
withdraws a publication.

### 19.35 Sharing photos — on the publishing profile form and the publish form

On the profile form, under « Photos » (off by default):

- FR : « Partage des copies des photos que vous choisissez à la publication,
  sans leurs métadonnées. Une photo peut quand même montrer où elle a été
  prise. Les photos prises dans une zone de confidentialité sont écartées,
  sauf si vous les choisissez. »
- EN: “Shares copies of the photos you select when publishing, without their
  metadata. A photo can still show where it was taken. Photos taken inside a
  privacy zone are left out unless you choose them.”

Under « Position des photos sur le parcours »: it is a distance along the
published route, never the photo's GPS position.

On the publish and replace forms, the « Photos à partager » list appears only
when the selected profile shares photos; otherwise the form says « Ce profil ne
partage pas les photos. » beside a link to the profiles. The list says copies
are made now and do not follow later edits; a photo inside a privacy zone
carries the « Dans une zone de confidentialité » badge, starts unticked, and
the notice « Une photo prise dans une zone de confidentialité peut montrer où
vous habitez ou séjournez. Elle est écartée sauf si vous la cochez, et elle
est alors partagée sans aucune position. » precedes the acknowledgement
checkbox the publish requires. The list always ends with « Une photo peut
montrer où elle a été prise, même sans sa position GPS. »

### 19.36 Strava archive — on the « Archive Strava » import panel

Placement: the panel of the Strava archive source (`[devdoc:strava-archive]`), in an `alert-info` above its submit. Persistent and non-dismissible.

> **FR** — « Seuls activities.csv, le dossier activities, bikes.csv et
> shoes.csv sont lus ; les photos, abonnés, commentaires et le reste de
> l'archive sont ignorés. Rien ne quitte cette instance, et les activités
> importées restent privées jusqu'à ce que vous les publiiez. L'équipement
> nommé dans l'archive et absent de votre compte est créé. »
>
> **EN** — "Only activities.csv, the activities folder, bikes.csv and shoes.csv
> are read; photos, followers, comments and the rest of the archive are
> ignored. Nothing leaves this instance, and imported activities stay private
> until you publish them. Gear the archive names that your account lacks is
> created."

While photos are on (`[devdoc:photos]`), the first sentence names the
`media` folder instead of ignoring the photos, says the photos stay private
with the activities, and that they count towards the account's storage
(« … les activités importées et leurs photos restent privées jusqu'à ce que
vous les publiiez … ; les photos comptent dans votre espace de stockage. »).

A second sentence in the same alert says that activities typed in by hand on
Strava become manual entries, that a long history can take hours while maps, places and
segments fill in, and that importing the same archive again creates no
duplicate.

### 19.37 Instance funding — on `/funding` and profile settings

The manual-flow wording is the reference:

> **FR** — « Votre soutien aide à payer l'hébergement de cette instance. Il est
> facultatif et ne débloque aucune fonctionnalité. Le paiement se fait sur le
> site du prestataire. Le badge est valable un an à partir du paiement ; vous
> pouvez le masquer et choisir sa couleur. »
>
> **EN** — "Your contribution helps pay for hosting this instance. It is
> optional and unlocks no features. Payment takes place on the provider's
> website. The badge lasts one year from payment; you can hide it and choose
> its colour."

Automated-subscription wording (shown for a provider-backed tier, with the
cancellation sentence beside « Gérer mon abonnement »):

> **FR** — « Votre abonnement se renouvelle automatiquement chaque année. La
> résiliation se fait dans le portail du prestataire ; le badge reste valable
> jusqu'à la fin de la période déjà payée. Masquer le badge ne résilie pas
> l'abonnement. »
>
> **EN** — "Your subscription renews automatically every year. Cancellation
> happens in the provider's portal; the badge remains valid until the end of
> the period already paid. Hiding the badge does not cancel the subscription."
>
> **DE** — « Dein Abonnement verlängert sich automatisch jedes Jahr. Die
> Kündigung erfolgt im Portal des Anbieters; das Abzeichen bleibt bis zum Ende
> der bereits bezahlten Periode gültig. Das Ausblenden des Abzeichens kündigt
> das Abonnement nicht. »
>
> **ES** — « Tu suscripción se renueva automáticamente cada año. La cancelación
> se realiza en el portal del proveedor; la insignia sigue siendo válida hasta
> el final del periodo ya pagado. Ocultar la insignia no cancela la
> suscripción. »
>
> **NL** — « Je abonnement verlengt automatisch elk jaar. Opzeggen gebeurt in
> het portaal van de provider; de badge blijft geldig tot het einde van de al
> betaalde periode. De badge verbergen zegt het abonnement niet op. »

Badge accessible label: « Soutient cette instance » / "Supports this instance".
No distinction, nag or negative signal identifies a non-contributing account.

Badge accessible label: « Soutient cette instance » / "Supports this instance".
No distinction, nag or negative signal identifies a non-contributing account.

### 19.38 Sharing whole-history statistics and records — on profile settings

Placement: the persistent info panel in the independently saved
« Statistiques et records partagés » / "Shared statistics and records" card.
Each block has an independent native audience select: « Ne pas partager » /
"Do not share" (`none`, the default), « Mes abonnés acceptés » / "My accepted
followers" (`followers`), « Tous les membres de cette instance » / "All members
of this instance" (`members`). Choosing one is not consent to the other.
The intro, labelled selects and hints precede the panel; the card's submit
explicitly saves these sharing choices. Existing enabled boolean preferences
migrate to `members`, disabled ones to `none`, never to a broader audience.
An « En savoir plus » link after the panel opens the publishing help (§20.20),
which distinguishes these optional whole-history figures from publications.

> **FR** — « Ces chiffres portent sur tout votre carnet, y compris vos activités
> non publiées. Pour chaque bloc, vous choisissez qui peut le voir : vos abonnés
> acceptés ou tous les membres de cette instance. Aucun titre, date, lien ni
> parcours d'activité n'est partagé. Ces chiffres ne sont pas envoyés aux autres
> instances. « Ne pas partager » retire le bloc de votre profil. »
>
> **EN** — "These figures cover your whole workout history, including
> unpublished workouts. For each section, choose who can see it: your accepted
> followers or every member of this instance. No workout title, date, link or
> route is shared. These figures are not sent to other instances. ‘Do not share’
> removes the section from your profile."

The German, Spanish and Dutch texts faithfully translate the same consent.
Nothing is calculated or embedded in the public profile while its corresponding
audience is `none` or the viewer is not allowed, including chart payloads and
fallback tables. No hidden placeholder or owner-only preview implies sharing.

### 19.39 Being found by name — on profile settings and `/people`

Placement: the « Découvrabilité » / "Discoverability" fieldset of the
independently saved sharing card on `/settings/profile`, and the note under the
search box on `/people` while the viewer is hidden. The fieldset is a radio
group, `none` selected by default for every account: « Personne » / "Nobody"
and « Les membres de cette instance » / "Members of this instance". Each option
carries its own consequence line, and one hint states what a result shows.

> **FR** — « La recherche ne montre que votre avatar, votre nom et votre
> identifiant. Votre biographie, vos lieux et vos activités n'y figurent
> jamais. »
>
> **EN** — "Search shows only your avatar, name and handle. Your biography,
> places and activities never appear there."

The hidden note on `/people` is a persistent info panel, not a warning:

> **FR** — « Vous n'apparaissez pas dans la recherche par nom : seules les
> personnes qui saisissent votre identifiant complet peuvent vous trouver. »
>
> **EN** — "You do not appear in name search: only people who type your full
> handle can find you."

It ends with a link to the settings card. The German, Spanish and Dutch texts
faithfully translate both sentences. A hidden account is never presented as
incomplete or as having lost something; the exact handle always works.

## 20. Screen anatomies

Block diagrams of the twenty-two screens that define the product. Order is
top-to-bottom; each block is a card unless noted.

### 20.1 `/feed` — Feed

```
┌ page header ────────────────────────────────────────────┐
│ pretitle: —                    [ Public ◯ ⓘ ]           │
│ h1: Publications                                         │
└──────────────────────────────────────────────────────────┘
   centered single column (≈ 720px)
──────────────────── h2: Aujourd'hui ──────────────────────
┌ publication item (the whole card is the link) ───────────┐
│ (◍) Marie Dufour  @marie   [Vous] [Public] [Autre inst.] │
├──────────────────────────────────────────────────────────┤
│ [ route image | pending skeleton | unavailable frame ]   │
├──────────────────────────────────────────────────────────┤
│ (▲) h3: Sortie du matin              [Trajet] [Record]   │
│ Hier 07:12                                               │
│ ┌ DISTANCE ┐ ┌ TEMPS EN MVT ┐ ┌ ALLURE ┐ ┌ D+ ┐          │
│ │ 12,4 km  │ │ 1:02:11      │ │ 5:01/km│ │180 m│        │
│ Trois lignes de description au plus…                     │
│ ⌚ Garmin Forerunner 255                                  │
└──────────────────────────────────────────────────────────┘
──────────────────── h2: Hier ─────────────────────────────
… endless scroll (pagination nav is the <noscript> fallback) …
```

The author header is mandatory: avatar, display name and `@username`, all
linked to the profile (`@user@instance` and the « Autre instance » badge for
remote accounts). The full item anatomy and the day separators are specified
in §8.3. The `Public` switch sits in the header, applies on change, and is a
URL parameter so back/forward and sharing keep the choice; its ⓘ tooltip
explains what it adds and is keyboard-reachable.

Empty: *"Aucune publication pour le moment. Les activités publiées de cette
instance apparaîtront ici."* → `Importer une activité`. The feed is
members-only ([ACCESS.md](ACCESS.md)), so there is no signed-out empty state.

### 20.2 `/me` — Personal hub

Signed-in home: `/` redirects here.

```
┌ page header ─────────────────────────────────────────────┐
│ (avatar) h1: Marie Dufour                                │
│          @marie · 178 activités                          │
└──────────────────────────────────────────────────────────┘
  (Tous 16) (Vélo 7) (Course 5) …   [semaine|30j|année|tout]
  sport pills, no card; phones: one row of two native selects
  [Tous les sports ▾]                       [30 jours ▾]
┌ période ─────────────────────────────────────────────────┐
│  15        │ 296,9 km  │ 3 892 m   │ 16 h 18 min         │
│  ACTIVITÉS ▲│ DISTANCE ▲│ DÉNIVELÉ ▼│ TEMPS ▲             │
│ ──────────────────────────────────────────────────────── │
│  INTENSITÉ ⓘ         4 semaines actives sur 5   ‹ Auj. › │
│  onde hebdo : rose = période, gris = historique,          │
│  défile vers la gauche pour le passé                      │
│  ⚡ Pic : semaine du 14 septembre · 2 activités · 67,1 km…│
└───────────────────────────────────────────────────────────┘
┌ activity calendar ⓘ ──────────────────────────────────────┐
│ [Durée|Distance|Activités] ‹ avr. – sept. 2026 ›        │
│ [ cellules 13 px fixes, plus de semaines si plus large ] │
│ années sous la grille · légende Moins ▁▂▃▄ Plus          │
└───────────────────────────────────────────────────────────┘
┌ répartition des sports (8) ─┐ ┌ régularité (4) ───────────┐
│ donut, métrique, légende %  │ │ Voir les statistiques ›   │
│ ‹ Voir les données ›        │ │ Cette semaine vs moy. 4sem│
│                             │ │ séries, jours actifs      │
└─────────────────────────────┘ └───────────────────────────┘
┌ segments récents ───────────┐ ┌ records récents ────────┐
│ Voir les segments ›         │ │ Voir les records ›      │
│ date, segment, sport, temps,│ │ 3 latest: record / sport│
│ rangs (phones: stacked rows)│ │ valeur ›  (row = link)  │
└─────────────────────────────┘ └─────────────────────────┘
┌ activités récentes (12, 4 on phones)   Tout afficher › ┐
│ Hier 07:30 · 12,4 km · 1 h 25 min · 4:38 /km · ↑ 320 m  │
│ grille 2 / 3 / 4 colonnes, jamais de rangée incomplète  │
└───────────────────────────────────────────────────────────┘
```

### 20.3 `/workouts/:id` — Workout detail

Single scroll, one layout for the web, phones and the iOS companion. There is
no sticky section navigation. The map leads the page; from `lg` (992 px) up it
is the sticky left rail beside summary, profile and analysis. The header menu
is the only place for the original file download and the workout deletion:
there is no original-data card and no danger zone.

```
┌ page header ─────────────────────────────────────────────┐
│ (◍) h1: Sortie du matin                   [Publier] [⋯] │
│     Par Marie                     (autre compte)         │
│     Course à pied · lun. 3 mars 07:30                    │
│ (⌖) Valmorin · Cimefroide · Rochelune                        (owner) │
│ (🌐) [ Record ] [ Trajet ] ⌚ appareil                   │
│  ⋯: Modifier (< md) · Créer un segment · Enregistrer en  │
│     itinéraire · Télécharger le fichier d'origine ·      │
│     Régénérer l'image · Altitudes : passer au service /  │
│     revenir à l'appareil (propriétaire, estimation       │
│     activée et profil enregistré requis) ·               │
│     Supprimer l'activité                                 │
└───────────────────────────────────────────────────────────┘
[Carte]       map card, first under the header; sticky left rail from lg;
              cooperative gestures on touch screens (§15.2); its text
              summary is screen-reader-only
[Résumé]      four primary tiles: distance, temps en mouvement, the sport's
              preferred average, dénivelé + (power for a fixed-basis sport
              that recorded it, and in place of the speed for a power-led
              virtual sport); a record value carries the trophy card stamp
              secondary metrics in 2 / 3 / 4 columns by the card's width,
              folded on phones behind « Plus de mesures (N) » — N counts the
              recorded ones only; a metric the file did not record is never
              a dash, it is named once in « Non mesuré pour cette activité :
              fréquence cardiaque, puissance. », which folds with them
              an elevation-less owner workout carries a one-line « Altitudes »
              notice under the tiles (enable estimation · estimate · retry)
[Social]      the social row (§10.17) right under the summary, with a
              publication: [💬 3] → the thread's page, below lg only, on the
              left; the reactions on the right, on every screen
[Météo]       weather card ([devdoc:weather]) after the Analyse card
              (after the profile for a reader); the header badge row carries
              its badge (condition icon, mean temperature, linking here): the
              condition icon (an animated monochrome Meteocons SVG, day or
              night variant, in the primary on a primary-tint tile; static
              under reduced motion, §16) beside the temperature range and the
              condition; the badge's icon is drawn larger than its type but
              never makes the badge taller than its neighbours;
              ressenti, vent (an SVG arrow pointing
              where it blows, km/h or mph, rafales), humidité, précipitations
              when above zero, the device's own « Temp. capteur »; the
              « Vent pendant l'effort » bar (face primary, côté muted, dos
              success, legend as text) and the mean headwind; the
              « Données météo : Open-Meteo.com » attribution in the footer.
              Owner states: pending, failed (Réessayer), missing (Récupérer
              la météo); a reader sees the frozen summary only when the
              profile shared it; a recording with only the device's
              readings shows « Temp. capteur » and the §19.31 sensor note
[Description] its own card when present: description · notes privées (owner)
[Profil]      elevation chart card (§15.1): floating axes, whole-distance
              ticks, selection zoom with « Vue d'ensemble »; « Voir les
              données » from md up (screen-reader list on phones); the
              estimated-elevation marker is an icon-only pill; the route
              steps are one horizontal line, each name whole, scrolling with
              faded edges so the card keeps its height across analysis tabs;
              toponymy places numbered on the curve, the active analysis
              tab's layers and steps ([SMART-LAPS.md](SMART-LAPS.md))
[Analyse]     one owner card, only non-empty tabs on one sideways-scrolling
              line with faded edges, first one active:
              Segments · Tours détectés · Montées · Descentes · Arrêts ·
              Efforts · Tours enregistrés · Intervalles · Météo ·
              Meilleurs efforts · Qualité des données (§15.5)
              Météo: the start, each whole hour and the finish (heure,
              conditions with a static icon, température, ressenti, vent,
              rafales, pluie);
              Intervalles gains « Vent » (de face / de dos / neutre) when the
              workout has weather; while Météo is active, weather markers
              (start, then each change of weather, ≥ 8 % apart, ≤ 6) sit on
              the profile as rose pills holding the white animated icon and
              on the map as rose panels (icon, temperature, wind arrow true to
              north)
              tables and stacked lists switch on the card's own width (36rem);
              HR, cadence, power, trigger and the effort date only from 56rem,
              except a power-led ride's climb power, which stays at every width
              hover/focus a row shades its range on the chart and thickens the
              matching slice on the map, both in the theme ink; tap pins it,
              Escape clears it
[Commentaires] full-width card (§10.20) from lg, anchor #comments: the thread,
              the composer with its §19.21 sentence and its submit on the
              right, the owner's close/reopen as a small primary ghost button;
              below lg the card lives on /workouts/:id/comments
[Publications] full-width owner card: header « Retirer toutes les
              publications » (ghost danger) while one is live; one row per
              publication, at most one per audience ([PUBLISHING.md](PUBLISHING.md)) —
              the scheduled ones (§19.19 notice, reschedule, cancel, publish
              now) then the active ones, narrowest audience first (audience,
              profile, date, « Voir comme vos lecteurs », shared media,
              Remplacer, Retirer, a distribution alert only when sending
              failed); « Ajouter une publication » closes the list and
              unfolds the publish form limited to the free audiences, or
              stays disabled with its reason (every audience taken, followers
              turned off). Without a publication the publish form opens the
              card: profile, delay, the §19.1 lists and warnings, « En savoir
              plus » for the delay and safety hints; a row's « Remplacer »
              unfolds the same form under the list, limited to its own
              audience and the free ones
[Participants] full-width owner card (§10.18): « Ajouter un participant » in
              the header, the §19.20 sentence, one row per participation
```

A **positionless recording** (`[devdoc:no-gps]`) follows the same layout without
its geography: no map rail, so the summary leads the single column and the
chart plots elapsed minutes when the file recorded no distance; a neutral
« Sans position GPS » pill sits in the badge line; the elevation figures and —
on a duration-only session — the distance and pace/speed tiles are absent, and
the fourth primary tile is average power, then average heart rate, then
calories; the analysis card has no Segments tab; the `⋯` menu keeps the
original-file download and the deletion alone; the sharing card states that
there is no route to share instead of offering the publish form, and the
workout card shows the no-position state where the route image would be.

A **manual entry** (`[devdoc:manual-entry]`) is its owner's alone and has
its own template: the header with « Modifier » and a `⋯` menu holding the
deletion, the « Saisie manuelle » pill and the commute badge, the summary of
the typed figures only (distance, moving time and pace/speed when a distance
was entered, then the ascent, power, heart rate and calories that were; no
« not recorded » line), the §19.30 line under it, and the description card. No
map, chart, analysis, comments, sharing or participants card. In the list its
card top shows the pencil and « Saisie manuelle » where the route image would
be, and the table prints a dash for a figure left empty.

`?as=publication` renders the owner's page exactly as a reader of one active
publication sees it — the one `&audience=` names, the narrowest by default —
with its sanitized track and chart, no owner section, under an info line with
« Revenir à ma vue »; without an active publication the parameter is ignored.
A reader is always served one version, the narrowest audience they may read;
the owner's header, cards and table carry one audience badge per active
publication. On a workout published to several audiences the comment composer
lets the owner pick the thread, and a followers comment carries the
« Abonnés » badge for readers who see more than one thread.

The `md` sport tile leads the identity block at the left of the `h1`; only
another account's workout carries the author line, under the title and in the
same column as the icon, followed by the sport name and the date. The
owner-only place line and the badge line (the audience pill, record,
commute, device) start below at the left margin — not indented under the icon;
an empty badge line is not rendered. The tile stays decorative: the translated
sport name is printed under the title. The owner's actions share the title's
row at every width: Publish (while unpublished), Edit from `md` and the `⋯`
menu, a 40 px `btn-icon` matching the buttons beside it. Below `md` Publish and
`⋯` stack in a narrow right-aligned column that spans the title and the next
line, so the place or badge line rises beside `⋯`.

Non-owner: header, résumé (permitted metrics only), carte and profil if the
profile permits, and nothing else. No trace of the withheld sections.

An invited or confirmed participant is the exception, and only before the
source is published to them: they get the metrics-only presentation of the
credited set (§19.20) with the participants card and the confirm, decline, or
withdraw action, and no map, chart, analysis, or original data. Once the
source is published and viewable by them, the standard publication
presentation applies and the « Avec @X » badge joins the header metadata line.

### 20.4 `/workouts` — Workout list

```
┌ page header ── [⌁] h1: Mes activités              [▦|☰] ┐
│                    37 activités sur 178 (live)            │
│ sport pills: (Course à pied 42) (Vélo 37) …  ← scrolls on │
│                                                 phones    │
│ [📅 Cette année ▾] [⇅ Date (plus récentes) ▾]  [⚙ Filtres 2]│
│ chips: (Rochelune ×) (vélotaf ×)  Effacer les filtres          │
└───────────────────────────────────────────────────────────┘
  drawer (closed until asked; right panel, bottom sheet on
  phones): dates (custom period) · publication · trajet ·
  lieu · recherche · [Réinitialiser] [Afficher les résultats]
▦ cards: the `/me` presentation —      ☰ table: date · sport ·
  fully clickable cards (route          titre · distance ·
  image, smart date, compact            temps · D+ · état
  metrics, no footer), endless
  scroll (<noscript>: pagination)
  sectioned by month while the
  list is date-sorted: an `h2.hr-text`
  rule per month (§10.6 style, like
  the feed's days)
```

The card view reproduces the `/me` recent-workout cards and scrolls endlessly
(§10.14), sectioned by calendar month — in the viewer's zone — while the list
is date-sorted: the month is an `h2.hr-text` rule spanning the grid, and the
endless scroll drops a separator a fetched page repeats, exactly like the
feed's day separators (§8.3). Sorting by anything else drops the sections, so
a rule never contradicts the order. The card badges are icon-only and an
unpublished card carries none (§10.4). The table view scrolls endlessly too
(`<noscript>`: pagination): the desktop rows and the phone list are both item
containers, and below `md` it becomes the §12.3 list of stacked rows in a
card — never the card grid, so the view switch keeps its meaning on a phone.
Its sortable headers write the same `sort` value as the sort select (§10.5);
rows a fetched page appends join the bulk selection's count and tri-state,
and arrive selected under the « select all filtered » scope. The page header
leads with the section tile (`ti-activity`, the navigation icon) beside the
title, like the workout page's sport tile; the live result count sits under
the title, and the only header control is the card/table switch as a
`nav-segmented` icon pair (§10.15) — no import or new-workout action: the
topbar import button is the standing entry. The toolbar and the drawer follow
§10.6. The period presets are the hub's calendar windows, so « Voir tout » on
`/me` opens the list on the same window and sport. An account with no
workout gets the empty state alone, without the toolbar or the view switch.

The table view also carries the bulk workflow (§10.19). Its two follow-on
screens are ordinary pages, never modals:

```
┌ /workouts/bulk/:id — vérification (brouillon) ────────────┐
│ h1: Changer le sport de 137 activités                     │
│ 137 activités · du 3 mai au 28 septembre                   │
│ Sports : Course à pied × 120 · Vélo × 17                   │
│ Publications : 94 publiées · 2 programmées                 │
│ ⚠ 3 activités sans fichier d'origine seront ignorées.      │
│ Sport [ Choisir ▾ ]                                        │
│ hint §19.4 · [ Annuler ] [ Changer le sport ]              │
└────────────────────────────────────────────────────────────┘
┌ /workouts/bulk/:id — progression ──────────────────────────┐
│ barre · 45 modifiées · 3 ignorées · 0 échouée · 0 annulée  │
│ [ Annuler l'opération ]                                    │
│ table des activités : titre · état · raison                │
│ à la fin : [ Retour aux activités ] (+ toast)              │
└────────────────────────────────────────────────────────────┘
```

The review keeps the summary in a card and the operation form in a second card
(one concern per card, §14.1); the confirm button names the operation in the
plural. The progress page reproduces the batch-import anatomy (§20.5): status
badge, progress bar and counters, the per-activity table in the §12.2 style
with its phone list, cancellation while active, and the terminal summary with
a single return action. The `⋯`-less header carries the operation's own title,
never a raw identifier.

### 20.5 `/workout_imports/new` — Import

One surface for every import, with a source picker when more than one import
source is enabled (`[devdoc:import-sources]`). The picker is a pill tab list;
each source renders its own panel, and the shared options card sits below the
panels: the fallback sport, the single-file title, the equipment, the commute
flag and the notes. The former M1 single-file form (`/workouts/new`) redirects
here. The manual source (« Saisie manuelle »,
`[devdoc:manual-entry]`) is the exception: its panel is a form of its own,
and the upload form — panels, options and footer — hides while it is
selected.

```
┌ page header ── h1: Importer ─────────────────────────────┐
┌ sources ── [Fichiers] [Archive Strava] [iGPSPORT]        │
│            [Saisie manuelle] ────────────────────────────┐
┌ source panel ────────────────────────────────────────────┐
│ files:  dropzone — GPX, FIT, TCX, KML, KMZ · .gz · .zip  │
│ strava: how to request the archive (3 steps) · .zip ·    │
│         sport de secours (facultatif) · §19.36 ·         │
│         [Importer l'archive]                             │
│ device: [Connecter le compteur] · modèle (non testé) ·   │
│         série · batterie ·                               │
│         activités (case · date · taille) ·               │
│         [Tout sélectionner] · progression ·              │
│         [Importer la sélection] · journal                │
└───────────────────────────────────────────────────────────┘
┌ options ── titre (un seul fichier) · sport de secours ·  │
│            équipement · domicile-travail · notes         │
                                    [ Annuler ] [ Importer ]
```

The manual panel leads with the §19.30 note, then three cards: « L'activité »
(sport, local start with its time zone named, duration and moving time as
hours / minutes / seconds input groups, distance in km or mi, ascent in m or
ft — hidden and disabled for a sport that measures no elevation), « Mesures
facultatives » (average and maximum heart rate, calories, average power), and
the title, description, private notes and commute; the equipment card follows
when the account has some. Its own footer « Enregistrer l'activité » /
« Annuler ». A refused form returns to this panel with what was typed, each
refusal under its field (§14). The entry's edit page reuses the same form.

The file source keeps the footer submit; the device source owns its "Importer
la sélection" action, which downloads the selected FIT files over Web
Bluetooth, validates them, and submits the same batch form. A browser without
Web Bluetooth or a secure context shows the device requirements instead of
the controls. Once connected, the device panel names the model; a model not
yet verified on hardware carries a `bg-secondary-lt` « non testé » badge and a
secondary sentence saying the import should work and pointing at the
connection log. A device outside the iGPSPORT family is refused in the status
line with its name. The shared options apply to every file and device source.

The Strava archive source (`[devdoc:strava-archive]`) is an `archive` kind:
like a remote source it hides the shared options card and the footer submit,
since each activity brings its own title, type, texts, commute flag and gear.
Its panel carries one `.zip` field, an optional fallback sport (« Aucun
(ignorer l'activité) » by default), the §19.36 alert and its own « Importer
l'archive » button. A refused upload returns to this panel with the reason
under the field. Its batch page names each entry by the Strava activity name
with the archive member underneath, reads « Lecture de l'archive Strava… »
while the CSV is read, and lists under the summary the equipment it created
the photos it attached, those the archive lacked and those refused
(« 3 photos jointes · 2 photos absentes de l'archive · 1 photo refusée
(format, taille, limite par activité ou espace de stockage) »).

The title is revealed only when exactly one file is selected and that file
cannot hold several entries (a ZIP never reveals it; a bare track file, a
`.gz` or a `.kmz` does). Hiding it clears what was typed, and the importer
applies the title only when the batch holds one entry, so a batch never titles
every workout alike. The equipment, the commute flag and the notes apply to
every imported workout, and each hint says so.

While running, the same page becomes the progress view: overall progress bar,
counts (importées / échouées / doublons / annulées), per-entry table (§12.2),
cancel. Polling drives an `aria-live` region announcing transitions only. On
completion a toast fires (§10.8) and the summary offers "Voir les activités".

### 20.6 `/segments/:id` — Segment detail

Owner view:

```
┌ page header ── (◍) Segment · h1: name · badge d'état ─────┐
│                                             [Modifier] [⋯]│
┌ map (rail collant, gauche) ─┐ ┌ tuiles : Distance · D+ ──┐
│                             │ │ Mes efforts · Mon rang   │
│                             │ │ (laurier top 3) ·        │
│                             │ │ secondaires · profil     │
└─────────────────────────────┘ └──────────────────────────┘
┌ Classements · [Tout afficher] [Ne plus figurer] ──────────┐
│ §20.7 aperçu : top 10 par sport                           │
│ §19.6 état + note, sous le tableau                        │
┌ mes efforts · [Voir tout] ────────────────────────────────┐
│ Progression (dès 2 efforts) · [Voir les données]          │
│ tableau : coupe or/argent/bronze, allure                  │
```

The personal efforts card opens on the **Progression** chart once the viewer
has two efforts in one sport on the course, whatever its kind (segment, route,
loop): one chart per sport holding two efforts, each under its sport tile and
name when there are several (a sport with a single effort draws none), the
viewer's own times only, oldest to newest, one primary point per effort, the
time axis reversed so a faster effort sits higher and snapped on the clock.
The three best times keep their point and are marked by their trophy — gold,
silver, bronze, the same places as the efforts table (§10.4) — set beside it
at the end of a short 45° leader in the place colour, up and to the right,
mirrored near the right edge or the top of the plot so it stays in view. A thin (1.25 px) muted
grey line is the trend, robust to a bad day: a straight Theil–Sen line under
eight outings, a robust LOWESS curve from eight ([SEGMENTS.md](SEGMENTS.md)), each
outing counted once as the mean of its laps, drawn from three outings and
carrying no tooltip. It is drawn on a regular grid with straight segments,
never a spline (one overshoots, even runs backwards, beside a long gap), and
it is dotted where it rests on too few outings: all of it under five outings,
and across any gap between two outings longer than six months and than 15 %
of the history, from the last outing before to the first after. There is no
legend; the subtitle names the grey line and its dotted stretches.
The tooltip names the activity, its date, time, sport-preferred pace or speed,
its place and its gap to the record; on a pointer device a point opens its
activity. « Voir les données » holds the chronological table (date, activity
with its trophy, time, gap to the record), read by assistive technology only
on phones.

On desktop the map is the same sticky left rail as a workout detail, and the
details and the stored course profile scroll in the right column; the
Classements container and the personal efforts stay full width below. The
details card is a summary-tile grid, the workout summary's language (§10.2):
Distance and D+ lead for every viewer; a signed-in viewer adds **Mes efforts**
and, on a shared course, **Mon rang** — `3 / 12`, with the laurel-wreath
podium stamp in the place colour for a top-three place, `Non classé` for an
unlisted effort, `—` without one. A private course replaces **Mon rang**
with Participants and moves D− to the secondary line. Participants counts the
athletes the viewer sees ranked on a shared course ([SEGMENTS.md](SEGMENTS.md)),
never an unpublished effort; the secondary line keeps
pente moyenne, tolérance (owner), and the course metrics the primary grid did
not use. The
`[Tout afficher]` action mirrors the personal-efforts one and appears only when
a board section overflows the preview. The header `⋯` menu leads with the
participation toggle, then links to the source activity, or states that it was
deleted, then offers the type-labelled reversed copy of a segment or a route,
then carries the publication texts and actions — the §19.15 sentence,
the stale hint, the blocking warnings or private hint, then publish, republish
when stale, withdraw — and closes with the destructive delete item, behind the
same confirmation. The owner's publication state is the header badge
(§10.4, `Non publié`, `Publié : Public/Abonnés`, `Obsolète`). Narrower viewports keep
the linear details, map, profile order.

Shared view (visibility permitting): same header, description, map, course
metrics, stored profile, and Classements container, plus the viewer's own
efforts; a signed-in viewer gets the §19.6 toggle in the container header and
in a reduced `⋯` menu that also offers **Copier le segment** and **Copier en
sens inverse** — a private copy of the course, matched to the copier's own
workouts, the reversed one mirroring the geometry and elevation — without
`[Modifier]`, tolerance, or source workout. An all-sports course shows "Tous
les sports" and its board is split per sport (§20.7). A course received from
another instance has no stored profile and shows the unavailable state.

The index at `/segments` lists every course the viewer may see, one kind at a
time: **Segments**, **Routes** or **Loops**, chosen in the hub's period
control — a `nav-segmented` of labelled links above the list (§10.15), active
on the current kind with `aria-current`, every choice a plain GET URL. The
listing carries the readable shared courses (public ones, plus followers-only
ones from owners the viewer follows) and the viewer's own courses, private
ones included; routes and loops are never shared, so those kinds only ever
hold the viewer's own. The section heading stays **Segments**, the pretitle
and the switch name the kind, and the document title names the kind too. The
page header also carries the primary `[Nouveau segment]` action
(`[Nouvel itinéraire]` on Routes; none on Loops, which are only detected) and
the `[Découvrir]` action, which opens the discover page. Both stay beside the
title at every width, like the workout header (§20.3): on phones they stack
in a narrow column at the top right at their natural widths, and the primary
action reads `[Nouveau]`. The kind switch is a regular-size segmented control
that spans the width in equal parts on phones. The primary action
opens **Choisir une activité** (`/segments/new`, `?kind=route` for a route),
the first of two steps: a sentence names the next step, the owner's most
recent positioned recording leads as a shortcut card (its route image, facts,
places and `[Utiliser cette activité →]`), then a place search (the workout
list's autocomplete) and the other positioned recordings, newest first, as
endless-scroll rows whose whole row opens the selection step on that
workout's own creation page. While a place is searched the shortcut steps
aside and the list holds every match; without any positioned recording the
page offers `[Importer une activité]`. The courses are a
dense list, not a card grid — a course is compared on its figures, so a route
image per course spends the screen on little (§12):

```
┌ (Course à pied 4) (Vélo route 2)          ← sport pills, §10.6 ┐
│ [⇅ Plus récents ▾]                                              │
├─────────────────────────────────────────────────────────────────┤
│    Nom ⇅               Sport Distance⇅ D+⇅ Pente⇅ Profil Record⇅ Mon RP⇅ │
│ ⟋  Côte de la Citadelle (◍)  1,8 km  112 m 6,2 %  ▁▃▅█  (L)1 4:12  4:35   │
│    (⌖) Rochelune [À moi][Public]                          Grimpeur 7  (L)2 / 12│
└─────────────────────────────────────────────────────────────────┘
```

From `md` up it is a `table` in a card (§12.2), every row the course link
(the name's stretched link covers the row); below `md` it becomes the §12.3
list of stacked rows: glyph, name, place, then `sport · distance · D+ · pente`,
then `Record … · Mon RP …`, the mini profile on the right from `sm`. Each row
carries:

- the **course glyph**: the course line drawn as a 40 px SVG in the brand
  primary on a transparent ground, from the geometry simplified server-side.
  It is decorative (`aria-hidden`); the name carries the link and the label;
- the **name**, and for the viewer's own course in the Segments kind the
  **À moi** badge (§10.4 Mine) beside its sharing state (§10.4, in the
  course's own words), both icon-only with their tooltip on phones.
  Routes and loops are always the
  viewer's own and private, so they carry no badge;
- the **nearby place** under the name (`ti-map-pin`), geocoded once at the
  course midpoint; absent while pending, for a virtual course, or on an
  instance without geocoding — never a placeholder;
- the **sport** tile (`xs`, named by its tooltip). An all-sports course
  takes one row per sport it was run in, named `Nom du segment (Sport)` like
  its board sections (§20.7), each with that sport's record and best; while
  nobody ran it, one row with the neutral `ti-category` tile;
- distance, ascent and average grade, right-aligned in tabular figures, `—`
  when unknown;
- the **mini profile** (from `xl` in the table): a 96 × 28 SVG area under a
  primary line, drawn from the stored course profile, labelled
  `Profil d'altitude : de 120 m à 232 m`; nothing for a course without one;
- the **record**: the gold laurel and `1` (§10.4), the leader's time, and the
  leader of the row sport's board under the §20.7 alias rules (a real name
  only for the viewer, the accounts they follow, or on their own course; no
  avatar, no date). A private course has no board and reads
  `—`; the Routes and Loops kinds have no record column at all;
- **Mon RP**: the viewer's fastest effort in the row's sport, and under it their
  standing rendered by `rank_medal` (`2 / 12`, the laurel for a top-three
  place) when they rank on that board; `—` without an effort.

The toolbar is the §10.6 filter bar reduced to what the list needs: the sport
pills (shown from two sports; an all-sports course nobody ran stays under
every sport)
and the sort select, which is the phone's only sort control. The column
headers write the same `sort` value (§10.5): newest first by default, name,
distance, ascent, grade, record and best, empty values last either way. The
list scrolls endlessly (§10.14, the workout table's two item containers and
skeleton; `<noscript>`: pagination). A filter that matches nothing gets the
filtered empty state with « Effacer le filtre ». The board itself, its
podium and the participants live on the course page.

The **Découvrir** page (`GET /segments?kind=discover`) is the map alone — no
cards, no filter, no tabs — showing every course the viewer may see: the
readable shared ones (public, plus followers-only ones from owners they
follow) and their own, private ones included. A viewer with nothing to show
gets the §11.4 empty state pointing at `/people` instead of an empty canvas.
The map is the one map allowed to centre on the reader's own position (§14.4):
an already-granted browser permission centres it silently at city zoom,
otherwise only the `Me localiser` control button ever prompts — never an
unsolicited dialog. Without a granted position it opens on the start point of
the viewer's most recent workout, and with no activity at all on its default
centre. The `segments-map` component reads the scope through
`GET /segments/discover_map?bbox=…` as the viewport moves (debounced, in-flight
reads aborted) and draws one line per course, smoothed at the medium level for
display like every other course map (§15.4), above the basemap geometry and
under its labels:

- **Stacked courses take nuances.** A course alone is the brand primary, as
  on every map. Courses that share a stretch of road (within 25 m for 200 m,
  or half the shorter one; a crossing does not count) form a group: the
  longest keeps the primary and the others take the next steps of a
  primary ramp (`lib/course_overlaps.js`), contrasted with the basemap first —
  darker on the light basemap, lighter on the dark one — never an invented
  hue or a sport colour (§6). Shorter courses draw on top, so a climb nested
  in a longer course stays visible and reachable. Colour is never the only
  cue: the popup names every course under the pointer.
- **Every course carries its direction**, since a segment only matches
  recordings made its way and its reversed copy is another course. Unlike the
  §15.2 marks, the arrows sit **on the line itself**, not beside it — among
  many thin courses an offset mark would read as its neighbour's: an open
  head without shaft (the line is the shaft), in the surface colour over a
  border of the course's own nuance, placed on the §15.2 slots. The
  route-wide three-arrow threshold does not apply: each course gets its arrow
  as soon as it is 48 screen pixels long. Courses on the same road and in the
  same direction share their marks; the opposite direction keeps its own.
  Lines are never offset from the road. Every other map keeps the offset
  arrows of §15.2.
- **Hover and click are one bubble** (§15.1). With a hovering pointer, a
  non-interactive bubble names the courses under it while their lines
  thicken; a click (a tap on touch screens, which have no hover bubble) pins
  it with the links, and the lines stay emphasised while it is open. Each
  entry is a thumb-sized row — the course's nuance swatch, its name linked to
  its page, then `sport · distance · participants` — formatted server-side,
  drawn as text nodes, and never naming an athlete; the topmost course comes
  first, at most six.

The map uses the account's basemap and unit system, cooperative gestures on
touch screens (§15.2; the wheel keeps zooming on a desktop, where the map is
the page), the compact collapsed attribution, and on phones the `--discover`
height. The page header carries `[Liste]` back to the index, beside the title
on every width. The map card's count announces how many courses are on
screen, an empty viewport says so, and a failed read keeps the previous lines
and shows the error state.

### 20.7 Leaderboard

The board is previewed on the segment detail page (§20.6): the **top 10 per
sport**, under the `Classements` container, with `[Voir le classement complet]`
when a section overflows. The full board lives here.

```
┌ page header ── h1: Classement · par @créateur · [Retour] ┐
┌ [Tout le monde | Mes abonnements] [Tous | Femmes | Hommes]  Rangs parmi… ┐
┌ §19.5 info panel — non-owners, non-dismissible ┐
┌ table ───────────────────────────────────────────────────┐
│  #  Nom / alias        Temps    Date       Allure/vitesse│
│  1  Marie              12:04    3 mars      15,9 km/h    │
│  2  Grimpeur 7         12:41    mars 2026   15,2 km/h    │
└───────────────────────────────────────────────────────────┘
```

The last column follows the sport: `Vitesse` for a speed sport, `Allure` for a
pace sport (min/km or min/mi), and both labels when the sport displays the two.
A sport with a fixed pace basis (rowing) reads its allure over that basis
(`/500 m`). Its value is the average pace or speed stored on the effort (moving
time), rendered in the viewer's unit system.

Les trois premières lignes du tableau affichent le rang §10.4 : le laurier de
la place (or, argent, bronze) devant le numéro ; à partir de la quatrième place,
le numéro reste seul, toujours annoncé « Rang N ».

Le classement suit son lecteur ([SEGMENTS.md](SEGMENTS.md)) : chacun y voit les
athlètes dont il peut lire la publication, parcours partagé, sauf ceux qui ont
quitté ce classement. Les rangs se lisent donc « parmi les athlètes que vous
pouvez voir », phrase écrite sous le sélecteur. Nul ne voit les efforts d'un
autre athlète sur une page de segment en dehors du classement (§20.6).
L'en-tête nomme le créateur du segment (avatar, nom affiché, `@username`).

Un sélecteur `nav-segmented` (§10.15) au-dessus des tableaux — sur cette page
comme dans le conteneur Classements de la page du segment — choisit
**Tout le monde** ou **Mes abonnements** (les comptes suivis et soi-même) ;
chaque choix est une URL GET (`?board=following`), et une vue « abonnements »
vide le dit.

Sur la page du classement complet seulement, un second `nav-segmented` suit le
premier : **Tous**, puis **Femmes** et **Hommes** pour chaque catégorie qu'au
moins une section offre ([SEGMENTS.md](SEGMENTS.md), `?category=`, combinable
avec `?board=`). Une catégorie n'est offerte qu'à partir de 3 athlètes
distincts que le lecteur voit dans ce sport ; une section en dessous dit
« Moins de 3 athlètes de cette catégorie parmi ceux que vous voyez dans ce
sport. » au lieu de lister qui que ce soit. Le sélecteur n'est pas rendu tant
qu'aucune section n'atteint le seuil. L'aperçu de la page du segment reste le
classement général ; la tuile *Mon rang* y ajoute, en légende discrète sous la
valeur, la place du lecteur dans la catégorie qu'il a déclarée
(`2 / 5 · Femmes`) quand elle est offerte.

Chaque lecteur voit les **noms réels** (liés au profil) pour lui-même, pour les
comptes qu'il suit et, s'il a créé le segment, pour tous ; les autres lignes
sont aliasées avec la date réduite au mois. Les efforts marqués anonymes
restent aliasés pour tout le monde.

Un segment multi-sports rend **une section de classement par sport**, chacune
titrée `Nom du segment (Sport)` et ordonnée comme un classement distinct ; un
segment mono-sport garde une seule section, sans suffixe. L'ordre des sections
suit le catalogue des sports.

Anonymous rows: alias only — **no avatar**, no profile link, no exact date, no
identifier of any kind (§9.5, [SEGMENTS.md](SEGMENTS.md)).

The viewer's own standing is read on the course page: the *Mon rang*
tile carries the rank and the board size (`3 / 12`, with the laurel for a
top-three place), an unlisted effort reads `Non classé`, and the hub's latest
segments keep the ranks of recent efforts. There is no separate leaderboard
directory.

### 20.8 `/me/records`

```
┌──────────────────────────────────────────────────────────┐
│ page header ── h1: Records                               │
├──────────────────────────────────────────────────────────┤
│ sport pills: (◍) Course à pied · (◍) Vélo · …            │
│ Choisissez un sport, ou balayez les records sur mobile.  │
├──────────────────────────────────────────────────────────┤
│ Course à pied                                            │
│ Records                  │ Meilleurs efforts             │
│ Distance la plus longue  │ 5 km                          │
│   42,2 km · 12 avr. →    │   25:00 · 12 avr. →           │
│ Durée la plus longue     │ 10 km                         │
│   4:12:33 · 12 avr. →    │   52:10 · 3 mars →            │
│ …                        │ …                             │
└──────────────────────────────────────────────────────────┘
```

One card, one sport at a time (§10.25): the sport pills (icon and name, native
arrow-key navigation) form one sideways-scrolling line, and every sport's page
is one full-width page of a native scroll-snap strip. Touch can swipe between
sports, but choosing a pill always reaches it without a gesture. The card fits
the selected sport's height, so a short sport leaves no blank space under its
rows; no autoplay or programmatic animation, and vertical page scrolling stays
native. The selected pill follows a completed swipe, a polite status names the
sport, and only the selected page is keyboard/screen-reader accessible. A page
carries the sport heading, then its classic records and its best efforts side
by side once the page is wide enough and stacked on a phone; a sport with no
best efforts shows the classic table alone. A single sport has no selector or
swipe hint. Without JavaScript every page remains readable in sequence; Turbo
teardown releases the resize observer and the pending scroll callback and
restores that baseline before caching.

Sports are ordered most practised first, so the page opens on the account's
main sport; `?sport_id=` names the one to open, which the hub's filtered
« Voir les records » link passes. Record types absent for a sport (elevation,
power, pace-vs-speed) are **omitted**, never shown empty, and the classic
records keep the record-type order rather than a storage order. Rows carry no
§10.4 trophy: the whole page is records, so a per-row marker would carry no
information; the empty state's trophy is neutral (`text-secondary`), never a
place colour. A record whose workout was deleted keeps its value and date and
drops the link.

### 20.9 `/equipment`

Index of cards: type icon, label, total distance, workout count, active state.
Detail page: totals, attached workouts table, refresh action for drifted totals
(a §11.3 partial state), edit, and a danger zone.

### 20.10 `/me/stats`

```
┌ page header ── h1: Statistiques ─────────────────────────┐
┌ controls: par période | par sport · période ▾ · sport ▾ ─┐
┌ chart card + « Voir les données » disclosure ────────────┐
┌ totals table (the same data, always present) ────────────┐
```

### 20.11 `/settings` — Universal hub

The grouped settings collection rendered on every breakpoint (§8.5): one card
per group, one icon + label + chevron link per sub-page. From `md` up each
sub-page repeats the collection in its shell; below `md` it links back here.

### 20.12 `/settings/publishing-profiles/:id/edit`

```
┌ §19.3 info panel, persistent ────────────────────────────┐
┌ identité: nom · audience (public · followers: built-in profile only) ────┐
┌ contenu: titre · description ─────────────────────────────────────────────┐
┌ mesures: 19 checkboxes, 3 columns, [tout] [aucune] ───────────────────────┐
┌ parcours: route · image · fond de carte · GPX · masquer départ/arrivée ──┐
┌ délai avant publication: select · §19.19 info ───────────┐
┌ publication automatique: §19.25 · switch · trajets · sports · ☐ accord ──┐
┌ aperçu: live summary of what a viewer will see ──────────┐
                                    [ Annuler ] [ Enregistrer ]
```

The automatic switch is disabled, with the holder's name as its hint, while
another profile of the same audience is automatic ([AUTO-PUBLISHING.md](AUTO-PUBLISHING.md)).

### 20.13 `/settings/privacy-zones/new` — see §14.4

### 20.14 `/@username` — Public profile

A **portrait and a journal of shared outings**, never a second training
dashboard. The local profile and the cached remote profile compose the same
header, bio, filters, editorial publication cards and optional sport mix.
Viewing still requires membership ([ACCESS.md](ACCESS.md)).

```
┌ (avatar lg) Display name                     [Suivre*] ┐
│             @marie@allure.test                          │
├ Présentation ──────────┬ Publications · N visibles ────┤
│ bio                   │ sport pills · period           │
├ Statistiques* ─────────┤ editorial publication cards    │
│ sports radar · metric │ endless scroll                 │
├ Records personnels* ──┤                                │
│ sport switch · records│                                │
├ Sports partagés ───────┤                                │
│ count-only sport mix  │                                │
└───────────────────────┴────────────────────────────────┘
```

`*` Only when the corresponding local sharing permission is enabled.

- **Header:** the hub's avatar/name/handle order (§8.4), with « Modifier mon
  profil » / "Edit my profile" for the owner and the existing follow control
  for another account. Every follow request stays pending until accepted,
  locally too; « En attente » includes cancellation (§24). The local page keeps
  its ActivityPub alternate link.
- **Presentation:** the bio in the standard card, omitted when empty — no
  placeholder claiming the person forgot it. Local text is escaped with its
  paragraph breaks; remote markup uses the existing sanitized projection.
- **Journal:** reuse `feeds/_item` with `show_author: false` and its editorial
  variant. Keep the sanitized route image and its pending/unavailable states,
  shared photos, title, sport, activity date, description excerpt, commute and
  audience badges, reactions and comment count. No metric tiles, device line,
  record badges or trophy stamps, even when those fields were published.
  Ordinary feed cards keep their full anatomy (§8.3).
- **Navigation:** reuse the hub's sport/period toolbar (§10.6, §10.15), including
  its two native selects on phones. The default period is **Tout / All**, not a
  recent window that could make an established profile appear empty. The same
  week, rolling 30 days and calendar year choices apply in the viewer's time
  zone. The journal orders and filters by the **published activity date and
  sport**, never the mutable source workout. A remote note without a date is
  retained under All, placed after dated notes, not assigned an invented date.
  Sport options and counts come only from accessible publications; retain an
  active sport with zero results in the selected period. Filter state stays in
  the URL; filtered-empty differs from no visible publications (§11.4).
- **Sport mix:** reuse the hub donut, keyboard legend, selection panel and
  equivalent table, only for several sports and with no active sport filter.
  Its sole measure is **publication count**; there is no metric selector,
  distance or duration total. Like the hub, keep five named slices and group
  the rest under Others. A selected slice offers the journal filtered to
  that sport over the same period. The visible hint names the limited basis:
  publications accessible here, not the account's complete practice history.
- **Layout:** from `lg`, the bio, optional statistics and records, then the
  sport mix form the narrow left column; the journal leads the wide right
  column. On phones the order is bio, optional statistics and records, journal,
  sport mix: the secondary chart never delays the first publication. Without a
  bio, shared figures or a meaningful mix, leave no empty rail. The journal
  reuses endless scroll with the real Pagy nav as its no-JavaScript fallback
  (§10.14).

The default profile has no cumulative-distance tiles or personal records.
There are **two independently acknowledged sharing exceptions**, local only,
under `/settings/profile` (§19.38): `users.profile_statistics_audience` and
`users.profile_records_audience`, both non-null and defaulting to `none`, with
`followers` and `members` as the other choices. Each is read afresh on the
profile request. `Profiles::SharingPolicy` authorizes the signed-in local
viewer before any private-history query: `none` renders nothing even to the
owner, `members` serves every active local account, and `followers` serves the
owner and accepted local followers only, never pending, rejected, undone or
reverse-direction follows. This local access does not depend on the restricted
federation switch; there is no remote or anonymous principal. A narrower
audience, revocation or an ended follow takes effect on the next read.
Deactivated owners and viewers expose neither block.

- **General statistics by sport:** the four permitted aggregates are activity
  count, distance, moving time (the personal statistics' duration definition)
  and ascent. They read **all** of `user.workouts`, including unpublished,
  manual and credited workouts, with no recent-2,000 cap. There are no averages,
  calories, speed, pace, heart rate, cadence or power. A sport with no recorded
  distance omits it; elevation is omitted for sports without elevation. The
  compact card draws a radar with the **sports as axes**, in catalog order,
  and one measure at a time: activity count, distance, moving time, ascent.
  The measure changes through native segmented radios or a horizontal swipe,
  using the same whole-panel paging as the records below. Omit a measure with
  no data and omit a sport with no applicable value for that measure, never
  turn absence into zero; keep the remaining sports' order. Every axis uses
  the **same logarithmic scale** for the selected measure: `log1p(value)` on
  the stored SI values (counts, metres, seconds), zero at the centre, a common
  maximum. This zero-safe compression is visual only and is explicitly named;
  the raw figures, formatted in the reader's units, remain in each measure's
  « Voir les données » table. That disclosure is open without JavaScript or
  after a chart failure. The maximum's real value also accompanies the chart.
  Never independently normalize each sport, fabricate axes, group sports into
  Others, or read the radar as a performance score. Long names may truncate on
  the chart but stay complete in the table; all sports remain represented.
  With fewer than three applicable sports, use horizontal bars on the same
  scale instead of a degenerate polygon. ECharts renders on SVG, without
  animation, follows the theme, and releases its observers on Turbo navigation.
  Hovering a vertex or an axis end shows the full sport name, selected measure
  and untransformed, reader-unit value in the standard inverted tooltip. A
  short tap pins the same reading on touch; movement over 10 px, a cancelled
  pointer or a long press never selects, so horizontal swiping and vertical
  scrolling stay native. Axis ends also make zero values readable when their
  vertices overlap at the centre. The bar fallback exposes the same reading.
  Escape, an outside press, leaving the chart with a mouse, scrolling, a panel
  change, resize/theme re-render or Turbo teardown dismisses it. The complete
  server-rendered tables remain the keyboard and screen-reader equivalent.
  Its hint says these are whole-history totals across all years, unaffected by
  journal filters.
- **Personal records:** reuse the personal record labels, values and sport
  presentation from `/me/records`, including standard-distance best times.
  Read the existing winners and sport-specific filtering, never recalculate a
  separate public ranking. Show only **label and value**, never the achievement
  date, source title, workout link, identifier or location. One sport is shown
  at a time, the first initially: the existing Tabler sport radio pills (icon
  and name, native arrow-key navigation) form one sideways-scrolling line,
  independent of journal filters. Every sport's complete two-column table is
  one full-width page of a native scroll-snap strip; touch can swipe between
  sports, but choosing a pill always reaches it without a gesture. This pages
  whole tables, never horizontally scrolls their columns (§12). All pages
  share the tallest page's height to avoid vertical jumps. No autoplay or
  programmatic animation; vertical page scrolling is left native. The selected
  pill follows a completed swipe, a polite status names the sport, and only
  the selected page is keyboard/screen-reader accessible. A single sport has
  no selector or swipe hint. Both cards reuse the `paged-panels` controller
  (§10.25), which the owner's records page uses too.
  Without JavaScript all tables remain readable in sequence; Turbo teardown
  releases the resize observer and pending scroll callback and restores that
  baseline before caching.
  As on the owner's records page, every row is already a record: no repeated
  trophies. This does not add record badges to journal cards.

These two optional sections belong to the left rail, keeping their own
headings and scope outside the journal's filtered region. Neither changes
publication permissions or snapshots, publishes an activity, nor crosses the
federation boundary. The cached remote profile has no such data and invents
none. Rankings between people, performance comparisons, training load,
intensity pulse, regularity and calendar remain absent.

The journal, its filters and its sport mix read the **same authorized set**: local active publications,
deduplicated to the narrowest audience served to this reader; remote active
notes admitted to this account, never another member's cache. Unpublished,
scheduled, deleted and inaccessible publications do not affect cards, filters
or counts. SQL aggregates read only scalar sport keys, never every complete
snapshot. The remote profile keeps its separately entitled courses section;
missing remote history is never reconstructed or presented as a global total.

### 20.15 `/session/new` — Sign in

```
        ┌ auth shell, centered column ─────────┐
        │            (A) allure.               │
        │       allure.test                    │
        ├──────────────────────────────────────┤
        │  Adresse e-mail  [               ]   │
        │  Mot de passe    [            ] (👁) │
        │              Mot de passe oublié ?   │
        │            [ Se connecter ]          │
        └──────────────────────────────────────┘
```

The auth shell is the `auth` layout: brand mark and `allure.` wordmark (§5.2), instance domain, theme toggle,
flash, and the card — no primary navigation, bottom bar, feedback widget or
footer chrome. Password fields are full width and carry a reveal toggle with an
accessible name that names the action ("Afficher / Masquer le mot de passe").
Rails' `password_field` maps `maxlength` to `size`; every password input passes
`size: nil` so the browser cannot shrink it.

Same shell for forgot-password and reset-password. Sign-up, where registration
is enabled, is the same shell with username, email and password, plus live
username availability and the reserved-name rule explained *before* submission.
Where registration is closed, the sign-in page says so plainly and does not
render a dead link; an operator can still admit one account with a single-use
`users:invite` link, which opens the same card with the invited address
prefilled read-only. An expired, already used, or unknown invitation link
returns to sign-in with a plain statement.

Re-authentication (`/session/reauthenticate/new`, `[devdoc:auth]`) is the
same shell: « Confirmez votre identité », one sentence naming the window
(« Cette confirmation reste valable 10 minutes. »), the account address as
read-only plain text, the password field with its reveal toggle, a full-width
« Confirmer », and « Annuler » back to the page the action came from. A
sensitive non-GET action is not replayed: after confirmation the person lands
back on its page with « Identité confirmée. Vous pouvez reprendre votre
action. » and repeats it. Once a second factor is enrolled the same card adds
the second-factor fields below the password, and the copy says so; the
operator console's 15-minute step-up uses this page.

Two-step verification (`/session/challenge/new`, `[devdoc:auth]`) is the
same shell after a correct password, laid out like Tabler's
`2-step-verification-code` page: the card title « Vérification en deux
étapes », one centred sentence, then Tabler's one-time-code input — six
large slots in two groups of three over one real
`autocomplete="one-time-code"` field (the `otp` Stimulus controller creates
and disposes the Tabler `OtpInput`, and a complete code submits the form) —
with « Le code change toutes les 30 secondes. » under it. When the account
has a passkey and the browser can use one, an « ou » divider and a
full-width outline « Utiliser une clé d'accès » follow; a passkey-only
account sees only that button. A centred link « Vous n'avez plus accès à
votre application ? Utilisez un code de récupération. » swaps the slots for a
monospace recovery-code field (`?recovery=1`), and back. The footer is
Tabler's paired `btn-list`: « Annuler » and « Vérifier », each half width.
A wrong answer re-renders with « Ce code ne correspond pas. Réessayez. »; the
fifth, or an expired step, returns to sign-in with a plain statement. The
re-authentication page and the authenticator-app enrolment page use the same
six-slot input.

Password managers watch the `<body>` they found when the page loaded, so a
form Turbo swaps in is never offered a fill. In a browser, every `auth`-layout
page therefore loads in full (`turbo-visit-control: reload`) and its forms
submit natively (`credential_form_data`); the re-authentication form also
carries a hidden `autocomplete="username"` field, since managers skip the
read-only account field. The iOS companion keeps Turbo on these pages.

The « Double authentification » card leads `/settings/security`: an inline
alert states the obligation (warning during the grace period with its date and
days left, danger once required), then a flush list — application
d'authentification (Configurer / Remplacer / Retirer), clés d'accès (each with
its name, added and last-used dates, Retirer; a name field and « Ajouter une
clé d'accès », replaced by a plain sentence where the browser cannot), and,
once enrolled, the recovery-code count with « Générer de nouveaux codes ».
Removals and regeneration go through the §10.10 confirmation. Removing the
last method of a password account is refused with the reason. Enrolling the
authenticator app is its own settings page: the QR code on white in both
themes, the key in groups of four, and the code field. The ten recovery codes
are shown once, on their own `no-store` page, after the first enrolment and
after each regeneration.

An enrolment-only session (grace period over, or the operator) keeps the
application chrome without the notification bell; every other page sends it to
the security page with the obligation. During the grace period every
application page carries a warning reminder under the flash — the deadline,
the days left, « Activer » and « Plus tard », which hides it until the end of
the day.

Identity providers (`[devdoc:auth]`) add to the same shell, only for the
providers the operator enabled. Under the sign-in and sign-up forms an « ou »
divider precedes one full-width secondary button per provider — the brand
glyph and « Continuer avec Google / Apple / <label> » — each a POST form
outside Turbo. Inside the iOS companion the same buttons, identical on the
page, open the provider in the system sign-in sheet (`[devdoc:auth]`); the
page then continues in the app exactly as in a browser, a cancelled sheet
leaves it untouched, and Google is omitted there while Sign in with Apple is
not offered. An older companion without that bridge shows no provider button.
A first sign-in with an unknown identity opens « Créer votre
compte » (`/auth/onboarding/new`): one sentence naming the provider, the
provider's (or invitation's) address as read-only plain text, the username
with the sign-up's live availability and a hint that it is permanent, the
display name prefilled from the provider, a full-width « Créer mon compte »,
and « Annuler » back to sign-in. Refusals return to sign-in with a plain
statement: an address already used by an account (« Connectez-vous avec votre
mot de passe puis associez ce fournisseur dans les réglages. »), an
unconfirmed address, closed registration, an identity linked elsewhere, a
failed round trip.

`/settings/security` is laid out in three full-width groups: the « Double
authentification » card; the password card beside the « Fournisseurs
d'identité » card at equal height on `lg` and wider (the password card spans
the row, its form kept to a readable width, when no provider is enabled or
linked); then the « Sessions actives » card, whose header carries « Fermer
toutes les sessions » behind the §10.10 confirmation instead of a separate
danger card. Its table names the device (one truncated line, its full user
agent as a title, « Cette session » beside it), the sign-in date with its
method (« Mot de passe » or the provider), the last activity, and a
ghost-danger « Révoquer ». Below `md` the sign-in column goes, the badge
drops under the device and « Révoquer » becomes an × with its accessible
name; below `sm` the last activity joins the device cell, so the table never
scrolls sideways.

`/settings/security` adapts to the account's ways in. A password-less account
sees « Définir un mot de passe » in place of the password change — one
sentence saying a password adds a way in that will need two-step
verification, then the new password and its confirmation — and its two-step
card says what a method is for without a password. The « Fournisseurs
d'identité » card follows: one sentence (a linked identity signs in on its
own and its own sign-in replaces Allure's two-step verification; for the
operator, that Allure still asks for two-step verification after it), a flush
list with each identity's glyph, provider, address, linked and last-used
dates, and a ghost-danger « Dissocier » behind the §10.10 confirmation —
absent on the account's only way in — then one « Associer <provider> »
button per enabled provider not yet linked. The card is absent when no
provider is enabled and none is linked. Re-authentication for a
password-less account asks for its two-step method when one is enrolled, and
otherwise offers « Continuer avec <provider> » for its linked providers.

### 20.16 `/remote_notes/:id` — Remote publication

```
┌ page header ── (◍) author · h1: title · handle · date ───┐
┌ metrics: distance · durée · D+ · … ──────────────────────┐
  social row (§10.17): [💬 N] (below lg)      réactions ▸
┌ weather · description (sanitized) ───────────────────────┐
┌ media frame: pending / unavailable / map / chart / files ┐
┌ comments card (§10.20), from lg: the origin's thread as  ┐
│ this instance holds it, the composer with the received   │
│ §19.21 sentence; below lg on /remote_notes/:id/comments  │
┌ « Copie reçue d'une autre instance : @handle. » ─────────┐
```

### 20.17 `/remote_segments/:id` — Remote course

```
┌ page header ── (◍) author · h1: name · handle · sport ───┐
┌ metrics: distance · D+ · D− ─────────────────────────────┐
┌ description (sanitized) ─────────────────────────────────┐
┌ media frame: pending / unavailable / map / files ────────┐
┌ §19.16 copy panel: [Copier comme segment] ───────────────┐
┌ « Copie reçue d'une autre instance : @handle. » ─────────┐
```

A remote course has no elevation chart, no origin leaderboard, and no owner
actions. A deleted course renders the §19.17 tombstone to former recipients
only.

### 20.18 `/settings/api` — API tokens and webhooks

Inside the settings shell (§8.5), two collection cards, each with its own
header action; creation forms are their own pages in the shell (`/new`), as
for publishing profiles.

```
┌ intro: one sentence · [Documentation de l'API →] ────────┐
┌ Jetons d'API ─────────────────────── [Créer un jeton] ───┐
│ name · allure_pat_X… · permissions (badges) · location   │
│ badge · expires · last used (relative) · [Révoquer]      │
│ empty: « Aucun jeton. »                                  │
┌ Assistants IA (MCP) ─────────────────────────────────────┐
│ one sentence · Adresse: …/mcp · client configurations    │
│ (label · [Copier] · monospace block), token placeholder  │
┌ Webhooks ─────────────────────────── [Ajouter un webhook]┐
│ host + path (truncated) · events (count) · state badge · │
│ last delivery (status + relative) · [⋯]                  │
│ empty: « Aucun webhook. »                                │
```

- **Token creation** (`/settings/api/tokens/new`) re-authenticates first
  (§20.15), then: name; permissions as a checkbox list, none ticked, each in
  words with its scope code in muted monospace; expiry select (30 / 90 / 365
  days, default 90); the §19.26 warning; « Localisation pour les assistants
  IA » as a radio list (« Aucune localisation » selected, « Tracés sans mes
  zones de confidentialité », « Tracés complets », only up to the instance
  ceiling), each with its description, then the §19.27 warning; « Créer le
  jeton ». The next page
  shows the secret once in a read-only monospace field with a copy button and
  the §19.26 second text, the chosen location level, and — for a token with
  `read` — the MCP client configurations filled with the secret; leaving it
  never shows the secret again.
- **Location badge**: a token above « Aucune localisation » carries a
  `bg-warning-lt` badge with `ti-map-pin` (« Tracés sans zones » / « Tracés
  complets ») after its permission badges.
- **Revocation** is confirmation-guarded (§10.10) and immediate.
- **Webhook form** (`/settings/api/webhooks/new`, `/edit`): URL, description,
  events as a grouped checkbox list (Activités, Publications, Records et
  segments, Social, Services connectés) with « Tous les événements », the
  §19.26 warning, then the secret shown once after creation exactly like a
  token. The `⋯` menu holds « Envoyer un test », « Renouveler le secret »,
  « Désactiver » / « Réactiver », « Supprimer ».
- **Webhook detail** (`/settings/api/webhooks/:id`): its facts, then the
  deliveries of the last 30 days as a paginated table (event, time, status
  badge, HTTP code, attempts) with « Renvoyer » per row; refreshed through the
  live-frame pattern while a delivery is pending.
- State badges: « Actif », « En pause » (owner), « Désactivé — échecs
  répétés », « Désactivé — adresse supprimée » (410), « Désactivé par
  l'opérateur ».

### 20.19 `/developers/api` — API reference

```
┌ page header: « API » · [Mes jetons →] ───────────────────┐
┌ intro card: base URL (copyable) · authentication in one  │
│ sentence · link to openapi.json · §19.26 first text      │
┌ Scalar reference, full width ────────────────────────────┐
```

The reference is the embedded Scalar component (`[devdoc:api]`): it
follows the light/dark theme, uses the brand tokens for its accent, never
fetches outside the instance and never stores a pasted token. It lives in a
same-origin frame filling the viewport's height, because Tabler and Scalar
share utility class names; Scalar shows its own loading state there, and the
intro card's `openapi.json`/`openapi.yaml` links remain the way to the
document if the reference fails.

**Language exception.** The page chrome is bilingual like every page; the
reference contents (operation summaries, descriptions, error titles) are
English only, because they are protocol text whose two versions would drift
on a contract. This is the only screen where English copy is shown to a
French-locale account by design.

### 20.20 `/help` — Help

```
┌ page header: « Aide » ───────────────────────────────────┐
│ intro sentence                                           │
┌ list group: icon · title · one-line summary → topic ─────┐

┌ page header: pretitle « Aide » (link) · topic title ─────┐
┌ article card, col-lg-8: h2 sections, lists, §19 panels ──┐
```

The screens explain themselves; help explains the **concepts behind them**
that a hint cannot carry, for members, in a handful of pages: publishing,
privacy zones, sharing beyond the instance, segments and leaderboards,
training load and heart-rate zones (`HelpController::TOPICS`). It is not a
manual of the screens and never describes a button's position. The operator's
documentation is the separate public site (`docs/site/`), not these pages.

- **Reached** from the account menu's « Aide » entry (`navigation.help`,
  bridge item `help`, also in the companion's native account menu through
  the topbar payload, icon `help-circle`) and
  from a « En savoir plus » link (`HelpHelper#help_link`) placed after the hint
  or panel of the screen the page explains. A page never links to help from
  its primary actions.
- **Members-only** like every page; an unknown topic is a 404.
- **Register:** the sober register (§3.2) wherever a page touches publishing,
  privacy, leaderboards or health data, neutral elsewhere; never playful.
  Glossary words only (§4); no protocol vocabulary (§24).
- **The §19 texts appear verbatim** in `alert alert-info` panels where a page
  explains what they govern, so help never paraphrases a privacy promise
  differently from the screen that makes it.
- **Language exception.** Each topic's body has locale-specific partials,
  `app/views/help/topics/_<topic>.{fr,en,de,es,nl}.html.erb`,
  instead of locale-file strings: long prose with links and headings does not
  belong in YAML. Titles, summaries and icons stay in the locale files
  (`help.topics.<topic>`), and `spec/requests/help_spec.rb` fails when a topic
  lacks a language. All five versions change in the same patch.

### 20.21 The demo strip and the credentials block

```
┌ demo strip (every layout, above the chrome) ─────────────┐
│ « Instance de démonstration : tout est réinitialisé     │
│   chaque nuit à 03:00. » ⚠ Réinitialisation imminente   │

┌ sign-in page, below the form ────────────────────────────┐
│ card « Comptes de démonstration »                        │
│ privacy sentence · tom@demo.allure.rocks (membre)        │
│ « Mot de passe partagé : » <mot de passe publié>              │
```

Rendered only when `DEMO_INSTANCE` is set (`Allure::Demo`, `[devdoc:demo]`);
an ordinary instance shows nothing of either surface.

- **The strip** is one quiet secondary line on a sunken surface, above the
  topbar in every layout — application, auth and admin — stating the plain
  truth: a demo, recreated every night at the configured hour. It is never
  dismissible (the devtools bar above it is the only dismissible precedent)
  and never a warning color by itself. The auth layout floats its language
  and theme controls in the strip's band, so the cluster takes the
  `demo-strip-offset` class there and moves below it instead of overlapping.
- **The T−5 warning** appears **without any reload**: the strip carries the
  next reset as an absolute instant (`data-demo-reset-at-value`) and the
  window (`data-demo-reset-window-value`); the `demo-reset` Stimulus
  controller ticks every ten seconds and reveals the warning span, in the
  warning ink, at five minutes. The page may have been open for hours; the
  controller, not a page load, decides (`app/frontend/controllers/
  demo_reset_controller.js`).
- **The credentials block** sits under the sign-in form as a small card:
  the privacy sentence first (« Données partagées entre visiteurs et
  effacées chaque nuit. N'importez aucune donnée personnelle. »), then one
  line per shared account — e-mail in `code`, then the role, admin for the
  configured operator, member otherwise — then the shared password in
  `code`. The block never shows a TOTP secret: a demo holds no second
  factors. Addresses are e-mails because the form asks for an e-mail.
- **Register:** none. This is operational truth-telling about a disposable
  instance, not a marketing surface; the same sentence governs both surfaces
  and every locale carries it.

### 20.22 `/people` — Accounts

```
┌ page header ─────────────────────────────────────────────┐
│ pretitle « Relations » · title « Comptes »               │

┌ search card ─────────────────────────────────────────────┐
│ « Trouver un compte »                                    │
│ [ handle or name ................ ] [ Rechercher ]       │
│   └ live dropdown: avatar · name · @handle · badge ·      │
│     follow control (max 8)                               │
│ hint · « En savoir plus »                                │
│ hidden-account note (only while the viewer is hidden)    │

┌ relationships card ──────────────────────────────────────┐
│ [ Abonnements (n) ] [ Abonnés (n) ] [ Demandes (n) ]     │
│   └ card-header-tabs, one card per active view           │
│ rows: avatar · name · @handle · [action]                 │
│ pagination when more than one page                       │
│ requests: incoming section then outgoing section         │

┌ suggestions card (Following tab only) ───────────────────┐
│ avatar · name · @handle · reason · [Suivre] [Masquer]    │
```

- **One search field, two behaviours.** Typing three characters or more opens
  the live dropdown (§19.39); submitting still resolves an exact handle or
  actor URI. The dropdown is a `dropdown-menu` anchored under the field, closed
  by Escape, an outside click, or a shorter query.
- **A result is deliberately thin.** Avatar, display name, `@handle`, one
  relationship badge (« Vous suivez », « Demande envoyée », « Vous suit »,
  « Demande reçue ») and the follow control. Nothing else is rendered, not even
  as hidden markup.
- **Tabs carry their count** in a `badge bg-secondary-lt`; the active tab is a
  `nav-link active` with `aria-current="page"` inside a
  `nav-tabs card-header-tabs` list in the card header. The views are pages, not
  an ARIA tab widget, so the list carries an `aria-label` and no `role="tab"`.
  `?tab=` is the whole state, so a tab is linkable and survives a reload.
- **Requests** lists incoming requests first (Accept / Reject, unchanged) then
  outgoing ones (pending badge, cancel). An empty list is one secondary
  sentence, never a blank card.
- **Removing a follower** is a `btn-ghost-danger` on the follower row, opening
  the shared destructive modal (§10.10) with the account's name and the
  consequence; the confirmation verb is « Retirer ».
- **Suggestions** name their reason after the handle, in secondary ink:
  « Sortie faite ensemble », « A réagi à vos activités », « Sur les mêmes
  parcours que vous ». « Masquer » opens the same destructive modal and is
  permanent; the card disappears when no suggestion remains.
- **Phones** stack the rows and keep the actions on the same line as the name
  where they fit; the tabs scroll horizontally rather than wrapping. The
  screen is a web view in the iOS companion and uses the same markup.

### 20.23 `/connections` and `/connections/:provider` — connected services

The hub (§8.6) is the settings hub's collection (§20.11), one row per service
the account may see: the service's mark, its name, the state badge, and the
external account with its last sync once linked.

```
┌ Compte / Services connectés ─────────────────────────────────┐
│ intro · §19.25 notice while a profile publishes automatically│
┌ Importation ─────────────────────────────────────────────────┐
│ ◈ Garmin Connect                    Non connecté          › │
│ ◈ EXR                               Non connecté          › │
│ ◈ Withings   paul@… · jamais synchronisé          Connecté › │
│ ◈ Zwift      paul@… · synchronisé il y a 14 heures Connecté ›│
```

A service's page is the settings shell (§8.5) with the services as its
navigation:

```
┌ Compte / Services connectés ─────────────────────────────────┐
│ [← Retour aux services connectés]            (below md)      │
┌──────────────────┬───────────────────────────────────────────┐
│ Importation      │ Zwift                                     │
│ Garmin Connect   │ ┌ Connexion ─────────────── [Connecté] ──┐ │
│ EXR              │ │ description · facts · §19.23d copy     │ │
│ Withings         │ │ [Synchroniser] [Récupérer l'équipement]│ │
│ Zwift          ◀ │ ┌ Récupérer des activités ──────────────┐ │
│                  │ │ Du · Au · sport de repli · [Importer]  │ │
│                  │ ┌ Préférences ──────────────────────────┐ │
│                  │ │ switches · [Enregistrer]               │ │
│                  │ ┌ Déconnecter ──────────────────────────┐ │
│                  │ │ ☑ delete · hint · [Déconnecter]        │ │
└──────────────────┴───────────────────────────────────────────┘
```

The state badge is the settings card's own (§10.4): « Non connecté »,
« Connecté », « Reconnexion nécessaire », « Accès révoqué », « Connexion en
cours… », « Code de vérification attendu », « Déconnexion en cours… »,
« Désactivé par l'opérateur ». Only a linked service carries the retrieval,
preferences and unlink cards; a disabled one carries the « Désactivé par
l'opérateur » sentence alone.

### 20.24 `/workouts/:id/photos` — Photos

The owner's photo manager (`[devdoc:photos]`), reached from the workout's
Photos card (« Gérer ») and from its lightbox (« Modifier »). The page header
is the way back to the workout, then « Photos ».

```
┌ ‹ Retour à « Sortie du matin » ─────────────────────────────┐
│ Photos                                                      │
├───────────────────────────────┬─────────────────────────────┤
│ [Carte]  sticky from lg       │ Ces photos restent privées… │
│                               │ [Ajouter des photos]        │
│                               │ 10,1 Mo sur 2 Go            │
│                               │ Correction de l'horloge…    │
│                               │ ⠿ [vignette] Légende        │
│                               │              [__________] ✓ │
│                               │              Prise le …     │
│                               │              ⌖ Placée …     │
│                               │              [Placer]  [⋯]  │
└───────────────────────────────┴─────────────────────────────┘
```

- **Layout.** From `lg` up the route is the sticky left rail and the manager
  the right column; below it the map leads the single column, as on the
  workout page. A positionless recording or a manual entry has no map and no
  placement: the manager alone.
- **Upload.** The whole column accepts a drop; the intake zone is the card's
  own (`_upload`), with the formats, the limits and the per-file progress. The
  quota is always shown here, in text and a native progress element.
- **Rows.** One row per photo, in gallery order: a drag handle (pointer
  devices), the thumbnail opening the lightbox, the caption, the capture time,
  the placement line and, for a photo the automatic placement left off the
  route, the reason (`[devdoc:photos]`: « Hors du parcours : prise 58 min
  avant le départ », « … à 1,2 km du tracé », « … ni heure ni position GPS »).
  « Placer sur le parcours » arms the map; the `⋯` menu holds « Retirer la
  position », « Placer automatiquement », « Monter », « Descendre »,
  « Télécharger l'original » and « Supprimer… ».
- **Caption.** It saves itself when the field is left or Enter is pressed
  (Shift+Enter keeps a line break); « Légende enregistrée » confirms it to
  assistive tech, a refusal keeps the text, marks the field invalid and names
  the reason. Without JavaScript the row keeps its submit button.
- **Order.** The gallery follows the capture time until the owner reorders it
  (`[devdoc:photos]`). Dragging shows where the row lands; the menu's
  « Monter » / « Descendre » are the keyboard and touch path. A manual order
  shows « Trier par heure de prise de vue » and says that new photos go to the
  end.
- **Map and list.** A marker click brings its row into view and highlights it;
  a placement — or its cancel — returns to the row it started from. The
  lightbox has no « Modifier » link here: the page is the manager.
- **Camera clock.** The correction field (minutes) shows once a photo carries
  a capture time; it says what moves and what stays (§10.22).

---

## 21. First run
No wizard. Onboarding is carried by empty states, each naming exactly one next
action, forming a path a new account walks naturally.

| Surface | State | Action |
|---|---|---|
| `/` feed | "Aucune publication pour le moment." | Importer une activité |
| `/workouts/import` | dropzone, formats and limits stated up front | — |
| First import completes | toast + the workout | Voir l'activité |
| `/me` | "Une activité de plus et les statistiques deviennent intéressantes." | Importer |
| `/segments` | "Créez un segment depuis une activité." | Choisir une activité |
| `/equipment` | "Ajoutez vos chaussures ou votre vélo pour suivre leur usure." | Ajouter |
| `/me/records` | "Vos records apparaîtront ici après votre première activité." | Importer |
| `/settings/privacy-zones` | §19.7 panel + "Créez une zone avant votre première publication." | Créer une zone |

Two things are true at first run and must not surprise anyone:

- the two built-in publishing profiles already exist (`ensure_built_ins_for!`);
  both are available, so the publish control offers `Public`, `Followers` or
  `Not published`, and the followers profile page states who receives its
  publications (§19.13);
- nothing is published until the account explicitly publishes it. The first
  publish flow states this (§19.1).

---

## 22. Styleguide route

A `/styleguide` route, available in **development and test only**, rendering
every component in this document:

- each component in all its variants;
- each of the four states (§11) for every stateful surface;
- both themes, switchable in place;
- both locales, switchable in place;
- the sport identity system for all 38 sports, so a missing or wrong icon is
  visible at a glance — which is how the `ti-skiing` defect should have been
  caught;
- the generated-avatar palette and the chart ramp against both backgrounds, with
  their contrast ratios printed.

It exists because there is **no general JavaScript test suite**: the browser is
the only end-to-end check for anything in `app/frontend/`, and three MapLibre
defects were visible only there, two of them silently. A single page that
renders everything gives Playwright one deterministic target and makes this
document falsifiable.

It is never routed in production.

Alongside it, the development-only impersonation tool (AGENTS.md, "Development
tools") renders two surfaces that use these components and nothing new: a
warning bar above the topbar, « Mode développement : vous agissez en tant que
@x » with a « Revenir à @y » button, shown on every page while an impersonation
lasts, and an « Agir en tant que… » entry in the account menu that opens the
account list at `/devtools/impersonation`. Both are tooling rather than product
information architecture: they exist only while the `devtools/` engine is
loaded, they are never routed or rendered in production, and they are not part
of the components this document specifies.

---

## 23. PWA identity

The manifest is routed at `/manifest.json` and carries the instance description
and the Allure primary.

The design specifies an **installable identity only**:

- name "Allure", short name "Allure";
- description naming the instance;
- maskable icons at the required sizes, derived from the brand mark;
- `theme_color` matching the resolved theme, `background_color` matching
  `--allure-surface` for that theme;
- `display: standalone`, `start_url: /`.

The **brand mark** is the Allure monogram: a bold A holding a shield with two
orbital nodes, cut out of the A by the even-odd fill. It is authored once as an
inline SVG partial (`shared/_brand_mark`) in `currentColor` — so it follows the
theme ink and the primary accent — with a viewBox trimmed to the artwork bounds
so it sits level with the wordmark. The same artwork ships as the primary
rounded tile in `public/icon.svg` (and its 512px PNG) for the favicon and
manifest.

**No offline caching strategy.** A sport tracker whose data is stale and whose
maps are unavailable is worse than one that says it needs a connection. The
service worker stays absent until there is a specific offline capability worth
designing; the commented-out Web Push scaffold is removed rather than left as
dead code.

Print styles are out of scope.

---

## 24. Forward compatibility with M5

M5 adds remote profiles, follow, a following feed, notifications, comments,
likes, moderation and Wanderer; the federation transport, remote profiles,
feed, operator settings, and remote publication and course rendering have
shipped. The surface is specified by [FEDERATION.md](FEDERATION.md) and
[SEGMENTS-FEDERATION.md](SEGMENTS-FEDERATION.md); this section records where it attaches so none
of it forces a redesign.

**Where things attach**

| M5 surface | Reserved slot |
|---|---|
| Follow / unfollow | The action slot on `/@username`'s header (§20.14), and on a remote profile using the same header component. |
| Following stream | Folded into `/feed` (§8.3) behind the signed-in Public switch, with the same card anatomy; `/following` redirects. |
| Remote profiles and publications | The avatar component (§9.5), the workout card and the workout detail visual language, unchanged — they already accept an identity rather than a `User`. |
| Remote courses | The same remote page, media frame and card language as remote publications (§20.16/§20.17), plus the §19.16 copy panel and the §19.17 tombstone. The course card is not added to the feed. |
| Notifications | Shipped (`§10.16`): the topbar bell left of the account menu, its count badge, and `/notifications`; per-kind switches live at `/settings/notifications`. |
| Federation diagnostics | The administration console (§7.6, `[devdoc:admin]`); the former settings sub-page redirects there for the configured instance operator. A `wanderer` sub-page remains open in the settings shell (§8.5). |
| Comments and likes | Shipped: reactions in the header and on feed cards (§10.17); comments as the full-width card after "Partage" (§10.20), with their count on feed cards. |

**Rules**

1. **Nothing in the UI names the protocol.** A remote account is "un compte sur
   une autre instance", not "an ActivityPub actor". Delivery state is "publiée",
   not "202 Accepted". [PUBLISHING.md](PUBLISHING.md) already requires a non-technical
   delivery summary; this design makes it a vocabulary rule.
2. **A remote person is badged, not styled differently.** The same avatar, name
   and card, plus an instance badge (`@user@instance`). Two visual languages for
   local and remote people would double every component.
3. **The publication model does not become a federation model.** There is no
   "federated visibility" control, ever. `[devdoc:roadmap]` locks this and the UI must
   not reintroduce it.
4. **Anything fetched from another instance is proxied and cached**, following
   the Gravatar rule (§9.3): the browser talks only to its own instance.
5. **Empty states assume nobody is followed.** A federated feed with no follows
   is the normal state of a new instance, not an error.

---

## 25. Debt this document supersedes

Known defects and gaps, recorded so they are not rediscovered as design
questions. Each is a deviation from a rule above.

**Navigation and routing**

1. The M3-M5 navigation leaves all resolve, including `feed_path`,
   `people_path`, `settings_path`, and the operator console's admin tree. The
   unbuilt `trails_path`, `feed_federated_path`, and `settings_wanderer_path`
   surfaces are intentionally absent from `config/navigation.rb` rather than
   dangling; the following stream is part of `/feed`, and Wanderer
   interoperability is post-M5 ([FEDERATION.md](FEDERATION.md)). No dangling leaf remains.
2. The topbar account menu's "Profile" item links to `root_path`, not the
   account's profile — and now that `settings_profile_path` routes, the menu has
   two plausible destinations and points at neither.
6. `settings/profiles#show` is a single page mixing display name and bio. §8.5
   separates profile and units/locale into distinct sub-pages under a settings
   shell. Leaderboard participation is no longer a setting: it is the
   per-segment control of §19.6.

**Theme**

7. The theme choice never persists for signed-in accounts:
   `theme_controller.js` PATCHes only when `settings_appearance_path` exists,
   and it does not. Violates §17.

**Unstyled surfaces**

8. `sessions/new`, `passwords/new`, `passwords/edit` are raw generator markup:
   inline `style="color:red"`, `<br>` layout, hardcoded English, no
   `content_for :title`, no page header. Violates §3.5, §7.4, §14.
9. `passwords_mailer/reset.html.erb`, `reset.text.erb` and both mailer layouts
   are unstyled and hardcoded English.
10. `SessionsController` and `PasswordsController` emit hardcoded English flash
    strings.

**Sport identity**

11. The former `skiing` glyph defect (a Tabler glyph that did not exist) and the
    per-colour-group icon mapping are resolved: §6.3 now gives every seeded
    sport its own globally distinct glyph, rendered from `SportPalette`.

**Components**

13. Deletes use the native browser `data-turbo-confirm` dialog, which cannot
    carry the §19 consequence copy. Violates §10.10.
14. The toast region exists, but only a finishing batch import produces an
    async-outcome toast; route-image availability, recompute completion, and
    publication delivery still land silently. Partially violates §10.8.
15. Closed: privacy zones are placed with the §14.4 map picker and its place
    search; the coordinates remain the editable source of truth.
16. The quiet celebration of a new record at import (§3.3) is not built: a new
    record shows only through its trophy on the workout and the records pages.
17. Every other data table wraps in `table-responsive` and scrolls horizontally
    on a phone — laps, splits, efforts, shared efforts, records, equipment
    workouts and import entries. §12 requires declared column priorities and a
    stacked card mode instead.

**Dead code and generator defaults**

19. `WorkoutPublicationsController` and `WorkoutPublicationMediaController` are
    unrouted; the publication media helpers point at `Federation::MediaController`.
20. `app/views/pwa/manifest.json.erb` and `service-worker.js` are unrouted, and
    the manifest still declares `theme_color: "red"` and a placeholder
    description. Violates §23.

**Accessibility**

21. There is no skip-to-content link, no live region for the batch-import
    polling, and no text or table equivalent for the elevation chart. Violates
    §18.2, §18.7, §18.8.

**Content-Security-Policy**

22. The policy (`config/initializers/content_security_policy.rb`) allows no
    inline or evaluated script, but `style-src` keeps `'unsafe-inline'`: about
    forty `style="…"` attributes (progress and zone widths, the styleguide,
    the weather icons' `mask-type`) and the chart and map libraries write
    inline styles. Moving the attributes to classes or CSS custom properties
    set from Stimulus is the next step; only then can `style-src` drop it. A
    new view never adds an inline `<script>` or event-handler attribute; a
    page that cannot avoid one (the self-submitting provider pages) uses
    `javascript_tag nonce: true`.

---

## 26. Changing this document

A visual or interaction decision that will outlive one screen belongs here
before it is implemented. A change lands in the same patch as the code that
depends on it, in both locales, with the styleguide updated.

When a rule here conflicts with a data or protocol contract in
[WORKOUT.md](WORKOUT.md), [PUBLISHING.md](PUBLISHING.md), [FEDERATION.md](FEDERATION.md),
`[devdoc:tracking-depth]` or [SEGMENTS.md](SEGMENTS.md), the contract wins and this
document is amended — never the other way round, and never silently.
