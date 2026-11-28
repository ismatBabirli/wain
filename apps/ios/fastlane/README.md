# App Store listing

`metadata/` is the listing for "Wain: AI Coding Agents" (Apple ID 6839484995), in the layout `fastlane deliver` reads. Nothing uploads it yet; paste it into App Store Connect, or upload it with the "Wain CI" API key the release uses.

Limits: name and subtitle 30 characters, promotional text 170, keywords 100, description 4000. Keywords skip the words already in the name, and name no other app or trademark. Other agents are named only in the description, as what Wain works with.

`review_information/notes.txt` holds `DEMO_ADDRESS` and `DEMO_CODE` until a demo machine exists for App Review.

## Answers that live only in App Store Connect

- **App Privacy: Data Not Collected.** No analytics, no account. The push token goes to wainhq.com once, which seals it into a handle and keeps nothing; the handle lives on the user's own machines. Alert text passes straight through to Apple. Dictation runs on the phone or on the user's own Mac. The one judgment call: the relay keeps a per-phone alert count under a one-way hash of the token for about a day, to rate-limit.
- **Age rating: 4+.** Every content question is None. No user-to-user messaging, no web browsing, no ads. The app shows text the user's own coding agents write.
- **Category:** Developer Tools (`metadata/primary_category.txt`).
- **Price:** free, every country.
- **Export compliance:** HTTPS and standard crypto only, already declared by `ITSAppUsesNonExemptEncryption = NO`.
- **Screenshots:** `screenshots/en-US/`, five on a 6.9" iPhone (1320 × 2868) and four on a 13" iPad (2064 × 2752), since the app runs on iPad.

## Retaking the screenshots

Each shot is a real capture framed on Paper's Store page ("Wain — Design System"), so a change to a screen shown means a retake:

1. Seed and start a scratch server: `python3 apps/ios/scripts/store_seed.py /private/tmp/wain-store`, then the two commands its docstring gives.
2. On an iPhone 17 Pro Max and a 13-inch iPad simulator, set the region to US English (so the clock reads 9:41) and override the status bar: `xcrun simctl status_bar <udid> override --time 9:41 --batteryState discharging --batteryLevel 100 --wifiBars 3 --cellularBars 4`, and dark mode with `xcrun simctl ui <udid> appearance dark`.
3. Run `StoreShotsTests` on each, with `TEST_RUNNER_WAIN_URL=ws://127.0.0.1:<port>` and `TEST_RUNNER_WAIN_TOKEN` from the seed. Build signed as usual: without signing the app has no Keychain, and the server refuses its empty token.
4. Export the attachments (`xcrun xcresulttool export attachments`), drop each into its Paper frame, and export the frames at 1x.
