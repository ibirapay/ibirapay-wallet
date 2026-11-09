// Amount limits shared by Receber and Enviar.

import 'i18n.dart';

/// Smallest payment Spark accepts (its leaf limit); below it the network drops the payment, in both directions.
const minPaymentSats = 330;

/// Why [sats] cannot be paid or received, or null when it can. There is no upper limit: the firetest cap was lifted by the owner (11-05).
String? satsError(int? sats) {
  if (sats == null || sats <= 0) return tr('lim.enter');
  if (sats < minPaymentSats) return tr('lim.min', {'n': minPaymentSats});
  return null;
}
