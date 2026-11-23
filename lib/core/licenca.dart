import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

import 'licenca_config.dart';

/// Códigos de ativação por aparelho, com prazo de validade, conferidos sem
/// internet.
///
/// Cada instalação gera um **número de instalação** aleatório (8 letras/números).
/// O vendedor do app gera, na página geradora, um **código de ativação** de 16
/// caracteres a partir de: id do app + número de instalação + validade. O código
/// leva a validade (dias desde 01/01/2025) e uma assinatura HMAC‑SHA256 com a
/// chave secreta do app; por isso não funciona em outro aparelho, em outro app,
/// nem com a validade alterada.
class CodigoLicenca {
  CodigoLicenca._();

  static const alfabeto = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static final epoch = DateTime.utc(2025, 1, 1);

  /// Valor de dias que significa "sem prazo".
  static const permanente = 65535;

  /// Mantém só os caracteres válidos, em maiúsculas.
  static String normalizar(String s) =>
      s.toUpperCase().split('').where((c) => alfabeto.contains(c)).join();

  /// Tira o código de um texto colado (aceita a mensagem inteira do WhatsApp,
  /// espaços, quebras de linha e letras minúsculas).
  static String extrairCodigo(String texto) {
    final t = texto.toUpperCase();
    final grupos = RegExp(r'([A-HJ-NP-Z2-9]{4})[\s\-–—_.]+([A-HJ-NP-Z2-9]{4})[\s\-–—_.]+([A-HJ-NP-Z2-9]{4})[\s\-–—_.]+([A-HJ-NP-Z2-9]{4})')
        .firstMatch(t);
    if (grupos != null) return '${grupos[1]}${grupos[2]}${grupos[3]}${grupos[4]}';
    final soltos = RegExp(r'(?<![A-Z0-9])[A-HJ-NP-Z2-9]{16}(?![A-Z0-9])').firstMatch(t);
    if (soltos != null) return soltos[0]!;
    return normalizar(t);
  }

  /// Formata em grupos de 4: ABCD-EFGH-…
  static String formatar(String s) {
    final n = normalizar(s);
    final partes = <String>[];
    for (var i = 0; i < n.length; i += 4) {
      partes.add(n.substring(i, min(i + 4, n.length)));
    }
    return partes.join('-');
  }

  static int diasDe(DateTime data) =>
      DateTime.utc(data.year, data.month, data.day).difference(epoch).inDays;

  static DateTime dataDe(int dias) => epoch.add(Duration(days: dias));

  static String _base32(List<int> bytes) {
    var bits = 0, valor = 0;
    final out = StringBuffer();
    for (final b in bytes) {
      valor = (valor << 8) | b;
      bits += 8;
      while (bits >= 5) {
        out.write(alfabeto[(valor >> (bits - 5)) & 31]);
        bits -= 5;
      }
    }
    if (bits > 0) out.write(alfabeto[(valor << (5 - bits)) & 31]);
    return out.toString();
  }

  static List<int>? _deBase32(String s) {
    var bits = 0, valor = 0;
    final out = <int>[];
    for (final c in s.split('')) {
      final i = alfabeto.indexOf(c);
      if (i < 0) return null;
      valor = ((valor << 5) | i) & 0xFFFF;
      bits += 5;
      if (bits >= 8) {
        out.add((valor >> (bits - 8)) & 255);
        bits -= 8;
      }
    }
    return out;
  }

  static Future<List<int>> _assinatura(String appId, List<int> chave, String instalacao, int dias) async {
    final msg = utf8.encode('$appId|${normalizar(instalacao)}|$dias');
    final mac = await Hmac.sha256().calculateMac(msg, secretKey: SecretKey(chave));
    return mac.bytes.sublist(0, 8);
  }

  /// Gera o código (mesmo algoritmo da página geradora).
  static Future<String> gerar({
    required String appId,
    required List<int> chave,
    required String instalacao,
    required int dias,
  }) async {
    if (dias < 0 || dias > permanente) throw ArgumentError('Validade inválida');
    final sig = await _assinatura(appId, chave, instalacao, dias);
    return formatar(_base32([dias >> 8, dias & 255, ...sig]));
  }

  /// Confere o código. Devolve a data de validade (último dia válido) ou null
  /// se o código não for deste app/aparelho.
  static Future<DateTime?> validar({
    required String appId,
    required List<int> chave,
    required String instalacao,
    required String codigo,
  }) async {
    final n = extrairCodigo(codigo);
    if (n.length != 16) return null;
    final bytes = _deBase32(n);
    if (bytes == null || bytes.length < 10) return null;
    final dias = (bytes[0] << 8) | bytes[1];
    final esperado = await _assinatura(appId, chave, instalacao, dias);
    var dif = 0;
    for (var i = 0; i < 8; i++) {
      dif |= esperado[i] ^ bytes[2 + i];
    }
    if (dif != 0) return null;
    return dias == permanente ? DateTime.utc(9999, 12, 31) : dataDe(dias);
  }
}

