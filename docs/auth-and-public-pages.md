# Authentication, Public Pages, Visual Theming & PWA

Staff and doctors were originally two entirely separate login systems (two
guards, two forms, a segmented "الموظفون/الأطباء" toggle). That's been
collapsed into **one `/login` form on both web and Flutter** that
auto-detects the account type server-side — there is no more registration
page and no more "which kind of account" question anywhere in the UI.

The app also carries a deliberate, repeatedly-reaffirmed visual identity
rule, first stated during the web UI redesign and later ported wholesale to
Flutter as an "Instagram-style" theme: a fixed, neutral **blue/black/white**
palette for everyday UI, plus one signature 5-stop rainbow gradient reserved
**only** for small accent moments (a brand mark, a loading ring, a story-ring
badge) — never a full-UI repaint, and never swapped for the admin-configurable
in-app theme. Every subsequent gradient use explicitly cites and reuses this
same rule rather than inventing a new look.

## Login & auth model

**Two guards, one form.** `config/auth.php` defines a `web` guard (`users`
table, roles `super_admin`/`admin`/`editor`/`doctor`/`accountant`/`senior`/`hr`)
and a `doctor` guard (`doctors` table). Both `User` and `Doctor` use Sanctum's
`HasApiTokens`, so one `auth:sanctum` middleware authenticates either kind of
token via Sanctum's polymorphic `personal_access_tokens.tokenable` — token
resolution doesn't go through `config/auth.php` at all, only session auth
does. A real config bug surfaced by this split: the `doctor` guard pointed at
a `providers.doctors` entry that was never actually added, so any code path
touching the doctor *session* guard (not Sanctum) crashed with a null-provider
error — invisible during the whole API-only phase and only surfaced once
doctor web login started exercising it. Fixed by adding the missing provider.

**Username-or-email, one field.** Both login forms accept either identifier
in a single `login` field; `LoginRequest`/`DoctorLoginRequest` use
`filter_var($input, FILTER_VALIDATE_EMAIL)` to decide whether `Auth::attempt()`
matches on `email` or `username` — only one key is ever passed, so it can't
widen into an unintended `OR` match.

**Unification (2026-08-24).** Self-registration was deleted outright
(`Register.vue`, `RegisteredUserController`, the `register` routes) — it only
ever created `role: editor` staff rows; staff accounts are still created,
just admin-only via the existing `UserController` flow. `LoginRequest::authenticate()`
now tries `Auth::guard('web')` first, then `Auth::guard('doctor')`, and the
post-login redirect picks `dashboard` vs `doctor.dashboard` based on whichever
guard actually authenticated. The old `/doctor/login` route,
`DoctorAuthenticatedSessionController`, and `DoctorLoginRequest` are gone;
doctor **logout** still needed its own trimmed controller (different
middleware), and doctor **password reset stayed a separate flow** on purpose
— the token broker needs to know which table to check, and merging it would
touch security-sensitive reset logic nobody asked to change.

Flutter mirrors this exactly: the `SegmentedButton<AccountType>` (طالب/موظف)
is gone, `AuthRepository.loginStaff()/loginDoctor()` collapsed into one
`login({identifier, password})` against `POST /login`, and the response's new
`account_type` key (`"staff"`/`"doctor"`) replaces "which button was tapped"
as the source of truth for routing/parsing downstream.

### "Sign in with Google"

`laravel/socialite` + `GoogleAuthController`, **sign-in only, never sign-up**
— a Google account is matched to an *existing* `users`/`doctors` row by email
and never used to create one, since neither audience has open self-registration.
One Google Cloud OAuth app serves both account types via a single redirect URI
(`/auth/google/callback`); after the login unification, the button auto-detects
by trying `User::where('email', ...)` then `Doctor::where('email', ...)`,
dropping the earlier session-stashed `{as}` parameter entirely. The button and
the server route are both hidden/404 unless `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET`
are configured — verified off by default in this install.

## Password reset (OTP flow)

