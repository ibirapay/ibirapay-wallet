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
