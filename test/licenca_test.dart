// Códigos de ativação: os vetores abaixo foram calculados por uma
// implementação independente (Python) e pela página geradora (JavaScript).
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_producao_coco/core/licenca.dart';
import 'package:gestor_producao_coco/core/licenca_config.dart';

void main() {
  final chave = List<int>.generate(32, (i) => i);

  test('gera os mesmos códigos que a página geradora', () async {
    expect(await CodigoLicenca.gerar(appId: 'TST', chave: chave, instalacao: 'ABCD-EFGH', dias: 700), 'AL8R-DN8L-Q8AN-8LNZ');
    expect(await CodigoLicenca.gerar(appId: 'TST', chave: chave, instalacao: 'ZZ23-4567', dias: 65535), '999X-ATRB-4W8L-CMFV');
    expect(await CodigoLicenca.gerar(appId: 'TST', chave: chave, instalacao: 'K7Q2M9XA', dias: 0), 'AAAA-WK25-HMT5-RZ94');
  });

  test('código vale só para o aparelho, o app e a validade certos', () async {
    final validade = DateTime.now().add(const Duration(days: 30));
    final dias = CodigoLicenca.diasDe(validade);
    final codigo = await CodigoLicenca.gerar(appId: appLicencaId, chave: chaveLicenca, instalacao: 'ABCD-EFGH', dias: dias);
    final ok = await CodigoLicenca.validar(appId: appLicencaId, chave: chaveLicenca, instalacao: 'abcd efgh', codigo: codigo.toLowerCase());
    expect(ok, CodigoLicenca.dataDe(dias));
    expect(await CodigoLicenca.validar(appId: appLicencaId, chave: chaveLicenca, instalacao: 'ABCD-EFGJ', codigo: codigo), isNull);
    expect(await CodigoLicenca.validar(appId: 'XXX', chave: chaveLicenca, instalacao: 'ABCD-EFGH', codigo: codigo), isNull);
    // Trocar um caractere (ex.: tentar alterar a validade) invalida o código.
    final n = CodigoLicenca.normalizar(codigo);
    final adulterado = '${n[0] == 'A' ? 'B' : 'A'}${n.substring(1)}';
    expect(await CodigoLicenca.validar(appId: appLicencaId, chave: chaveLicenca, instalacao: 'ABCD-EFGH', codigo: adulterado), isNull);
    expect(await CodigoLicenca.validar(appId: appLicencaId, chave: chaveLicenca, instalacao: 'ABCD-EFGH', codigo: 'curto'), isNull);
    final perm = await CodigoLicenca.gerar(
        appId: appLicencaId, chave: chaveLicenca, instalacao: 'ABCD-EFGH', dias: CodigoLicenca.permanente);
    expect((await CodigoLicenca.validar(appId: appLicencaId, chave: chaveLicenca, instalacao: 'ABCD-EFGH', codigo: perm))!.year, 9999);
  });

  test('situação da licença: vencida, vencendo e válida', () {
    final hoje = DateTime.now();
    final h = DateTime.utc(hoje.year, hoje.month, hoje.day);
    expect(StatusLicenca(instalacao: 'X', validade: h.subtract(const Duration(days: 1))).valida, isFalse);
    expect(StatusLicenca(instalacao: 'X', validade: h).valida, isTrue); // último dia ainda vale
    expect(StatusLicenca(instalacao: 'X', validade: h.add(const Duration(days: 5))).vencendo, isTrue);
    expect(StatusLicenca(instalacao: 'X', validade: h.add(const Duration(days: 60))).vencendo, isFalse);
    expect(StatusLicenca(instalacao: 'X').valida, isFalse);
    expect(StatusLicenca(instalacao: 'X', validade: h.add(const Duration(days: 60)), relogioAtrasado: true).valida, isFalse);
  });
}