Originally an emailed link (Laravel's `Password` broker for staff, a
duplicate `DoctorPasswordResetController` flow for doctors). Replaced,
by request, with a **5-minute one-time 6-digit code**, after investigating
two reported vulnerabilities first (per the project's "no guessing" rule):
"email editable after opening the link" turned out real at the UI level but
not exploitable (`Password::reset()` looks up by whatever email is submitted
and checks the token against that same row); "link still works after a day"
turned out to be the page merely *loading* past expiry, not a successful
reset — the actual reset submission was correctly time-checked. Both fixed
for clarity anyway (read-only email field), but the OTP switch was wanted
regardless — a typed code fits a native mobile client far better than a
link that has to hand off to a browser.

Built from scratch rather than reusing Laravel's link-shaped broker:
- **`password_reset_otps`** table — `(email, guard)` primary key (`guard`
  is `users`/`doctors`, mirroring the two auth providers), hashed `otp`,
  `expires_at`.
- **`App\Services\OtpPasswordResetBroker`** — `send()` (6-digit `random_int`,
  hashed, throttled to one new code per 60s/address), `verify()`
  (hash-check + expiry), `forget()` (single-use, deleted after a successful
  reset).
- **`App\Notifications\OtpPasswordReset`** — one notification class for both
  guards, replacing the framework default and a now-deleted
  `DoctorResetPassword` notification.

The reset-password GET routes dropped their `{token}` URL parameter (a typed
code carries nothing in the URL). On Flutter, this was the first version of
the flow with a real in-app completion step: the old link-based flow only
ever sent an email and pointed the user at a browser. `LoginScreen`'s "نسيت
كلمة المرور؟" dialog (added 2026-08-28, before the OTP switch, calling
`POST /api/v1/forgot-password` — deliberately not building a native reset
screen at that point since completion still happened via the emailed web
link) was rebuilt into a 2-step dialog: step 1 requests the code, and on
success the same dialog (via a `StatefulBuilder` step flag, no new route)
swaps to a code + new-password + confirm form, submitting to the new
`resetPasswordWithOtp()` / `POST /reset-password`.

**Two real production bugs found delivering this**, both eventually traced
to one root cause: OTP emails silently weren't sending. `LOG_LEVEL=error` in
production `.env` was silently dropping the `warning`/`debug` calls added to
diagnose it — so the first fix pass "fixed" logging visibility without yet
finding the real bug. The actual cause, found via cPanel Terminal + two
temporary diagnostic routes: `OtpPasswordResetBroker::send()`'s resend-throttle
check called `now()->diffInSeconds($existing->created_at)` with a **raw
database string** instead of a `Carbon` instance, which evaluated as "issued
within the last 60 seconds" *forever* — every request after the first ever
test row silently no-op'd before generating a new code. `verify()` had the
identical unsafe pattern, fixed pre-emptively once the risk was known. Both
now wrap the raw string in `Carbon::parse()`.

## Public landing page

Replaced the stock unmodified Laravel/Breeze `Welcome.vue` scaffold (still
the framework's own starter content after the whole rest of the rebuild)
with a real bilingual, teaching-hospital-branded page. `routes/web.php`'s
`/` route now pulls real `ClinicSetting` fields (name, description, contact
info, both logos) and real counts (doctors/departments/stages/education
types) instead of placeholder numbers. Visual language reuses the app's own
theme tokens (`bg-app`, `accent`, `rounded-card`, etc.) so the page follows
whichever admin-configured theme (`App\Support\ThemePalette`) is active
rather than hardcoding colors. Sections: header, hero (with a "شاشة الانتظار"
CTA linking the existing public TV-board route), a real-stats strip, a
features grid, and a contact block that only renders fields actually set.

Bilingual via a **local page-scoped toggle**, not a new i18n system — nothing
else in the app has one. Static chrome fully translates (including a
`dir="rtl"`/`dir="ltr"` swap); admin-entered content displays exactly as
entered in either language, since translating database content on the fly
would mean inventing text nobody wrote.

Two real bugs caught during this work: the route rewrite silently dropped
the pre-existing `canLogin` prop the login button still depended on (caught
by inspecting the live Inertia JSON, not assumed correct because the build
succeeded); and headless Edge's `--window-size` flag doesn't reliably produce
a screenshot matching the requested viewport on this machine even though the
DOM itself had no overflow — the reliable method was driving `Emulation.setDeviceMetricsOverride`
directly over the CDP WebSocket before capturing.

A matching public, unauthenticated `GET /branding` endpoint
(`Api\BrandingController`) was added for the Flutter login screen, which runs
pre-token and can't hit the existing `auth:sanctum`-gated `/clinic-settings`.
It hand-picks only `clinic_name`/`logo_url` rather than reusing the full
settings serializer, so the model's hidden secrets (mail password, MikroTik
credentials, JWT key) can never be reachable from an unauthenticated route.

## Instagram-style visual identity

