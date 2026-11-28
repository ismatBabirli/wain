# Google Play listing

`metadata/android/en-US/` is the listing for "Wain: AI Coding Agents" (`com.plorigo.wain`), in the layout `fastlane supply` reads. Nothing uploads it yet; paste it into Play Console, or upload it with the `PLAY_SERVICE_ACCOUNT` key the release uses.

Limits: title 30 characters, short description 80, full description 4000.

## Answers that live only in Play Console

- **Data safety.** Collected: Device or other IDs (Firebase's installation ID and the FCM token), for App functionality, required, encrypted in transit, not shared, no deletion request (Google holds it). Nothing else: no analytics, no account, and what the app sends to the user's own machines is not collected by us. Alert text passes straight through wainhq.com to Firebase.
- **Content rating (IARC):** Utility. No violence, no user-to-user interaction, no location sharing, no purchases.
- **Target audience:** 18 and over. Not designed for children.
- **Ads:** none.
- **App access:** some features need a paired machine; give the demo machine's address and code, as in `apps/ios/fastlane/metadata/review_information/notes.txt`.
- **Privacy policy:** https://www.wainhq.com/docs/reference/privacy
- **Graphics:** `images/icon.png` (512 × 512, written by `brand/build.py --install`), `images/featureGraphic.png` (1024 × 500), and five phone screenshots in `images/phoneScreenshots/` (1440 × 2560).

## Retaking the screenshots

The phone shots are real captures from a Pixel 7-sized emulator (1080 × 2400), framed on Paper's Store page next to the iPhone ones. Use the scratch server the iPhone retake seeds (`apps/ios/fastlane/README.md`), which the emulator reaches at `ws://10.0.2.2:<port>`. Before capturing, turn on dark mode and the demo status bar:

```bash
adb shell cmd uimode night yes
adb shell settings put global sysui_demo_allowed 1
adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941
adb shell am broadcast -a com.android.systemui.demo -e command network -e mobile hide
adb shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4 -e fully true
```

Pair through Enter an address, open each screen, and save it with `adb exec-out screencap -p > shot.png`. The frames are 9:16 because Play refuses a screenshot more than twice as tall as it is wide, which a raw 1080 × 2400 capture is.
