# Dental Clinic TV (waiting screen)

A small Android TV app, separate from the Flutter app (2026-11-02, by request).
It only shows the clinic's waiting screen (`/waiting-screen`) full screen:

- First start asks for the server: the clinic's offline server (`http://clinic.lan`),
  the hosting, or any other address. Press MENU (or BACK) on the remote to change it.
- Starts by itself when the TV is switched on (allow "display over other apps" from
  the menu once, which Android 10+ requires for that).
- Retries by itself when the network or server is down, and keeps the screen awake.
- Updates itself: a minute after start and every 6 hours it asks the server
  (`/api/v1/app/version?platform=android_tv`, else the offline server's `/apps/releases.json`),
  downloads a newer APK and opens the install confirmation; it reopens by itself after.
  MENU → "التحقق من التحديث" checks right away.
- Plain `http://` works (clinic.lan or an IP), so the logo and pictures load too.

Built by `.github/workflows/flutter-apps.yml` (job `android_tv`), signed with the same
key as the phone app, and published as `DentalClinicTV-<version>.apk` on /download.
