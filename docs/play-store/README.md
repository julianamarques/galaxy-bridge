# Publishing on Google Play

Everything the Play Console asks for, and the order to do it in. The account is a personal one created after November 2023, so the app must go through a closed test before it can be published.

## Files

| File | For |
|---|---|
| [listing.md](listing.md) | Store listing: name, short and full descriptions in English and Portuguese, category |
| [`website/`](../../website) | The privacy policy in Portuguese (`privacy/`) and English (`en/privacy/`), published by GitHub Pages (`.github/workflows/pages.yml`) at <https://julianamarques.dev/galaxy-bridge/privacy/> and <https://julianamarques.dev/galaxy-bridge/en/privacy/> |
| [declarations.md](declarations.md) | Data safety answers, permission declarations, accessibility, foreground services, app access |
| `graphics/icon-512.png` | App icon (512 × 512) |
| `graphics/feature-graphic.png`, `graphics/feature-graphic-pt.png` | Feature graphic (1024 × 500), English and Portuguese |

Still missing: phone screenshots (at least 2, 1080 × 1920 or larger, 9:16) and the demo videos the declarations ask for.

## Build

```bash
cd android
./gradlew lintRelease bundleRelease
```

Upload `app/build/outputs/bundle/release/app-release.aab`. It is signed with the upload key in `~/.galaxy-bridge/upload.jks`; keep a backup of it and of `~/.galaxy-bridge/keystore.properties`. Enroll in **Play App Signing** when creating the app, so Google holds the app signing key and a lost upload key can be reset.

Raise `versionCode` in `android/app/build.gradle.kts` for every upload.

## Steps

1. **Create the app:** name "Galaxy Bridge for Mac", default language English (en-US), app, free.
2. **App content:** privacy policy URL, app access (from [declarations.md](declarations.md#app-access-for-the-reviewers)), ads (none), content rating questionnaire (no objectionable content), target audience 18+, data safety, government app (no), financial features (none), health (none).
3. **Sensitive permissions:** call log, all files access, photos and videos, accessibility and foreground services, each with its demo video (see [declarations.md](declarations.md)).
4. **Store listing:** texts from [listing.md](listing.md), icon, feature graphic, screenshots; add Portuguese (pt-BR) as a translation.
5. **Closed test:** create a closed testing track, upload the bundle, add at least 12 testers (by email or a Google Group) and share the opt-in link. They must stay opted in for 14 days in a row; each one needs a Mac with the Galaxy Bridge app to try it for real.
6. **Production access:** after the 14 days, apply in the Dashboard, answering the questions about the test. Google reviews the application (about a week).
7. **Production release:** promote the tested bundle to production.

Expect the sensitive permission reviews to take longer than the others; if one is refused, the answer says why, and the feature can be removed from the Play build and the app sent again.
