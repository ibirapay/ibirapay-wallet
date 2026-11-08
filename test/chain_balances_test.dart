import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/chain_balances.dart';

void main() {
  test('stable balances print with two decimals, truncated, comma separator', () {
    expect(StableBalance('Polygon', 'USDT', BigInt.zero).text, '0,00');
    expect(StableBalance('Polygon', 'USDT', BigInt.from(1234567)).text, '1,23');
    expect(StableBalance('Solana', 'USDC', BigInt.from(999999)).text, '0,99');
    expect(StableBalance('Solana', 'USDC', BigInt.from(25000000)).text, '25,00');
  });

  test('a balance no node could read is unknown, never zero', () {
    expect(const StableBalance('Polygon', 'USDT', null).text, '?');
  });

  test('gas balances print four decimals, truncated: POL has 18 places, SOL 9', () {
    expect(const GasBalance('POL', null).text, '?');
    expect(GasBalance('POL', BigInt.zero).text, '0,0000');
    expect(GasBalance('POL', BigInt.parse('1234567890000000000')).text, '1,2345');
    expect(GasBalance('SOL', BigInt.from(25000000)).text, '0,0250');
    expect(GasBalance('SOL', BigInt.from(1999999999)).text, '1,9999');
  });
}