/// Número de instalação como é mostrado ao cliente: prefixo do app + 8
/// caracteres (ex.: COC-ABCD-EFGH). O prefixo permite à página geradora
/// escolher o app certo sozinha; a assinatura usa só os 8 caracteres.
String numeroInstalacao(String instalacao) => '$appLicencaId-${CodigoLicenca.formatar(instalacao)}';

class StatusLicenca {
  StatusLicenca({required this.instalacao, this.validade, this.relogioAtrasado = false});
  final String instalacao;
  /// Último dia válido (null = nunca ativado).
  final DateTime? validade;
  final bool relogioAtrasado;

  bool get permanente => validade != null && validade!.year >= 9999;
  int get diasRestantes {
    if (validade == null) return -1;
    final h = DateTime.now();
    return validade!.difference(DateTime.utc(h.year, h.month, h.day)).inDays;
  }

  bool get valida => validade != null && !relogioAtrasado && diasRestantes >= 0;
  bool get vencendo => valida && !permanente && diasRestantes <= 7;
}

/// Licença guardada no aparelho (fora do banco: não vai no backup nem é
/// copiada para outro celular).
class LicencaLocal {
  LicencaLocal._();

  static Future<File> _arquivo() async {
    final pasta = await getApplicationSupportDirectory();
    return File('${pasta.path}/licenca_v1.json');
  }

  static Future<Map<String, dynamic>> _ler() async {
    final f = await _arquivo();
    if (await f.exists()) {
      try {
        return Map<String, dynamic>.from(jsonDecode(await f.readAsString()) as Map);
      } catch (_) {}
    }
    return {};
  }

  static Future<void> _gravar(Map<String, dynamic> dados) async {
    final f = await _arquivo();
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(dados), flush: true);
  }

  static String _novaInstalacao() {
    final r = Random.secure();
    return List.generate(8, (_) => CodigoLicenca.alfabeto[r.nextInt(32)]).join();
  }

  static String _hoje() {
    final h = DateTime.now();
    return '${h.year.toString().padLeft(4, '0')}-${h.month.toString().padLeft(2, '0')}-${h.day.toString().padLeft(2, '0')}';
  }

  /// Lê (e cria, na primeira vez) o número de instalação e confere a licença.
  static Future<StatusLicenca> verificar() async {
    final d = await _ler();
    var instalacao = d['instalacao'] as String?;
    if (instalacao == null || CodigoLicenca.normalizar(instalacao).length != 8) {
      instalacao = _novaInstalacao();
      d['instalacao'] = instalacao;
      await _gravar(d);
    }
    final codigo = d['codigo'] as String?;
    DateTime? validade;
    if (codigo != null) {
      validade = await CodigoLicenca.validar(
          appId: appLicencaId, chave: chaveLicenca, instalacao: instalacao, codigo: codigo);
    }
    // Proteção simples contra voltar a data do celular para estender o prazo.
    final hoje = _hoje();
    final ultima = d['ultima_data'] as String?;
    final atrasado = ultima != null && DateTime.parse(hoje).isBefore(DateTime.parse(ultima).subtract(const Duration(days: 1)));
    if (!atrasado && (ultima == null || hoje.compareTo(ultima) > 0)) {
      d['ultima_data'] = hoje;
      await _gravar(d);
    }
    return StatusLicenca(instalacao: instalacao, validade: validade, relogioAtrasado: atrasado);
  }

  /// Ativa/renova com o código recebido. Lança [FormatException] se inválido
  /// ou vencido.
  static Future<StatusLicenca> ativar(String codigo) async {
    final st = await verificar();
    final validade = await CodigoLicenca.validar(
        appId: appLicencaId, chave: chaveLicenca, instalacao: st.instalacao, codigo: codigo);
    if (validade == null) {
      final n = CodigoLicenca.extrairCodigo(codigo);
      if (n.length != 16) {
        throw FormatException('O código deve ter 16 letras e números (ex.: ABCD-EFGH-JKLM-NPQR). '
            'Foram reconhecidos ${n.length}. Confira se copiou o código completo.');
      }
      throw FormatException('Este código não é deste aparelho/aplicativo. Ele precisa ser gerado para o app '
          '"$appLicencaNome" e para o número de instalação ${numeroInstalacao(st.instalacao)}.');
    }
    final novo = StatusLicenca(instalacao: st.instalacao, validade: validade, relogioAtrasado: st.relogioAtrasado);
    if (novo.diasRestantes < 0) throw const FormatException('Este código já está vencido. Peça um código novo.');
    final d = await _ler();
    d['codigo'] = CodigoLicenca.formatar(CodigoLicenca.extrairCodigo(codigo));
    await _gravar(d);
    return novo;
  }
}
