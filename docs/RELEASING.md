# Releases and public publishing

## Repository boundaries

This is a fresh, standalone repository. Only the integration, build tools, docs, harness source, artwork, and attributed upstream snapshot belong here. Local signing assets, input files, generated app bundles, diagnostics, unrelated app projects, and development history do not.

## Prepare artifacts

```sh
python3 scripts/build_carplay.py --compile-only
python3 scripts/package_release.py
python3 scripts/audit_release.py . --artifact release/YouDash-v0.1.0-build-kit.zip
```

Use an unsigned integration module and a source/patch kit as the default redistributable artifacts. Document the user's own input and signing requirements. For a private unsigned IPA, build using `--unsigned`, then audit the entire archive. Do not upload a personal signed app or simply remove its outer signature while leaving nested signatures/profiles.

Audit both source and every artifact. Reject profiles, certificates/private keys, credential patterns, device IDs, personal home-directory paths, and signed code. Also scan locally for your own names, private bundle IDs, certificate names, and team IDs; generic scanners cannot recognize every personal identifier. Do not put those private identifiers into a committed scanner configuration.

Include SHA-256 sums and a machine-readable manifest recording actual/reported versions and source revision. Do not publish profile UUIDs, device lists, signer identities, or account exports.

## Public launch preparation

Keep the repository private until its owner explicitly changes visibility. While private, search engines cannot index its README. Repository name/description/topics and an original social image are prepared for discoverability after publication, not a guarantee of reach.

Before a public launch:

- Review third-party binary distribution rights separately from the GPL source.
- Prefer a source/module release and user-supplied application input.
- Add an account-free, cropped demo captured with permission; label illustrations accurately.
- Keep claims concrete: native interface/player, controller handoff, responsive layouts. Do not claim “first,” universal compatibility, entitlement approval, or guaranteed playback without evidence.
- Re-run the source, history, and artifact privacy audit.

Draft public announcement:

> YouDash brings the native YouTube interface to a CarPlay display: responsive browsing, an on-screen keyboard, and video with a queue beside it. The integration source and reproducible build instructions are available. Experimental, with documented signing and compatibility requirements.

An optional Actions workflow template is in `docs/examples/build-workflow.yml`. Enable it under `.github/workflows/` only with repository/workflow authorization. No CI workflow is active by default.
