# IBIRAPAY Carteira

Carteira autocustodial para Android (Flutter): Bitcoin on-chain, Lightning (Breez SDK Spark) e stablecoins em Polygon e Solana.
Self-custodial Android wallet (Flutter): on-chain Bitcoin, Lightning (Breez SDK Spark) and stablecoins on Polygon and Solana.

Licença / License: GPL-3.0-or-later, see [LICENSE](LICENSE). Third-party notices: [THIRD_PARTY.md](THIRD_PARTY.md).

## Build
```
flutter pub get
tool/build-apk.sh --test      # test build, signed with a throwaway key (see the script)
```
The Spark SDK native library is built from source by the plugin (Rust and the Android NDK are needed).

## Network services
The app reads chains through relay endpoints on `pagcoin.org` (`rpc.pagcoin.org`, `spark-*.pagcoin.org`). They hold no keys and no funds,
and can be replaced at build time with `--dart-define` (`POLYGON_RELAY_URL`, `BTC_RELAY_URL`).

## Reporting security issues
Write to contact@ibirapay.com. Please do not open a public issue for a vulnerability.

## Verifying IBIRAPAY releases
Downloads are at https://ibirapay.com/baixar. Check what you get against these values, which are published here as a second source
besides the download server.

- **Wallet APK** (this app): signing certificate SHA-256 `98b371c09604d0b0fe9ab8d6bfcf387001af94c8f888766dd723a06428157a4c`.
  Check with `apksigner verify --print-certs <apk>`. The same app is on the F-Droid repository https://fdroid.ibirapay.com/repo.
- **IBIRAPAY PDV, Linux and Windows files**: each release has a `SHA256SUMS` signed with an OpenSSH key (namespace `ibirapay-release`).
  Key fingerprint `SHA256:JXVU0z6q+201/heBdGkxS1u2O3VIU216P5kpvlcII+I`. Check with
  `ssh-keygen -Y verify -f ibirapay-release-signers -I ibirapay-linux-release -n ibirapay-release -s SHA256SUMS.sig < SHA256SUMS`,
  then `sha256sum -c SHA256SUMS`. The `ibirapay-release-signers` file on the download page must show that fingerprint
  (`ssh-keygen -lf ibirapay-release-signers`).
- **IBIRAPAY PDV, Android**: signing certificate SHA-256 `73ce99c9b2b9ad02c1fa511eab2b4cdfdafe1a372759a13ccd8933cb847287f8`.
