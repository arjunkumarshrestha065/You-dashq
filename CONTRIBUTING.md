# Contributing

Keep changes focused on native YouTube CarPlay integration. Preserve the native phone lifecycle and the distinction between actual and reported app versions. Prefer positive, scoped feature detection over blanket changes to unknown native views.

Before proposing a change, read `docs/ARCHITECTURE.md` and `docs/COMPATIBILITY.md`. Describe the user-visible problem, resulting behavior, relevant version/display constraints, and validation actually performed. Do not claim a simulator harness proves behavior on physical head units.

Never commit IPAs, application bundles, provisioning profiles, certificates/private keys, account data, device IDs, raw logs, or personal paths. Use placeholders in examples. Report sensitive findings privately as described in `SECURITY.md`.

Use GPL-compatible contributions with proper attribution. Update notices when adding third-party source. Do not claim ownership of Google's or upstream contributors' code.
