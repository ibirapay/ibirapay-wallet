// Every text of the app in its three languages: key -> (pt, en, es). `{name}` is replaced by the argument of the same name by tr();
// the three texts of an entry must carry the same names (test/i18n_test.dart checks it). Keep the terms the same everywhere:
// Disponível / Available / Disponible, Pendente / Pending / Pendiente, as 12 palavras / the 12 words / las 12 palabras.
// Spanish says "billetera" (Latin American), not "cartera".
const Map<String, (String, String, String)> strings = {
  'lang.title': ('Idioma', 'Language', 'Idioma'),
  'pin.enter': (
    'Digite o PIN',
    'Enter your PIN',
    'Introduce tu PIN',
  ),
  'pin.forgot': (
    'Esqueci o PIN',
    'Forgot PIN',
    'Olvidé el PIN',
  ),
  'pin.wait': (
    'Muitas tentativas. Tente de novo em {time}',
    'Too many tries. Try again in {time}',
    'Demasiados intentos. Inténtalo de nuevo en {time}',
  ),
  'pin.dead': (
    'PIN bloqueado: foram {n} tentativas erradas. Use "Esqueci o PIN" para apagar a carteira deste aparelho e restaurar com as 12 palavras.',
    'PIN locked: {n} wrong tries. Use "Forgot PIN" to erase the wallet on this device and restore it with the 12 words.',
    'PIN bloqueado: {n} intentos erróneos. Usa "Olvidé el PIN" para borrar la billetera de este dispositivo y restaurarla con las 12 palabras.',
  ),
  'pin.wrong1': (
    'PIN errado. Mais 1 tentativa antes de esperar.',
    'Wrong PIN. 1 more try before waiting.',
    'PIN incorrecto. 1 intento más antes de esperar.',
  ),
  'pin.wrongN': (
    'PIN errado. Mais {n} tentativas antes de esperar.',
    'Wrong PIN. {n} more tries before waiting.',
    'PIN incorrecto. {n} intentos más antes de esperar.',
  ),
  'pin.unreadable': (
    'Não consegui ler o PIN guardado neste aparelho.',
    'Could not read the PIN saved on this device.',
    'No pude leer el PIN guardado en este dispositivo.',
  ),
  'pin.create': (
    'Crie um PIN',
    'Create a PIN',
    'Crea un PIN',
  ),
  'pin.createWallet': (
    'Crie um PIN para proteger a carteira',
    'Create a PIN to protect the wallet',
    'Crea un PIN para proteger la billetera',
  ),
  'pin.repeat': (
    'Repita o PIN',
    'Repeat the PIN',
    'Repite el PIN',
  ),
  'pin.mismatch': (
    'Os dois PINs são diferentes. Comece de novo.',
    'The two PINs differ. Start again.',
    'Los dos PIN son distintos. Empieza de nuevo.',
  ),
  'pin.cannotSave': (
    'Não consegui guardar o PIN: {e}',
    'Could not save the PIN: {e}',
    'No pude guardar el PIN: {e}',
  ),
  'pin.createHint': (
    'De {min} a {max} números. Você vai usá-lo para abrir o app, enviar e ver as 12 palavras.',
    '{min} to {max} digits. You will use it to open the app, to send and to see the 12 words.',
    'De {min} a {max} números. Lo usarás para abrir la app, enviar y ver las 12 palabras.',
  ),
  'pin.repeatHint': (
    'Digite o mesmo PIN de novo para confirmar.',
    'Enter the same PIN again to confirm.',
    'Introduce el mismo PIN de nuevo para confirmar.',
  ),
  'pin.length': (
    'O PIN tem de ter de {min} a {max} números',
    'The PIN must have {min} to {max} digits',
    'El PIN debe tener de {min} a {max} números',
  ),
  'pin.repeated': (
    'Não use o mesmo número repetido',
    'Do not repeat the same digit',
    'No uses el mismo número repetido',
  ),
  'pin.sequence': (
    'Não use uma sequência como 1234 ou 4321',
    'Do not use a sequence like 1234 or 4321',
    'No uses una secuencia como 1234 o 4321',
  ),
  'del.title': (
    'Apagar carteira',
    'Delete wallet',
    'Borrar billetera',
  ),
  'del.word': (
    'APAGAR',
    'DELETE',
    'BORRAR',
  ),
  'del.hint': (
    'Digite {word} para confirmar',
    'Type {word} to confirm',
    'Escribe {word} para confirmar',
  ),
  'del.busy': (
    'Apagando...',
    'Deleting...',
    'Borrando...',
  ),
  'del.openSend': (
    'Há um envio de USDT/USDC em aberto. Espere ele terminar, ou cancele-o na tela inicial, antes de apagar a carteira.',
    'A USDT/USDC send is open. Wait for it to finish, or cancel it on the home screen, before deleting the wallet.',
    'Hay un envío de USDT/USDC abierto. Espera a que termine, o cancélalo en la pantalla de inicio, antes de borrar la billetera.',
  ),
  'del.oldSends': (
    'Há envios de USDT/USDC antigos sem resposta. Resolva, cancele ou descarte cada um na tela inicial (depois de conferir no explorador) antes de apagar a carteira.',
    'There are old USDT/USDC sends with no answer. Resolve, cancel or discard each one on the home screen (after checking the explorer) before deleting the wallet.',
    'Hay envíos antiguos de USDT/USDC sin respuesta. Resuelve, cancela o descarta cada uno en la pantalla de inicio (después de revisar en el explorador) antes de borrar la billetera.',
  ),
  'del.fail': (
    'Não consegui apagar tudo ({e}). A carteira só foi apagada se você voltar à tela de boas-vindas; tente de novo.',
    'Could not delete everything ({e}). The wallet is only deleted if you get back to the welcome screen; try again.',
    'No pude borrar todo ({e}). La billetera solo se borró si vuelves a la pantalla de bienvenida; inténtalo de nuevo.',
  ),
  'del.warn': (
    'Isto apaga as chaves desta carteira deste aparelho. Sem as 12 palavras, os sats, o USDT e o USDC dela ficam perdidos para sempre. Com as palavras você restaura a mesma carteira, aqui ou em outro aparelho.',
    'This deletes this wallet\'s keys from this device. Without the 12 words, its sats, USDT and USDC are lost forever. With the words you restore the same wallet, here or on another device.',
    'Esto borra las claves de esta billetera de este dispositivo. Sin las 12 palabras, sus sats, USDT y USDC se pierden para siempre. Con las palabras restauras la misma billetera, aquí o en otro dispositivo.',
  ),
  'del.loses': (
    'O que fica sem acesso neste aparelho',
    'What becomes inaccessible on this device',
    'Lo que queda sin acceso en este dispositivo',
  ),
  'del.locked': (
    'O app está bloqueado e não mostra o saldo.',
    'The app is locked and does not show the balance.',
    'La app está bloqueada y no muestra el saldo.',
  ),
  'del.noBalance': (
    'Nenhum saldo.',
    'No balance.',
    'Sin saldo.',
  ),
  'del.loadingNote': (
    'O saldo ainda está carregando e aparece aqui sozinho.',
    'The balance is still loading and will show up here by itself.',
    'El saldo aún se está cargando y aparece aquí solo.',
  ),
  'del.unanswered': (
    'Envios de USDT/USDC sem resposta, que podem ainda ser executados:',
    'USDT/USDC sends with no answer, which may still be executed:',
    'Envíos de USDT/USDC sin respuesta, que aún pueden ejecutarse:',
  ),
  'del.noteCodes': (
    'Anote os códigos acima: depois de restaurar, o app não vai lembrar deles.',
    'Write down the codes above: after restoring, the app will not remember them.',
    'Anota los códigos de arriba: después de restaurar, la app no los recordará.',
  ),
  'del.checkSends': (
    'Vou conferir esses envios no explorador antes de enviar de novo depois de restaurar',
    'I will check these sends on the explorer before sending again after restoring',
    'Revisaré estos envíos en el explorador antes de enviar de nuevo después de restaurar',
  ),
  'del.wrote': (
    'Anotei as 12 palavras em papel e conferi',
    'I wrote the 12 words on paper and checked them',
    'Anoté las 12 palabras en papel y las revisé',
  ),
  'bal.loading': (
    '{sym}: carregando...',
    '{sym}: loading...',
    '{sym}: cargando...',
  ),
  'bal.unreadable': (
    '{sym}: não consegui ler',
    '{sym}: could not read',
    '{sym}: no pude leer',
  ),
  'btc.syncing': (
    'SINCRONIZANDO',
    'SYNCING',
    'SINCRONIZANDO',
  ),
  'btc.balance': (
    'SALDO',
    'BALANCE',
    'SALDO',
  ),
  'btc.available': (
    'Disponível',
    'Available',
    'Disponible',
  ),
  'btc.pending': (
    'Pendente',
    'Pending',
    'Pendiente',
  ),
  'home.confirmCancel': (
    'Confirme o PIN para cancelar o envio',
    'Confirm your PIN to cancel the send',
    'Confirma tu PIN para cancelar el envío',
  ),
  'home.confirmSend': (
    'Confirme o PIN para enviar',
    'Confirm your PIN to send',
    'Confirma tu PIN para enviar',
  ),
  'home.received': (
    'Pagamento recebido',
    'Payment received',
    'Pago recibido',
  ),
  'home.tapClose': (
    'Toque para fechar',
    'Tap to close',
    'Toca para cerrar',
  ),
  'home.syncing': (
    'Sincronizando...',
    'Syncing...',
    'Sincronizando...',
  ),
  'home.empty': (
    'Nenhum pagamento ainda',
    'No payments yet',
    'Aún no hay pagos',
  ),
  'home.emptyHint': (
    'Seu histórico aparece aqui depois do primeiro pagamento enviado ou recebido.',
    'Your history shows up here after the first payment sent or received.',
    'Tu historial aparece aquí después del primer pago enviado o recibido.',
  ),
  'time.now': (
    'agora',
    'now',
    'ahora',
  ),
  'time.min': (
    '{n} min',
    '{n} min',
    '{n} min',
  ),
  'time.h': (
    '{n} h',
    '{n} h',
    '{n} h',
  ),
  'time.d': (
    '{n} d',
    '{n} d',
    '{n} d',
  ),
  'time.mo': (
    '{n} mes',
    '{n} mo',
    '{n} mes',
  ),
  'tx.in': (
    'Recebido',
    'Received',
    'Recibido',
  ),
  'tx.out': (
    'Enviado',
    'Sent',
    'Enviado',
  ),
  'tx.fee': (
    'taxa {fee}',
    'fee {fee}',
    'comisión {fee}',
  ),
  'tx.processing': (
    'PROCESSANDO',
    'PROCESSING',
    'PROCESANDO',
  ),
  'tx.failed': (
    'FALHOU',
    'FAILED',
    'FALLÓ',
  ),
  'btn.send': (
    'Enviar',
    'Send',
    'Enviar',
  ),
  'btn.receive': (
    'Receber',
    'Receive',
    'Recibir',
  ),
  'gas.label': (
    '{symbol} gás',
    '{symbol} gas',
    '{symbol} gas',
  ),
  'home.openSend': (
    'Envio em aberto: {amount} na {net}. Toque para ver',
    'Open send: {amount} on {net}. Tap to see',
    'Envío abierto: {amount} en {net}. Toca para ver',
  ),
  'info.title': (
    'Carteira',
    'Wallet',
    'Billetera',
  ),
  'info.confirmWords': (
    'Confirme o PIN para ver as 12 palavras',
    'Confirm your PIN to see the 12 words',
    'Confirma tu PIN para ver las 12 palabras',
  ),
  'info.confirmDelete': (
    'Confirme o PIN para apagar a carteira',
    'Confirm your PIN to delete the wallet',
    'Confirma tu PIN para borrar la billetera',
  ),
  'info.noCapture': (
    'Não consegui bloquear capturas de tela, então as palavras não serão mostradas.',
    'Could not block screenshots, so the words will not be shown.',
    'No pude bloquear las capturas de pantalla, así que las palabras no se mostrarán.',
  ),
  'info.copied': (
    'Copiado',
    'Copied',
    'Copiado',
  ),
  'info.addresses': (
    'Endereços para USDT e USDC',
    'Addresses for USDT and USDC',
    'Direcciones para USDT y USDC',
  ),
  'info.words': (
    'Palavras de recuperação',
    'Recovery words',
    'Palabras de recuperación',
  ),
  'info.hidden': (
    'Escondidas. Quem tiver estas 12 palavras controla todo o saldo.',
    'Hidden. Whoever has these 12 words controls the whole balance.',
    'Ocultas. Quien tenga estas 12 palabras controla todo el saldo.',
  ),
  'info.hide': (
    'Esconder',
    'Hide',
    'Ocultar',
  ),
  'info.show': (
    'Mostrar as 12 palavras',
    'Show the 12 words',
    'Mostrar las 12 palabras',
  ),
  'info.risk': (
    'Zona de risco',
    'Danger zone',
    'Zona de riesgo',
  ),
  'info.polyFallback': (
    'Polygon: nós públicos (relay indisponível)',
    'Polygon: public nodes (relay unavailable)',
    'Polygon: nodos públicos (relay no disponible)',
  ),
  'info.sparkFallback': (
    'Spark: conexão direta (relay indisponível)',
    'Spark: direct connection (relay unavailable)',
    'Spark: conexión directa (relay no disponible)',
  ),
  'main.connectFail': (
    'Não foi possível conectar: {e}',
    'Could not connect: {e}',
    'No fue posible conectar: {e}',
  ),
  'main.badWords': (
    'As palavras não formam uma carteira válida (12 palavras em inglês).',
    'These words do not make a valid wallet (12 words in English).',
    'Las palabras no forman una billetera válida (12 palabras en inglés).',
  ),
  'main.tagline': (
    'Bitcoin pela Lightning, USDT e USDC.\nVocê guarda as chaves.',
    'Bitcoin over Lightning, USDT and USDC.\nYou keep the keys.',
    'Bitcoin por Lightning, USDT y USDC.\nTú guardas las claves.',
  ),
  'main.create': (
    'Criar carteira',
    'Create wallet',
    'Crear billetera',
  ),
  'main.restoreWith': (
    'Restaurar com 12 palavras',
    'Restore with 12 words',
    'Restaurar con 12 palabras',
  ),
  'main.restoreTitle': (
    'Restaurar carteira',
    'Restore wallet',
    'Restaurar billetera',
  ),
  'main.restoreHint': (
    'as 12 palavras, separadas por espaço',
    'the 12 words, separated by spaces',
    'las 12 palabras, separadas por espacio',
  ),
  'main.restore': (
    'Restaurar',
    'Restore',
    'Restaurar',
  ),
  'main.retry': (
    'Tentar de novo',
    'Try again',
    'Intentar de nuevo',
  ),
  'scan.title': (
    'Escanear QR',
    'Scan QR',
    'Escanear QR',
  ),
  'scan.back': (
    'Voltar',
    'Back',
    'Volver',
  ),
  'scan.noPermission': (
    'Sem permissão para usar a câmera. Libere nas configurações do aparelho ou cole o código.',
    'No permission to use the camera. Allow it in the device settings or paste the code.',
    'Sin permiso para usar la cámara. Actívalo en los ajustes del dispositivo o pega el código.',
  ),
  'scan.cameraErr': (
    'Não consegui abrir a câmera ({code}).',
    'Could not open the camera ({code}).',
    'No pude abrir la cámara ({code}).',
  ),
  'scan.cameraFail': (
    'Não consegui abrir a câmera.',
    'Could not open the camera.',
    'No pude abrir la cámara.',
  ),
  'recv.title': (
    'Receber',
    'Receive',
    'Recibir',
  ),
  'recv.invoiceErr': (
    'Erro ao criar a fatura: {e}',
    'Error creating the invoice: {e}',
    'Error al crear la factura: {e}',
  ),
  'recv.amount': (
    'Valor',
    'Amount',
    'Monto',
  ),
  'recv.minimum': (
    'Pagamentos abaixo de {n} sats não são aceitos pela rede.',
    'Payments below {n} sats are not accepted by the network.',
    'Los pagos por debajo de {n} sats no son aceptados por la red.',
  ),
  'recv.creating': (
    'Criando...',
    'Creating...',
    'Creando...',
  ),
  'recv.create': (
    'Criar fatura',
    'Create invoice',
    'Crear factura',
  ),
  'recv.scan': (
    'Escaneie para pagar',
    'Scan to pay',
    'Escanea para pagar',
  ),
  'recv.copied': (
    'Copiado!',
    'Copied!',
    '¡Copiado!',
  ),
  'recv.copy': (
    'Copiar',
    'Copy',
    'Copiar',
  ),
  'recv.waiting': (
    'Aguardando o pagamento...',
    'Waiting for the payment...',
    'Esperando el pago...',
  ),
  'err.generic': (
    'Erro: {e}',
    'Error: {e}',
    'Error: {e}',
  ),
  'common.cancel': (
    'Cancelar',
    'Cancel',
    'Cancelar',
  ),
  'common.close': (
    'Fechar',
    'Close',
    'Cerrar',
  ),
  'common.continue': (
    'Continuar',
    'Continue',
    'Continuar',
  ),
  'common.discard': (
    'Descartar',
    'Discard',
    'Descartar',
  ),
  'common.paste': (
    'Colar',
    'Paste',
    'Pegar',
  ),
  'common.scan': (
    'Escanear',
    'Scan',
    'Escanear',
  ),
  'common.to': (
    'Para',
    'To',
    'Para',
  ),
  'common.amount': (
    'Valor',
    'Amount',
    'Monto',
  ),
  'common.done': (
    'Concluir',
    'Done',
    'Listo',
  ),
  'send.unsupported': (
    'Código não suportado neste teste',
    'Code not supported in this test version',
    'Código no admitido en esta versión de prueba',
  ),
  'send.prevInHistoryAmt': (
    'O envio anterior de {n} sats já consta no histórico. Toque em Continuar para fazer o novo envio.',
    'The previous send of {n} sats is already in the history. Tap Continue to make the new send.',
    'El envío anterior de {n} sats ya consta en el historial. Toca Continuar para hacer el nuevo envío.',
  ),
  'send.prevInHistory': (
    'O envio anterior já consta no histórico. Toque em Continuar para fazer o novo envio.',
    'The previous send is already in the history. Tap Continue to make the new send.',
    'El envío anterior ya consta en el historial. Toca Continuar para hacer el nuevo envío.',
  ),
  'send.noRecord': (
    'Ainda sem registro desse envio na carteira.',
    'This send is not in the wallet yet.',
    'Aún no hay registro de este envío en la billetera.',
  ),
  'send.discardTitle': (
    'Descartar o registro?',
    'Discard the record?',
    '¿Descartar el registro?',
  ),
  'send.discardBody': (
    'Se o envio anterior chegou a sair e você fizer outro, o valor sai duas vezes. Descarte só depois de conferir no histórico.',
    'If the previous send did go out and you make another one, the amount goes out twice. Discard only after checking the history.',
    'Si el envío anterior llegó a salir y haces otro, el monto sale dos veces. Descarta solo después de revisar el historial.',
  ),
  'send.invoice': (
    'a fatura',
    'the invoice',
    'la factura',
  ),
  'send.badAddress': (
    'Endereço Bitcoin não reconhecido',
    'Bitcoin address not recognised',
    'Dirección Bitcoin no reconocida',
  ),
  'send.addressChanged': (
    'O endereço mudou durante a preparação. Refaça o envio.',
    'The address changed during preparation. Make the send again.',
    'La dirección cambió durante la preparación. Rehaz el envío.',
  ),
  'send.quoteExpired': (
    'A cotação da taxa expirou. Feche e refaça o envio.',
    'The fee quote expired. Close and make the send again.',
    'La cotización de la comisión expiró. Cierra y rehaz el envío.',
  ),
  'send.notRecorded': (
    'Não consegui registrar o envio, nada foi enviado ({e})',
    'Could not record the send, nothing was sent ({e})',
    'No pude registrar el envío, no se envió nada ({e})',
  ),
  'send.quoteRefreshed': (
    'A cotação da taxa expirou e foi atualizada. Confira a taxa e confirme de novo.',
    'The fee quote expired and was refreshed. Check the fee and confirm again.',
    'La cotización de la comisión expiró y se actualizó. Revisa la comisión y confirma de nuevo.',
  ),
  'send.quoteExpiredE': (
    'A cotação da taxa expirou: {e}',
    'The fee quote expired: {e}',
    'La cotización de la comisión expiró: {e}',
  ),
  'send.sentWaiting': (
    'Enviado, aguardando confirmação',
    'Sent, waiting for confirmation',
    'Enviado, esperando confirmación',
  ),
  'send.redeemed': (
    'Resgate concluído',
    'Redeem complete',
    'Canje completado',
  ),
  'send.paid': (
    'Pagamento enviado',
    'Payment sent',
    'Pago enviado',
  ),
  'send.processing': (
    'Processando',
    'Processing',
    'Procesando',
  ),
  'send.failed': (
    'Falhou',
    'Failed',
    'Falló',
  ),
  'send.title': (
    'Enviar ou resgatar',
    'Send or redeem',
    'Enviar o canjear',
  ),
  'send.inputHint': (
    'Fatura (lnbc...), voucher (LNURL1...) ou user@dominio',
    'Invoice (lnbc...), voucher (LNURL1...) or user@domain',
    'Factura (lnbc...), voucher (LNURL1...) o user@dominio',
  ),
  'send.reading': (
    'Lendo...',
    'Reading...',
    'Leyendo...',
  ),
  'send.howMuch': (
    'Quanto enviar?',
    'How much to send?',
    '¿Cuánto enviar?',
  ),
  'send.minimum': (
    'Mínimo de {n} sats por pagamento.',
    'Minimum of {n} sats per payment.',
    'Mínimo de {n} sats por pago.',
  ),
  'send.calculating': (
    'Calculando...',
    'Calculating...',
    'Calculando...',
  ),
  'send.youWillRedeem': (
    'Você vai resgatar',
    'You will redeem',
    'Vas a canjear',
  ),
  'send.youWillSend': (
    'Você vai enviar',
    'You will send',
    'Vas a enviar',
  ),
  'send.voucher': (
    'Voucher',
    'Voucher',
    'Voucher',
  ),
  'send.networkFee': (
    'Taxa de rede',
    'Network fee',
    'Comisión de red',
  ),
  'send.total': (
    'Total',
    'Total',
    'Total',
  ),
  'send.redeem': (
    'Resgatar',
    'Redeem',
    'Canjear',
  ),
  'send.openTitle': (
    'Envio em aberto',
    'Open send',
    'Envío abierto',
  ),
  'send.openBody': (
    'Um envio on-chain anterior não teve resultado confirmado. Se ele saiu e você enviar outro, o valor sai duas vezes. Confira o histórico.',
    'A previous on-chain send had no confirmed result. If it went out and you send another, the amount goes out twice. Check the history.',
    'Un envío on-chain anterior no tuvo resultado confirmado. Si salió y envías otro, el monto sale dos veces. Revisa el historial.',
  ),
  'send.recheck': (
    'Conferir de novo',
    'Check again',
    'Revisar de nuevo',
  ),
  'send.resume': (
    'Tentar de novo com a mesma chave',
    'Try again with the same key',
    'Reintentar con la misma clave',
  ),
  'send.sending': (
    'Enviando...',
    'Sending...',
    'Enviando...',
  ),
  'send.keepOpen': (
    'Não feche o aplicativo',
    'Do not close the app',
    'No cierres la aplicación',
  ),
  'onc.wrongNetwork': (
    'Endereço de outra rede ({net}). Use um endereço Bitcoin da rede principal.',
    'Address of another network ({net}). Use a Bitcoin mainnet address.',
    'Dirección de otra red ({net}). Usa una dirección Bitcoin de la red principal.',
  ),
  'onc.unconfirmed': (
    'Não confirmado - confira o histórico antes de reenviar',
    'Not confirmed - check the history before sending again',
    'No confirmado - revisa el historial antes de reenviar',
  ),
  'onc.fast': (
    'Rápido',
    'Fast',
    'Rápido',
  ),
  'onc.medium': (
    'Médio',
    'Medium',
    'Medio',
  ),
  'onc.slow': (
    'Lento',
    'Slow',
    'Lento',
  ),
  'onc.feeAboveLimit': (
    'Taxa de rede acima do limite (precisa de {n} sats). Tente de novo quando baixar.',
    'Network fee above the limit (needs {n} sats). Try again when it drops.',
    'Comisión de red por encima del límite (necesita {n} sats). Inténtalo de nuevo cuando baje.',
  ),
  'onc.tooSmall': (
    'Valor pequeno demais para ser resgatado (a taxa passa do valor).',
    'Amount too small to be claimed (the fee is higher than the amount).',
    'Monto demasiado pequeño para canjearse (la comisión supera el monto).',
  ),
  'onc.noTx': (
    'Transação ainda não encontrada na rede.',
    'Transaction not found on the network yet.',
    'Transacción aún no encontrada en la red.',
  ),
  'onc.cannotClaim': (
    'Não foi possível resgatar agora: {e}',
    'Could not claim now: {e}',
    'No fue posible canjear ahora: {e}',
  ),
  'onc.waiting': (
    'Aguardando {n} confirmações',
    'Waiting for {n} confirmations',
    'Esperando {n} confirmaciones',
  ),
  'onc.confirmed': (
    'Confirmado, resgatando...',
    'Confirmed, claiming...',
    'Confirmado, canjeando...',
  ),
  'onc.addressErr': (
    'Erro ao criar o endereço: {e}',
    'Error creating the address: {e}',
    'Error al crear la dirección: {e}',
  ),
  'onc.payFeeTitle': (
    'Pagar a taxa de rede?',
    'Pay the network fee?',
    '¿Pagar la comisión de red?',
  ),
  'onc.payFeeBody': (
    'Resgatar este depósito de {amount} sats custa {fee} sats de taxa de rede, descontados do valor.',
    'Claiming this deposit of {amount} sats costs {fee} sats of network fee, taken from the amount.',
    'Canjear este depósito de {amount} sats cuesta {fee} sats de comisión de red, descontados del monto.',
  ),
  'onc.copyAddress': (
    'Copiar endereço',
    'Copy address',
    'Copiar dirección',
  ),
  'onc.note': (
    'Só envie Bitcoin (rede principal). O saldo entra depois de {n} confirmações, mesmo com o app fechado. A taxa de resgate sai do valor depositado. Mínimo: {min} sats mais a taxa.',
    'Only send Bitcoin (mainnet). The balance arrives after {n} confirmations, even with the app closed. The claim fee comes out of the deposited amount. Minimum: {min} sats plus the fee.',
    'Envía solo Bitcoin (red principal). El saldo entra después de {n} confirmaciones, incluso con la app cerrada. La comisión de canje sale del monto depositado. Mínimo: {min} sats más la comisión.',
  ),
  'onc.deposit': (
    'Depósito',
    'Deposit',
    'Depósito',
  ),
  'onc.claimPaying': (
    'Resgatar pagando {fee} sats',
    'Claim, paying {fee} sats',
    'Canjear pagando {fee} sats',
  ),
  'st.enterAmount': (
    'Digite um valor',
    'Enter an amount',
    'Escribe un monto',
  ),
  'st.badAmount': (
    'Valor inválido: use só números e uma vírgula ou ponto',
    'Invalid amount: use only numbers and one comma or dot',
    'Monto inválido: usa solo números y una coma o un punto',
  ),
  'st.decimals': (
    'No máximo {n} casas decimais',
    'At most {n} decimal places',
    'Como máximo {n} decimales',
  ),
  'st.ambiguous': (
    'Valor ambíguo: "{t}" pode ser {a} ou {b}. Digite um dos dois sem o separador do meio',
    'Ambiguous amount: "{t}" could be {a} or {b}. Type one of the two without the middle separator',
    'Monto ambiguo: "{t}" puede ser {a} o {b}. Escribe uno de los dos sin el separador del medio',
  ),
  'st.zero': (
    'O valor precisa ser maior que zero',
    'The amount must be greater than zero',
    'El monto debe ser mayor que cero',
  ),
  'st.badPolygon': (
    'Endereço inválido. Um endereço Polygon começa com 0x e tem 42 caracteres',
    'Invalid address. A Polygon address starts with 0x and has 42 characters',
    'Dirección inválida. Una dirección Polygon empieza con 0x y tiene 42 caracteres',
  ),
  'st.qrOtherChain': (
    'Esse QR é para outra rede (cadeia {chain}), não para a Polygon. Nada foi enviado',
    'This QR is for another network (chain {chain}), not for Polygon. Nothing was sent',
    'Este QR es para otra red (cadena {chain}), no para Polygon. No se envió nada',
  ),
  'st.qrFunction': (
    'Esse QR chama uma função ("{fn}") que o app não suporta. Nada foi enviado',
    'This QR calls a function ("{fn}") that the app does not support. Nothing was sent',
    'Este QR llama a una función ("{fn}") que la app no admite. No se envió nada',
  ),
  'st.qrOtherToken': (
    'Esse QR pede o pagamento em outro token ou contrato, não no que você escolheu. Nada foi enviado',
    'This QR asks for payment in another token or contract, not the one you chose. Nothing was sent',
    'Este QR pide el pago en otro token o contrato, no en el que elegiste. No se envió nada',
  ),
  'st.qrNoRecipient': (
    'Esse QR de pagamento de token não traz o endereço do destinatário. Nada foi enviado',
    'This token payment QR has no recipient address. Nothing was sent',
    'Este QR de pago de token no trae la dirección del destinatario. No se envió nada',
  ),
  'st.typo': (
    'O endereço tem um erro de digitação (a soma de verificação não confere)',
    'The address has a typo (the checksum does not match)',
    'La dirección tiene un error de tipeo (la suma de verificación no coincide)',
  ),
  'st.zeroAddress': (
    'Esse é o endereço zero: tudo que for enviado para ele se perde',
    'That is the zero address: anything sent to it is lost',
    'Esa es la dirección cero: todo lo que se envíe a ella se pierde',
  ),
  'st.tokenContract': (
    'Esse endereço é o contrato de um token: enviar para ele perde os fundos',
    'That address is a token contract: sending to it loses the funds',
    'Esa dirección es el contrato de un token: enviar a ella pierde los fondos',
  ),
  'st.badSolana': (
    'Endereço inválido. Um endereço Solana tem de 32 a 44 letras e números',
    'Invalid address. A Solana address has 32 to 44 letters and digits',
    'Dirección inválida. Una dirección Solana tiene de 32 a 44 letras y números',
  ),
  'st.noRegistry': (
    'Não consegui acessar o registro de envios do aparelho. Nada foi enviado',
    'Could not access the device\'s send record. Nothing was sent',
    'No pude acceder al registro de envíos del dispositivo. No se envió nada',
  ),
  'st.queryRefused': (
    'A rede recusou a consulta: {e}',
    'The network refused the query: {e}',
    'La red rechazó la consulta: {e}',
  ),
  'st.noNodeRetry': (
    'Nenhum nó da {net} respondeu. Verifique a internet e tente de novo',
    'No {net} node answered. Check the internet and try again',
    'Ningún nodo de {net} respondió. Verifica internet e inténtalo de nuevo',
  ),
  'st.openSend': (
    'Há um envio em aberto na {net}. Confira o resultado dele (aviso na tela inicial) antes de enviar de novo',
    'A send is open on {net}. Check its result (notice on the home screen) before sending again',
    'Hay un envío abierto en {net}. Revisa su resultado (aviso en la pantalla de inicio) antes de enviar de nuevo',
  ),
  'st.netRefusedNothing': (
    'A rede recusou: {e}. Nada foi enviado',
    'The network refused: {e}. Nothing was sent',
    'La red rechazó: {e}. No se envió nada',
  ),
  'st.noNodeNothing': (
    'Nenhum nó da {net} respondeu. Nada foi enviado',
    'No {net} node answered. Nothing was sent',
    'Ningún nodo de {net} respondió. No se envió nada',
  ),
  'st.noBaseFee': (
    'O nó da Polygon não informou a taxa base. Tente de novo',
    'The Polygon node did not report the base fee. Try again',
    'El nodo de Polygon no informó la comisión base. Inténtalo de nuevo',
  ),
  'st.wrongChainNode': (
    'O nó respondeu de outra rede, não da Polygon. Nada foi enviado',
    'The node answered from another network, not Polygon. Nothing was sent',
    'El nodo respondió desde otra red, no Polygon. No se envió nada',
  ),
  'st.lowBalancePoly': (
    'Saldo insuficiente de {sym} na Polygon: você tem {have}',
    'Not enough {sym} on Polygon: you have {have}',
    'Saldo insuficiente de {sym} en Polygon: tienes {have}',
  ),
  'st.polyRefusedTransfer': (
    'A Polygon recusou a transferência: {e}',
    'Polygon refused the transfer: {e}',
    'Polygon rechazó la transferencia: {e}',
  ),
  'st.lowPol': (
    'POL insuficiente para o gás: precisa de até {need} POL e você tem {have} POL. Mande um pouco de POL para o seu endereço Polygon',
    'Not enough POL for gas: you need up to {need} POL and you have {have} POL. Send a little POL to your Polygon address',
    'POL insuficiente para el gas: necesitas hasta {need} POL y tienes {have} POL. Envía un poco de POL a tu dirección Polygon',
  ),
  'st.ownWallet': (
    'O destino é a sua própria carteira',
    'The destination is your own wallet',
    'El destino es tu propia billetera',
  ),
  'st.polyRefusedSend': (
    'A Polygon recusou o envio: {e}',
    'Polygon refused the send: {e}',
    'Polygon rechazó el envío: {e}',
  ),
  'st.frozenOwn': (
    'Sua conta de {sym} na Solana está congelada pelo emissor do token: não dá para enviar daqui',
    'Your {sym} account on Solana is frozen by the token issuer: you cannot send from here',
    'Tu cuenta de {sym} en Solana está congelada por el emisor del token: no se puede enviar desde aquí',
  ),
  'st.lowBalanceSol': (
    'Saldo insuficiente de {sym} na Solana: você tem {have}',
    'Not enough {sym} on Solana: you have {have}',
    'Saldo insuficiente de {sym} en Solana: tienes {have}',
  ),
  'st.splitAccounts': (
    'Seu saldo de {sym} está dividido em várias contas e nenhuma tem o valor todo. Envie um valor menor',
    'Your {sym} balance is split across several accounts and none holds the whole amount. Send a smaller amount',
    'Tu saldo de {sym} está dividido en varias cuentas y ninguna tiene el monto completo. Envía un monto menor',
  ),
  'st.destFrozenOrInvalid': (
    'A conta de {sym} desse endereço está congelada ou inválida. Nada foi enviado',
    'The {sym} account of that address is frozen or invalid. Nothing was sent',
    'La cuenta de {sym} de esa dirección está congelada o es inválida. No se envió nada',
  ),
  'st.otherTokenAccount': (
    'Esse endereço é uma conta de token de outra moeda. Use o endereço da carteira do destinatário',
    'That address is a token account of another currency. Use the recipient\'s wallet address',
    'Esa dirección es una cuenta de token de otra moneda. Usa la dirección de billetera del destinatario',
  ),
  'st.destFrozen': (
    'A conta de {sym} desse endereço está congelada. Nada foi enviado',
    'The {sym} account of that address is frozen. Nothing was sent',
    'La cuenta de {sym} de esa dirección está congelada. No se envió nada',
  ),
  'st.notWallet': (
    'Esse endereço não é uma carteira (pertence a um programa). Nada foi enviado',
    'That address is not a wallet (it belongs to a program). Nothing was sent',
    'Esa dirección no es una billetera (pertenece a un programa). No se envió nada',
  ),
  'st.lowSol': (
    'SOL insuficiente para a taxa: precisa de {need} SOL{rent} e você tem {have}. Mande um pouco de SOL para o seu endereço Solana',
    'Not enough SOL for the fee: you need {need} SOL{rent} and you have {have}. Send a little SOL to your Solana address',
    'SOL insuficiente para la comisión: necesitas {need} SOL{rent} y tienes {have}. Envía un poco de SOL a tu dirección Solana',
  ),
  'st.rentNote': (
    ' (taxa e conta do destinatário)',
    ' (fee and recipient account)',
    ' (comisión y cuenta del destinatario)',
  ),
  'st.belowMinSol': (
    'O seu SOL restante ficaria abaixo do mínimo que a Solana exige numa conta ({min} SOL). Mande mais SOL',
    'Your remaining SOL would fall below the minimum Solana requires in an account ({min} SOL). Send more SOL',
    'Tu SOL restante quedaría por debajo del mínimo que Solana exige en una cuenta ({min} SOL). Envía más SOL',
  ),
  'st.simRefused': (
    'A Solana recusou a simulação: {e}. Nada foi enviado',
    'Solana refused the simulation: {e}. Nothing was sent',
    'Solana rechazó la simulación: {e}. No se envió nada',
  ),
  'st.solRefusedSend': (
    'A Solana recusou o envio: {e}',
    'Solana refused the send: {e}',
    'Solana rechazó el envío: {e}',
  ),
  'st.onlyPolyCancel': (
    'Só um envio da Polygon pode ser cancelado assim',
    'Only a Polygon send can be cancelled this way',
    'Solo un envío de Polygon puede cancelarse así',
  ),
  'st.tooOldCancel': (
    'Esse envio tem mais de 1 hora: confira a transação no Polygonscan, que guarda o histórico completo',
    'This send is more than 1 hour old: check the transaction on Polygonscan, which keeps the full history',
    'Este envío tiene más de 1 hora: revisa la transacción en Polygonscan, que guarda el historial completo',
  ),
  'st.lowPolCancel': (
    'POL insuficiente para cancelar: precisa de até {need} POL e você tem {have}',
    'Not enough POL to cancel: you need up to {need} POL and you have {have}',
    'POL insuficiente para cancelar: necesitas hasta {need} POL y tienes {have}',
  ),
  'st.polyRefusedCancel': (
    'A Polygon recusou o cancelamento: {e}',
    'Polygon refused the cancellation: {e}',
    'Polygon rechazó la cancelación: {e}',
  ),
  'st.netRefused': (
    'A rede recusou: {e}',
    'The network refused: {e}',
    'La red rechazó: {e}',
  ),
  'st.noNodePoly': (
    'Nenhum nó da Polygon respondeu. Tente de novo',
    'No Polygon node answered. Try again',
    'Ningún nodo de Polygon respondió. Inténtalo de nuevo',
  ),
  'st.recentSend': (
    'Esse envio é recente: a rede o resolve sozinha ou dá para cancelá-lo',
    'This send is recent: the network settles it by itself, or you can cancel it',
    'Este envío es reciente: la red lo resuelve sola o puedes cancelarlo',
  ),
  'st.internal': (
    'Erro interno ao assinar. Nada foi enviado',
    'Internal error while signing. Nothing was sent',
    'Error interno al firmar. No se envió nada',
  ),
  'sts.unexpected': (
    'Erro inesperado: {e}',
    'Unexpected error: {e}',
    'Error inesperado: {e}',
  ),
  'sts.unexpectedCheck': (
    'Erro inesperado: {e}. Confira o saldo e o histórico no explorador antes de enviar de novo',
    'Unexpected error: {e}. Check the balance and the history on the explorer before sending again',
    'Error inesperado: {e}. Revisa el saldo y el historial en el explorador antes de enviar de nuevo',
  ),
  'sts.title': (
    'Enviar USDT ou USDC',
    'Send USDT or USDC',
    'Enviar USDT o USDC',
  ),
  'sts.addressPoly': (
    'Endereço Polygon (0x...)',
    'Polygon address (0x...)',
    'Dirección Polygon (0x...)',
  ),
  'sts.addressSol': (
    'Endereço Solana',
    'Solana address',
    'Dirección Solana',
  ),
  'sts.balance': (
    'Saldo: {v}',
    'Balance: {v}',
    'Saldo: {v}',
  ),
  'sts.all': (
    'Tudo',
    'All',
    'Todo',
  ),
  'sts.gasNote': (
    'O gás é pago em {gas}, da sua própria carteira. Envie só para um endereço da rede {net}.',
    'Gas is paid in {gas}, from your own wallet. Send only to an address on the {net} network.',
    'El gas se paga en {gas}, desde tu propia billetera. Envía solo a una dirección de la red {net}.',
  ),
  'sts.consulting': (
    'Consultando a rede...',
    'Querying the network...',
    'Consultando la red...',
  ),
  'sts.networkFeeUpTo': (
    'Taxa de rede (até)',
    'Network fee (up to)',
    'Comisión de red (hasta)',
  ),
  'sts.recipientAccount': (
    'Conta do destinatário (1ª vez)',
    'Recipient account (first time)',
    'Cuenta del destinatario (1ª vez)',
  ),
  'sts.gasLeft': (
    'Gás que sobra',
    'Gas left over',
    'Gas restante',
  ),
  'sts.checkNet': (
    'Confira se o destinatário recebe na rede {net}: {sym} enviado para outra rede se perde.',
    'Check that the recipient receives on the {net} network: {sym} sent to another network is lost.',
    'Verifica que el destinatario recibe en la red {net}: {sym} enviado a otra red se pierde.',
  ),
  'sts.sendingNote': (
    'Não feche o aplicativo. Pode levar até um minuto e meio',
    'Do not close the app. It can take up to a minute and a half',
    'No cierres la aplicación. Puede tardar hasta un minuto y medio',
  ),
  'sts.notSent': (
    'Não foi enviado',
    'Not sent',
    'No se envió',
  ),
  'sts.sent': (
    'Enviado',
    'Sent',
    'Enviado',
  ),
  'sts.confirmedOn': (
    'A transação foi confirmada na {net}.',
    'The transaction was confirmed on {net}.',
    'La transacción fue confirmada en {net}.',
  ),
  'sts.txFailed': (
    'A transação falhou',
    'The transaction failed',
    'La transacción falló',
  ),
  'sts.revertedBody': (
    'Ela foi executada e rejeitada pela rede: os {sym} NÃO saíram, mas o gás foi gasto.',
    'It was executed and rejected by the network: the {sym} did NOT leave, but the gas was spent.',
    'Se ejecutó y la red la rechazó: los {sym} NO salieron, pero el gas se gastó.',
  ),
  'sts.expiredBody': (
    'A transação expirou antes de entrar na rede. Nada foi cobrado. Pode tentar de novo.',
    'The transaction expired before entering the network. Nothing was charged. You can try again.',
    'La transacción expiró antes de entrar en la red. No se cobró nada. Puedes intentarlo de nuevo.',
  ),
  'sts.pendingTitle': (
    'Enviado, ainda sem confirmação',
    'Sent, not confirmed yet',
    'Enviado, aún sin confirmación',
  ),
  'sts.pendingBody': (
    'Não dá para saber ainda se entrou. O envio ficou registrado e o app confere sozinho. NÃO envie de novo antes de conferir: pode pagar duas vezes.',
    'It is not yet known whether it went in. The send is recorded and the app checks by itself. Do NOT send again before checking: you may pay twice.',
    'Aún no se sabe si entró. El envío quedó registrado y la app revisa sola. NO envíes de nuevo antes de revisar: podrías pagar dos veces.',
  ),
  'sts.linkCopied': (
    'Link copiado',
    'Link copied',
    'Enlace copiado',
  ),
  'sts.copyLink': (
    'Copiar link do explorador',
    'Copy explorer link',
    'Copiar enlace del explorador',
  ),
  'ss.receiveTitle': (
    'Receber USDT ou USDC',
    'Receive USDT or USDC',
    'Recibir USDT o USDC',
  ),
  'ss.network': (
    'Rede {net}',
    '{net} network',
    'Red {net}',
  ),
  'ss.copyAddress': (
    'Copiar endereço',
    'Copy address',
    'Copiar dirección',
  ),
  'ss.addressCopied': (
    'Endereço copiado',
    'Address copied',
    'Dirección copiada',
  ),
  'ss.onlyOn': (
    'Envie somente USDT ou USDC pela rede {net}. Tokens enviados por outra rede ficam perdidos. O mesmo endereço recebe os dois.',
    'Send only USDT or USDC over the {net} network. Tokens sent over another network are lost. The same address receives both.',
    'Envía solo USDT o USDC por la red {net}. Los tokens enviados por otra red se pierden. La misma dirección recibe ambos.',
  ),
  'ss.btcReceive': (
    'Fatura Lightning (cai na hora) ou endereço on-chain',
    'Lightning invoice (arrives instantly) or on-chain address',
    'Factura Lightning (llega al instante) o dirección on-chain',
  ),
  'ss.btcSend': (
    'Fatura ou voucher Lightning, ou endereço on-chain',
    'Lightning invoice or voucher, or on-chain address',
    'Factura o voucher Lightning, o dirección on-chain',
  ),
  'ss.stableOn': (
    'USDT ou USDC na {net}',
    'USDT or USDC on {net}',
    'USDT o USDC en {net}',
  ),
  'ss.dollarAddress': (
    'Endereço para receber dólar digital',
    'Address to receive digital dollars',
    'Dirección para recibir dólar digital',
  ),
  'ss.gasPol': (
    'Você paga o gás em POL',
    'You pay the gas in POL',
    'Pagas el gas en POL',
  ),
  'ss.feeSol': (
    'Você paga a taxa em SOL',
    'You pay the fee in SOL',
    'Pagas la comisión en SOL',
  ),
  'pend.confirmed': (
    'Envio de {amount}: confirmado',
    'Send of {amount}: confirmed',
    'Envío de {amount}: confirmado',
  ),
  'pend.reverted': (
    'Envio de {amount}: falhou na rede, os tokens não saíram',
    'Send of {amount}: failed on the network, the tokens did not leave',
    'Envío de {amount}: falló en la red, los tokens no salieron',
  ),
  'pend.notSent': (
    'Envio de {amount}: não chegou a entrar na rede, nada foi cobrado',
    'Send of {amount}: never entered the network, nothing was charged',
    'Envío de {amount}: no llegó a entrar en la red, no se cobró nada',
  ),
  'pend.pending': (
    'Envio de {amount}: ainda sem confirmação',
    'Send of {amount}: not confirmed yet',
    'Envío de {amount}: aún sin confirmación',
  ),
  'pend.cancelled': (
    'Envio de {amount} cancelado: não entrou na rede. O cancelamento custou um pouco de POL',
    'Send of {amount} cancelled: it did not enter the network. The cancellation cost a little POL',
    'Envío de {amount} cancelado: no entró en la red. La cancelación costó un poco de POL',
  ),
  'pend.cancelTooLateOk': (
    'Não deu para cancelar: o envio de {amount} já tinha entrado e foi confirmado',
    'Could not cancel: the send of {amount} had already gone in and was confirmed',
    'No se pudo cancelar: el envío de {amount} ya había entrado y fue confirmado',
  ),
  'pend.cancelTooLateFail': (
    'Não deu para cancelar: o envio de {amount} já tinha sido executado e falhou na rede, os tokens não saíram',
    'Could not cancel: the send of {amount} had already been executed and failed on the network, the tokens did not leave',
    'No se pudo cancelar: el envío de {amount} ya se había ejecutado y falló en la red, los tokens no salieron',
  ),
  'pend.discarded': (
    'Envio descartado do registro',
    'Send discarded from the record',
    'Envío descartado del registro',
  ),
  'pend.cancelling': (
    'Cancelando... pode levar até um minuto e meio. Não feche o aplicativo',
    'Cancelling... it can take up to a minute and a half. Do not close the app',
    'Cancelando... puede tardar hasta un minuto y medio. No cierres la aplicación',
  ),
  'pend.cancelUnconfirmed': (
    'Cancelamento enviado, mas a rede ainda não o confirmou. Confira de novo em instantes.',
    'Cancellation sent, but the network has not confirmed it yet. Check again in a moment.',
    'Cancelación enviada, pero la red aún no la confirmó. Revisa de nuevo en unos instantes.',
  ),
  'pend.cannotTell': (
    'Ainda não dá para saber. Confira no explorador.',
    'It cannot be known yet. Check on the explorer.',
    'Aún no se puede saber. Revisa en el explorador.',
  ),
  'pend.title': (
    'Envio em aberto',
    'Open send',
    'Envío abierto',
  ),
  'pend.body': (
    'Esse envio foi assinado e pode ter entrado na rede, mas ainda não há confirmação. Não envie de novo antes de conferir: pode pagar duas vezes.',
    'This send was signed and may have entered the network, but there is no confirmation yet. Do not send again before checking: you may pay twice.',
    'Este envío fue firmado y puede haber entrado en la red, pero aún no hay confirmación. No envíes de nuevo antes de revisar: podrías pagar dos veces.',
  ),
  'pend.network': (
    'Rede',
    'Network',
    'Red',
  ),
  'pend.transaction': (
    'Transação',
    'Transaction',
    'Transacción',
  ),
  'pend.checking': (
    'Conferindo...',
    'Checking...',
    'Revisando...',
  ),
  'pend.checkNow': (
    'Conferir agora',
    'Check now',
    'Revisar ahora',
  ),
  'pend.staleNote': (
    'Esse envio tem mais de 1 hora e a rede pública já não guarda o histórico dele, então o app não consegue provar que ele não entrou. Antes de descartar, abra o link no {explorer} (histórico completo): se a transação aparece lá, o envio FOI feito.',
    'This send is more than 1 hour old and the public network no longer keeps its history, so the app cannot prove it did not go in. Before discarding, open the link on {explorer} (full history): if the transaction shows up there, the send WAS made.',
    'Este envío tiene más de 1 hora y la red pública ya no guarda su historial, así que la app no puede probar que no entró. Antes de descartar, abre el enlace en {explorer} (historial completo): si la transacción aparece allí, el envío SÍ se hizo.',
  ),
  'pend.discardAgain': (
    'Toque de novo: conferi no {explorer} e ele NÃO aparece',
    'Tap again: I checked on {explorer} and it does NOT appear',
    'Toca de nuevo: revisé en {explorer} y NO aparece',
  ),
  'pend.discardCheck': (
    'Descartar (conferi no {explorer})',
    'Discard (I checked on {explorer})',
    'Descartar (revisé en {explorer})',
  ),
  'pend.cancelNote': (
    'Se ele não aparece no explorador e você quer liberar novos envios, dá para cancelar: o app manda uma transação sua, para você mesmo e sem valor, no lugar dele. Se o envio original já tiver entrado, ele é confirmado normalmente. Custa um pouco de POL.',
    'If it does not appear on the explorer and you want to free up new sends, you can cancel: the app sends a transaction of yours, to yourself and with no value, in its place. If the original send has already gone in, it is confirmed as usual. It costs a little POL.',
    'Si no aparece en el explorador y quieres liberar nuevos envíos, puedes cancelar: la app envía una transacción tuya, a ti mismo y sin valor, en su lugar. Si el envío original ya entró, se confirma normalmente. Cuesta un poco de POL.',
  ),
  'pend.cancelAgain': (
    'Toque de novo para cancelar o envio',
    'Tap again to cancel the send',
    'Toca de nuevo para cancelar el envío',
  ),
  'pend.cancelSend': (
    'Cancelar envio',
    'Cancel send',
    'Cancelar envío',
  ),
  'pend.solanaNote': (
    'A Solana resolve esse envio sozinha: se ele não tiver entrado até o fim da validade (cerca de 1 a 2 minutos), o app o marca como não enviado.',
    'Solana settles this send by itself: if it has not gone in by the end of its validity (about 1 to 2 minutes), the app marks it as not sent.',
    'Solana resuelve este envío sola: si no ha entrado al terminar su validez (unos 1 a 2 minutos), la app lo marca como no enviado.',
  ),
  'lim.enter': (
    'Digite um valor em sats',
    'Enter an amount in sats',
    'Escribe un monto en sats',
  ),
  'lim.min': (
    'Mínimo de {n} sats por pagamento',
    'Minimum of {n} sats per payment',
    'Mínimo de {n} sats por pago',
  ),
  'send.discardRecord': (
    'Descartar o registro',
    'Discard the record',
    'Descartar el registro',
  ),
  'onc.payAndClaim': (
    'Pagar e resgatar',
    'Pay and claim',
    'Pagar y canjear',
  ),
};