**Web (2026-08-20).** Modelled on a supplied dental-unit control-panel
reference: near-black slate ground, raised large-radius cards, line icons,
and a mint accent used only on the active element. `clinic_settings.theme`
holds one of four palettes in `App\Support\ThemePalette` (`unit-dark` default,
`unit-blue`, `unit-violet`, `clinic-light`), applied as CSS custom properties
written server-side onto `<html>` by `app.blade.php` — deliberately not
resolved in JS, which would flash the previous palette on load. The theme
drives only the *chrome* (login areas, nav shells); ordinary page content
keeps its neutral light background with fixed Tailwind greys, since
repainting behind ~50 existing page components would produce dark-on-dark
text. `Components/BrandMark.vue` is a real SVG molar (two crown lobes, two
roots) painted with the theme's accent gradient, chosen over an icon-font
glyph because it needs to scale freely and carry a gradient.

**Flutter (2026-08-20).** A full pivot, not an extension of the web theme
system — `core/theme/app_theme.dart` was rewritten rather than adding a 5th
palette entry, since Instagram's identity has no "clinic sets it centrally"
concept at all. `InstagramColors`, each value traced to a specific real
Instagram UI element:
- `#0095F6` — action blue (buttons, links, focus rings, selected chips;
  same in light and dark mode)
- `#ED4956` — error/red
- `#000000` — dark-mode background (true black, not dark grey)
- `#262626` — near-black body text (light mode)
- `#8E8E8E` — secondary/muted text (both modes)
- `#DBDBDB` / `#262626` — hairline borders (light/dark)

