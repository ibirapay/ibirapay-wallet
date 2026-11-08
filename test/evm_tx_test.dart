import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/evm_tx.dart';
import 'package:wallet/wallet_seed.dart';

import 'stable_vectors.dart';

Eip1559Tx _tx(int nonce, int tip, int maxFee, int gas, String token, String to, int amount) => Eip1559Tx(
  nonce: nonce,
  maxPriorityFee: BigInt.from(tip),
  maxFee: BigInt.from(maxFee),
  gasLimit: gas,
  to: evmAddressBytes(token),
  data: erc20TransferData(to, BigInt.from(amount)),
);

void main() {
  test('RLP matches the published examples', () {
    Uint8List s(String t) => Uint8List.fromList(t.codeUnits);
    expect(bytesToHex(rlp(s('dog'))), '83646f67');
    expect(bytesToHex(rlp([s('cat'), s('dog')])), 'c88363617483646f67');
    expect(bytesToHex(rlp(Uint8List(0))), '80');
    expect(bytesToHex(rlp(<Object>[])), 'c0');
    expect(bytesToHex(rlp(rlpInt(BigInt.zero))), '80');
    expect(bytesToHex(rlp(rlpInt(BigInt.from(15)))), '0f');
    expect(bytesToHex(rlp(rlpInt(BigInt.from(1024)))), '820400');
    expect(
      bytesToHex(rlp(<Object>[<Object>[], <Object>[<Object>[]], <Object>[<Object>[], <Object>[<Object>[]]]])),
      'c7c0c1c0c3c0c1c0',
    );
    final long = s('Lorem ipsum dolor sit amet, consectetur adipisicing elit'); // 56 bytes: the first long-string form
    expect(bytesToHex(rlp(long)).startsWith('b838'), isTrue);
  });

  test('the test mnemonic derives the key and address the independent implementation has', () {
    final seed = mnemonicToSeed(vMnemonic.split(' '));
    final key = deriveEvmPrivateKey(seed);
    expect(bytesToHex(key), vEvmKeyHex);
    expect(deriveEvm(seed).address, vEvmAddress);
  });

  test('signed EIP-1559 USDT transfers equal the eth-account output byte for byte', () {
    final key = hexToBytes(vEvmKeyHex);
    for (final (nonce, tip, maxFee, gas, token, to, amount, raw, hash) in vEvm) {
      final signed = signTx(_tx(nonce, tip, maxFee, gas, token, to, amount), key, expectedAddress: vEvmAddress);
      expect(bytesToHex(signed.raw), raw.replaceFirst('0x', ''), reason: 'nonce $nonce');
      expect(signed.hashHex, '0x${hash.replaceFirst('0x', '')}');
    }
  });

  test('ERC-20 calldata is the 4-byte selector, the padded recipient and the padded amount', () {
    final d = erc20TransferData('0x742d35Cc6634C0532925a3b844Bc454e4438f44e', BigInt.from(1500000));
    expect(
      bytesToHex(d),
      'a9059cbb000000000000000000000000742d35cc6634c0532925a3b844bc454e4438f44e000000000000000000000000000000000000000000000000000000000016e360',
    );
    expect(() => erc20TransferData('0x742d', BigInt.one), throwsArgumentError);
    expect(() => erc20TransferData('0x742d35Cc6634C0532925a3b844Bc454e4438f44e', BigInt.zero), throwsArgumentError);
  });

  test('a key that is not the wallet is refused before anything is returned', () {
    final (nonce, tip, maxFee, gas, token, to, amount, _, _) = vEvm.first;
    final other = Uint8List(32)..[31] = 1;
    expect(() => signTx(_tx(nonce, tip, maxFee, gas, token, to, amount), other, expectedAddress: vEvmAddress), throwsA(isA<WalletError>()));
  });

  test('the signature recovers the signer key', () {
    final (nonce, tip, maxFee, gas, token, to, amount, _, _) = vEvm.first;
    final tx = _tx(nonce, tip, maxFee, gas, token, to, amount);
    final signed = signTx(tx, hexToBytes(vEvmKeyHex), expectedAddress: vEvmAddress);
    // tail of the raw tx is [yParity, r(32), s(32)] each RLP-prefixed: yParity 0x80 or 0x01, then 0xa0 + 32 bytes twice
    final t = signed.raw;
    final s = BigInt.parse(bytesToHex(t.sublist(t.length - 32)), radix: 16);
    final r = BigInt.parse(bytesToHex(t.sublist(t.length - 65, t.length - 33)), radix: 16);
    final v = t[t.length - 67] == 0x01 ? 1 : 0;
    expect(evmAddress(recoverPublicKey(tx.signingHash, r, s, v)), vEvmAddress);
  });
}
