# Third-party notices and attribution

## Project source

The YouDash integration is distributed under GPL-3.0; see `LICENSE`.

## YouMod

`vendor/YouMod/` is an unmodified source snapshot from [Tonwalter888/YouMod](https://github.com/Tonwalter888/YouMod), commit `fb6a9f6f3bbfcbe8aa8b92debda6405f2b7be2d7`, under GPL-3.0. Its original README, license, comments, and credits are preserved. The development input used YouMod 2.0.0. YouMod in a supplied IPA is reused as a binary unless explicitly rebuilt by the developer.

## Reference and build tools

- [PoomSmart/YouTubeHeader](https://github.com/PoomSmart/YouTubeHeader), reference pin `4b9977e2b243fcb143395e0a20d975a32eaa93e0`.
- [asdfzxcvbn/pyzule-rw (cyan)](https://github.com/asdfzxcvbn/pyzule-rw), build dependency pin `740d3716dcd98c20c000f12cdb88f1f0b2a533a4`.
- [mrdrvt99/YouProEXTRA](https://github.com/mrdrvt99/YouProEXTRA), source of the compatible development input, actual YouTube 21.42.4 / YouMod 2.0.0. Input SHA-256: `57e93f6805c56fcc8b1c43f0a421475959061ff5df7b0fe7ffa36d0b1c9bf549`.
- Playback compatibility research: the upstream issues linked in `docs/COMPATIBILITY.md`.

## External application binaries

Google's YouTube application is proprietary. Its binary, resources, trademarks, and service are not relicensed as project source. Supplying or receiving an IPA does not grant a right to redistribute Google's code. Public release preparation should prefer the integration module/source and a builder accepting the user's own authorized input. Any private unsigned IPA asset retains the underlying third-party rights and requires the recipient's own authorized signing.

The repository does not include any source tree from a separate app project. The keyboard and native module included here are the self-contained files used by this integration.