Built by hand rather than `ColorScheme.fromSeed`, so every token maps to a
real observed color instead of an algorithmic derivation. Flat, hairline
cards with `elevation: 0` (Instagram has no drop-shadow chrome), 8px corner
radius (not Material's pill default), filled inputs with no visible border
until focused/errored. `MaterialApp.router` sets both `theme:`/`darkTheme:`
with `themeMode: ThemeMode.system`, following the OS preference the same way
Instagram's own app does.

**The brand gradient itself** — web's `tailwind.config.js`:
```
'ig-gradient': linear-gradient(135deg, #FEDA75, #FA7E1E, #D62976, #962FBF, #4F5BD5)
```
five stops, gold → orange → pink/magenta → purple → indigo-blue. Flutter's
`InstagramColors.gradient` carries the equivalent orange→pink→purple
story-ring colors. Both were defined early but deliberately spent sparingly
— matching how little the real Instagram app itself uses it — later applied
to: the web login button's loading spinner, the Flutter sidebar header badge,
the profile "story ring," and the PWA app icon.

**New app icon (Flutter, 2026-08-27).** A supplied college-seal photo (white
square background) was processed with ImageMagick (`-fuzz 8% -transparent
white -trim`) into separate derived assets: an opaque white-background PNG
for iOS (Apple's icon slot doesn't support transparency), safe-zone-inset
foreground/background pair for Android's adaptive icon, and a transparent
version for in-app use on dark screens. First attempt at the iOS icon used
`remove_alpha_ios: true` on the transparent source instead of a pre-flattened
one — that flag only forces alpha to opaque without compositing onto
anything, producing a solid **black** icon from whatever RGB ImageMagick had
stored under transparent pixels. Fixed by using a dedicated pre-flattened
white-background source for iOS.

Same pass fixed an architectural contrast bug on the Flutter login screen:
typed text was invisible (white-on-near-white). Root cause wasn't a per-field
color miss but each field's `fillColor` being hand-set to a near-white grey
while text color fell through to the ambient `instagramDarkTheme`'s
near-white default — never actually using the app's own correctly
light/dark-aware `inputDecorationTheme`. Fixed by rebuilding the screen to
inherit the ambient theme instead of fighting it with hardcoded overrides,
which incidentally delivered the actual "match the rest of the app" redesign
that had been requested — `SplashScreen` was deliberately left on its own
navy/gold look, so there's now an intentional brief style handoff between
splash and login rather than one continuous brand experience.

**Gradient loading spinner (2026-09-01).** Requested to make the login
button's loading animation "متوافقة مع instagram loading." Web:
`Components/IgSpinner.vue` — a rotating ring built from a `conic-gradient`
(same 5 stops/order as `ig-gradient`) masked down to a ring via
`radial-gradient` (CSS has no native gradient-stroke, so cutting a disc's
center out is the standard fake), spun with the existing `animate-spin`
utility, replacing the old plain Material Symbols spinner icon in
`Login.vue`. Flutter: `core/widgets/instagram_spinner.dart` —
`InstagramSpinner`, a `RotationTransition` driving a `CustomPainter` that
strokes a ring with a `SweepGradient` (a plain `LinearGradient` can't wrap a
full circle; colors are read directly from `InstagramColors.gradient.colors`
with the first color repeated at the end so the ring's seam meets cleanly),
replacing `CircularProgressIndicator` in both the login button and the
forgot-password dialog's submit button. Both re-use the exact existing
gradient rather than inventing a new one, explicitly citing the app's
established "gradient = accent only" rule.

## Installable PWA (web only, 2026-09-01)

By request ("انشئ pwa"), scoped to web only. Because this is a clinical app
(patient records, case sheets), the design deliberately avoids the usual
"offline-first app shell" PWA pattern — a stale cached page showing outdated
case-sheet data would be actively dangerous. **The service worker caches
only the site's own hashed, content-addressed, immutable `/build/*` JS/CSS/
font output — never HTML, never `/api/*`.**

**Manifest via a route, not a static file.** `App\Http\Controllers\PwaManifestController`
(`GET /manifest.webmanifest`) builds the manifest with `url()`/`asset()`
rather than a static `public/manifest.json`, because the app is served from
a sub-directory (`APP_URL=.../dental_laravel/public`) — a static file's URLs
would need hand-keeping in sync with deployment, while a route resolves
correctly from `127.0.0.1`, a LAN IP, or a real domain automatically.
`theme_color` is hardcoded to Instagram blue `#0095F6` rather than the
admin-configurable theme — the installed app's OS-level icon/splash identity
is a one-time thing, not something that should shift with an in-app theme
change, the same reasoning already used for other fixed `ig-*` tokens on
public pages.

**Icons.** `public/icons/icon-source.svg`/`icon-source-maskable.svg`
reproduce `BrandMark.vue`'s tooth path verbatim against the same 5-stop
gradient, scaled to 512×512 (maskable variant keeps the glyph in an ~80%
safe zone for OS icon masking). Rasterized to PNGs via a new
`scripts/generate-pwa-icons.mjs` (uses `sharp`, new devDependency), run
manually (`npm run generate:pwa-icons`) rather than wired into the build —
branding rarely changes and sharp's native binary shouldn't be a per-CI-run
cost.

**Service worker** (`public/sw.js`) is deliberately minimal: cache-first,
populate-on-miss, but only for `GET` requests whose URL contains `/build/`.
Every other request — HTML/navigation, `/api/*`, `storage/*` — has no
`respondWith` at all and falls straight to the network; there's no
`navigateFallback`, so a network failure shows the browser's native offline
error rather than any stale cached page that could look like a working app.
Registered inline in `app.blade.php` via Blade's `asset()` helper (not
routed through the Vite bundle), for the same sub-directory-correctness
reason `ThemePalette::cssVariables` is also inlined there directly.

Verified end-to-end against the real production domain (`cdclinics.com`):
manifest resolves with correct URLs, all three icons return 200, and the
service worker registers and reaches `activated`
(`navigator.serviceWorker.getRegistrations()`) — worth noting because the
sandboxed browser-automation tool used earlier in the session couldn't
confirm registration even for a trivial control file, pointing at a
restriction of that automation environment rather than a defect in `sw.js`.

**iOS "Add to Home Screen" hint.** Safari on iOS has no `beforeinstallprompt`
equivalent — Apple never implemented it on any iOS browser (all run on
WebKit) — so there's no way to trigger or detect installability
programmatically there. Added a small, dismissible, one-time banner in
`app.blade.php` pointing users at the manual Share-sheet path. Shown only
when: (1) iOS/iPadOS specifically, including iPadOS 13+'s "Macintosh" UA
spoof (detected via `navigator.platform === 'MacIntel' && maxTouchPoints > 1`);
(2) actually Safari, not another WebKit iOS browser carrying its own UA token
(`CriOS`/`FxiOS`/`EdgiOS`/`OPiOS` excluded — they don't necessarily expose the
same Share-sheet option); (3) not already running standalone
(`navigator.standalone === true`); (4) not previously dismissed
(permanent `localStorage` flag). Styled with the app's ordinary theme-picker
tokens, not the fixed `ig-*` PWA-icon tokens — this banner is regular in-app
UI a logged-in user sees under whichever theme is active, not a one-time OS
identity element.
