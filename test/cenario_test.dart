// Testes do cenário de validação (coqueiral) sobre o banco
// SQLite real, usando sqflite_common_ffi. Rode com: flutter test
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_producao_coco/core/format.dart';
import 'package:gestor_producao_coco/data/db.dart';
import 'package:gestor_producao_coco/services/backup_service.dart';
import 'package:gestor_producao_coco/services/base.dart';
import 'package:gestor_producao_coco/services/cadastro_service.dart';
import 'package:gestor_producao_coco/services/campo_service.dart';
import 'package:gestor_producao_coco/services/compra_service.dart';
import 'package:gestor_producao_coco/services/demo_service.dart';
import 'package:gestor_producao_coco/services/dre_service.dart';
import 'package:gestor_producao_coco/services/estoque_service.dart';
import 'package:gestor_producao_coco/services/financeiro_service.dart';
import 'package:gestor_producao_coco/services/pdf_service.dart';
import 'package:gestor_producao_coco/services/pedido_service.dart';
import 'package:gestor_producao_coco/services/relatorio_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tmp;
  late AppDb app;
  late Database db;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('gpc');
    app = await AppDb.abrir(caminho: '${tmp.path}/teste.db', factory: databaseFactoryFfi);
    db = app.db;
  });

  tearDown(() async {
    await app.fechar();
    await tmp.delete(recursive: true);
  });

  test('dados de exemplo incluem talhões, insumos, manejos e colheitas', () async {
    await DemoService(db).carregar();

    final itens = await db.query('itens');
    expect(itens.where((item) => item['tipo'] == 'insumo'), hasLength(4));
    expect(itens.where((item) => item['tipo'] == 'embalagem'), hasLength(1));
    expect(itens.where((item) => item['tipo'] == 'acabado'), hasLength(2));
    expect(await db.query('talhoes'), hasLength(2));
    final manejos = await db.query('manejos');
    expect(manejos, hasLength(3));
    expect(manejos.every((m) => m['colheita_id'] != null), isTrue); // todos apropriados
    final colheitas = await db.query('colheitas');
    expect(colheitas.where((c) => c['status'] == 'concluida'), hasLength(2));
    expect(colheitas.where((c) => c['status'] == 'planejada'), hasLength(1));
    expect(await db.query('manejo_insumos'), isNotEmpty);
    expect(await db.query('pedidos'), hasLength(2));
  });

  test('preço sugerido e bloqueio de percentuais >= 100%', () {
    final p = CampoService.precoSugerido(custoUnitario: 0.6, pctTaxas: 5, pctImpostos: 5, pctFixas: 10, pctMargem: 20);
    expect(p.preco, 1.0); // 0,60 / (1 - 0,40)
    final e = CampoService.precoSugerido(custoUnitario: 30, pctTaxas: 50, pctImpostos: 50, pctFixas: 0, pctMargem: 0);
    expect(e.preco, isNull);
    expect(e.erro, isNotNull);
  });

  test('cenário completo: compra, manejo, colheita, pedido, entrega, pagamento e relatórios', () async {
    final cad = CadastroService(db);
    final campo = CampoService(db);
    final hoje = hojeIso();
    final daqui30 = isoData(DateTime.now().add(const Duration(days: 30)));

    // Saldo inicial na conta bancária para pagar o fornecedor depois.
    await db.update('contas_financeiras', {'saldo_inicial': 200, 'data_saldo_inicial': '2000-01-01'}, where: 'id = 2');

    final adubo = await cad.salvarItem({
      'tipo': 'insumo', 'nome': 'Adubo NPK', 'unidade_compra': 'saco 50 kg', 'unidade_consumo': 'kg',
      'fator_conversao': 50, 'estoque_minimo': 10,
    });
    final saco = await cad.salvarItem({
      'tipo': 'embalagem', 'nome': 'Saco de ráfia', 'unidade_compra': 'un', 'unidade_consumo': 'un', 'fator_conversao': 1,
    });
    final fornecedor = await db.insert('fornecedores', {'nome': 'Agropecuária', 'criado_em': agoraIso()});

    // 1. Compra de adubo e sacaria a prazo.
    final compras = CompraService(db);
    final cid = await compras.salvar(
      fornecedorId: fornecedor, data: hoje, condicao: 'prazo', parcelas: 1, primeiroVencimento: daqui30, contaId: 2,
      itens: [
        ItemCompra(itemId: adubo, quantidade: 1, custoTotal: 100, lote: 'A1', validade: isoData(DateTime.now().add(const Duration(days: 365)))),
        ItemCompra(itemId: saco, quantidade: 10, custoTotal: 20),
      ],
    );
    await compras.confirmar(cid);
    await expectLater(compras.confirmar(cid), throwsA(isA<RegraException>())); // duplicada bloqueada
    final est = EstoqueService(db);
    expect((await est.saldo(adubo, 0)).fisico, 50);
    final fin = FinanceiroService(db);
    final aPagar = await fin.titulosAbertos(tipo: 'pagar');
    expect(aPagar.length, 1);
    expect(Base.d(aPagar.first['aberto']), 120);
    expect(await fin.saldo(), 200); // compra a prazo não sai do caixa

    // 2. Talhão e manejo (adubação): baixa 25 kg (R\$ 2,00/kg) + mão de obra.
    final talhao = await campo.salvarTalhao({'nome': 'Talhão 1', 'area_ha': 2, 'qtd_plantas': 400, 'variedade': 'Anão verde'});
    final manejo = await campo.registrarManejo(
      talhaoId: talhao, data: hoje, operacao: 'adubacao',
      insumos: [InsumoUsado(itemId: adubo, quantidade: 25)], maoObra: 30,
    );
    expect((await est.saldo(adubo, 0)).fisico, 25);
    expect(await campo.custoPendente(talhao), 80.0); // 25 × 2,00 + 30
    await expectLater(
      campo.registrarManejo(talhaoId: talhao, data: hoje, operacao: 'adubacao', insumos: [InsumoUsado(itemId: adubo, quantidade: 999)]),
      throwsA(isA<RegraException>()),
    ); // saldo insuficiente
    expect((await est.saldo(adubo, 0)).fisico, 25);

    // Manejo cancelado devolve o insumo ao estoque.
    final mCancel = await campo.registrarManejo(
        talhaoId: talhao, data: hoje, operacao: 'adubacao', insumos: [InsumoUsado(itemId: adubo, quantidade: 5)]);
    expect((await est.saldo(adubo, 0)).fisico, 20);
    await campo.cancelarManejo(mCancel, 'Lançado em duplicidade');
    expect((await est.saldo(adubo, 0)).fisico, 25);
    expect(await campo.custoPendente(talhao), 80.0);

    // 3. Colheita de coco verde: apropria o manejo e entra no estoque.
    final coco = await cad.salvarItem(
        {'tipo': 'acabado', 'nome': 'Coco verde', 'unidade_venda': 'un', 'variavel_pct_cpv': 100, 'validade_dias': 12});
    final vCoco = (await cad.variacoes(coco)).first['id'] as int;
    await db.update('variacoes', {'preco_venda': 1.5}, where: 'id = ?', whereArgs: [vCoco]);
    final colheita = await campo.planejarColheita(talhaoId: talhao, itemId: coco, variacaoId: vCoco, data: hoje, qtdPrevista: 210);
    await expectLater(
      campo.concluirColheita(colheitaId: colheita, qtdAprovada: 200, refugo: 10, data: hoje),
      throwsA(isA<RegraException>()),
    ); // refugo sem motivo
    final loteId = await campo.concluirColheita(
      colheitaId: colheita,
      qtdAprovada: 200,
      refugo: 10,
      motivoPerda: 'Rachados',
      insumos: [InsumoUsado(itemId: saco, quantidade: 5)],
      maoObra: 40,
      data: hoje,
    );
    await expectLater(
        campo.concluirColheita(colheitaId: colheita, qtdAprovada: 200, data: hoje), throwsA(isA<RegraException>()));
    final lote = (await db.query('lotes', where: 'id = ?', whereArgs: [loteId])).first;
    expect(Base.d(lote['saldo']), 200);
    expect(Base.d(lote['custo_unitario']), closeTo(0.65, 0.0001)); // (80 + 10 + 40) ÷ 200
    expect(lote['validade'], isoData(DateTime.now().add(const Duration(days: 12))));
    expect(lote['codigo'], isNotEmpty);
    expect((await est.saldo(saco, 0)).fisico, 5);
    expect(await campo.custoPendente(talhao), 0);
    final m = (await db.query('manejos', where: 'id = ?', whereArgs: [manejo])).first;
    expect(m['colheita_id'], colheita);
    await expectLater(campo.cancelarManejo(manejo, 'x'), throwsA(isA<RegraException>())); // já apropriado
    final aprop = await db.query('lancamentos_resultado', where: 'chave = ?', whereArgs: ['colheita:$colheita:apropriacao']);
    expect(Base.d(aprop.single['valor']), -70.0); // mão de obra do manejo (30) + da colheita (40)

    // 4. Encomenda com sinal.
    final cliente = await db.insert('clientes', {'nome': 'Cliente', 'criado_em': agoraIso()});
    final ped = PedidoService(db);
    final pid = await ped.salvar(
      tipo: 'encomenda', clienteId: cliente, canal: 'Distribuidora', dataPedido: hoje, dataEntrega: hoje,
      itens: [ItemPedido(itemId: coco, variacaoId: vCoco, quantidade: 100, precoUnitario: 1.5, unidadeVenda: 'un')],
    );
    await ped.confirmar(pid);
    expect((await est.saldo(coco, vCoco)).reservado, 100);
    expect((await est.saldo(coco, vCoco)).disponivel, 100);
    await ped.registrarPagamento(pedidoId: pid, meioId: 1, valor: 50, data: hoje); // dinheiro → conta 1
    expect(await fin.saldoConta(1), 50);

    // 5. Entrega: baixa, abatimento do sinal, saldo a receber e CPV.
    await ped.entregar(pedidoId: pid, data: hoje, vencimentoSaldo: daqui30);
    await expectLater(ped.entregar(pedidoId: pid, data: hoje), throwsA(isA<RegraException>()));
    expect((await est.saldo(coco, vCoco)).fisico, 100);
    expect((await est.saldo(coco, vCoco)).reservado, 0);
    final aReceber = await fin.titulosAbertos(tipo: 'receber');
    expect(aReceber.length, 1);
    expect(Base.d(aReceber.first['aberto']), 100);
    final ini = isoData(inicioMes(DateTime.now()));
    final fim = isoData(fimMes(DateTime.now()));
    final dre = await DreService(db).calcular(ini, fim);
    expect(dre.receitaBruta, 150);
    expect(dre.cpv, 65);
    expect(dre.lucroBruto, 85);

    // 6. Pagamento do fornecedor.
    final titulo = aPagar.first;
    await fin.baixarTitulo(tituloId: titulo['id'] as int, data: hoje, contaId: 2, principal: 120);
    final movPag = await db.query('movimentos_financeiros', where: 'titulo_id = ?', whereArgs: [titulo['id']]);
    expect(movPag.single['conta_id'], 2);
    expect(movPag.single['data'], hoje);
    expect(movPag.single['tipo'], 'saida');
    expect(await fin.saldoConta(2), 80);

    // Transferência: efeito zero no consolidado.
    final antes = await fin.saldo();
    await fin.transferir(origemId: 1, destinoId: 2, valor: 10, data: hoje);
    expect(await fin.saldo(), antes);

    // 7. Relatórios: totais batem com o financeiro e com a DRE.
    final fr = await fin.fluxoRealizado(inicio: ini, fim: fim);
    expect(fr.saldoFinal, await fin.saldo(ateData: fim));
    expect(r2(fr.saldoInicial + fr.entradas - fr.saidas), fr.saldoFinal);
    final vc = await RelatorioService(db).vendasCustos(FiltroVendas(inicio: ini, fim: fim));
    expect(vc.receitaLiquida, dre.receitaLiquida);
    expect(vc.cpv, dre.cpv);
    expect(vc.lucroBruto, dre.lucroBruto);
    expect(vc.vendas, 1);
    expect(vc.custosProducao['Total colhido'], 130.0);
    expect(vc.ordens, hasLength(1));
    final fp = await fin.fluxoProjetado(dataRef: hoje, ate: daqui30);
    expect(fp.aReceber, 100);

    // PDFs são gerados (bytes válidos) sem internet.
    final cab = CabecalhoPdf(negocio: 'Teste', titulo: 'T', periodo: 'x', filtros: const []);
    final pdf1 = await PdfService.fluxoCaixa(cab: cab, realizado: fr, projetado: fp);
    final pdf2 = await PdfService.vendasCustos(cab: cab, v: vc);
    expect(String.fromCharCodes(pdf1.sublist(0, 4)), '%PDF');
    expect(String.fromCharCodes(pdf2.sublist(0, 4)), '%PDF');

    // 9. Backup protegido por senha: senha errada é recusada; a certa preserva os dados.
    final bytes = await BackupService.gerar(app: app, senha: 'segredo');
    await expectLater(BackupService.abrir(bytes, 'errada'), throwsA(isA<RegraException>()));
    final arquivos = await BackupService.abrir(bytes, 'segredo');
    final outro = File('${tmp.path}/restaurado.db');
    await outro.writeAsBytes(arquivos['banco.db']!);
    final app2 = await AppDb.abrir(caminho: outro.path, factory: databaseFactoryFfi);
    final fin2 = FinanceiroService(app2.db);
    expect(await fin2.saldo(), await FinanceiroService(db).saldo());
    expect((await EstoqueService(app2.db).saldo(adubo, 0)).fisico, 25);
    await app2.fechar();
    AppDb.definirInstancia(app);
  });

  test('cancelamento libera reserva e devolve sinal; lote vencido é bloqueado', () async {
    final cad = CadastroService(db);
    final hoje = hojeIso();
    final doce = await cad.salvarItem({'tipo': 'acabado', 'nome': 'Coco seco', 'unidade_venda': 'cento'});
    final v = (await cad.variacoes(doce)).first['id'] as int;
    final est = EstoqueService(db);
    await db.transaction((txn) async {
      await est.entradaProduzido(txn,
          itemId: doce, variacaoId: v, quantidade: 2, custoUnitario: 40, codigoLote: 'A', fabricacao: hoje,
          validade: isoData(DateTime.now().add(const Duration(days: 2))));
      await est.entradaProduzido(txn,
          itemId: doce, variacaoId: v, quantidade: 5, custoUnitario: 40, codigoLote: 'VENC', fabricacao: '2020-01-01',
          validade: '2020-01-05');
    });
    final s = await est.saldo(doce, v);
    expect(s.fisico, 7);
    expect(s.vencido, 5);
    expect(s.disponivel, 2);

    final ped = PedidoService(db);
    final pid = await ped.salvar(
        tipo: 'encomenda', dataPedido: hoje, itens: [ItemPedido(itemId: doce, variacaoId: v, quantidade: 2, precoUnitario: 120)]);
    await ped.confirmar(pid);
    expect((await est.saldo(doce, v)).disponivel, 0);
    await ped.registrarPagamento(pedidoId: pid, meioId: 1, valor: 100, data: hoje);
    await ped.cancelar(pedidoId: pid, motivo: 'Comprador desistiu', valorDevolvido: 100, contaDevolucaoId: 1);
    expect((await est.saldo(doce, v)).disponivel, 2);
    expect(await FinanceiroService(db).saldoConta(1), 0);

    // Venda de 3 unidades falha: só 2 válidas (lote vencido bloqueado).
    await expectLater(
      ped.vendaBalcao(data: hoje, itens: [ItemPedido(itemId: doce, variacaoId: v, quantidade: 3, precoUnitario: 120)], pagamentos: const []),
      throwsA(isA<RegraException>()),
    );
    expect((await est.saldo(doce, v)).fisico, 7);
  });

  test('cartão: taxa registrada uma vez e conciliação do depósito', () async {
    final cad = CadastroService(db);
    final hoje = hojeIso();
    final bolo = await cad.salvarItem({'tipo': 'acabado', 'nome': 'Coco verde', 'unidade_venda': 'un'});
    final v = (await cad.variacoes(bolo)).first['id'] as int;
    await db.transaction((txn) async {
      await EstoqueService(db).entradaProduzido(txn,
          itemId: bolo, variacaoId: v, quantidade: 1, custoUnitario: 30, codigoLote: 'T', fabricacao: hoje);
    });
    // Cartão de crédito: 3,5%, 30 dias, conta 2.
    await PedidoService(db).vendaBalcao(
        data: hoje,
        itens: [ItemPedido(itemId: bolo, variacaoId: v, quantidade: 1, precoUnitario: 100)],
        pagamentos: [PagamentoInfo(meioId: 4, valor: 100)]);
    final fin = FinanceiroService(db);
    final rec = await fin.titulosAbertos(tipo: 'receber');
    expect(rec.single['ref_tipo'], 'cartao');
    expect(Base.d(rec.single['aberto']), 96.5);
    await fin.conciliarCartao(tituloId: rec.single['id'] as int, data: hoje, contaId: 2, valorDepositado: 96.0);
    expect(await fin.saldoConta(2), 96.0);
    final ini = isoData(inicioMes(DateTime.now()));
    final fim = isoData(fimMes(DateTime.now()));
    final dre = await DreService(db).calcular(ini, fim);
    expect(dre.despesasVariaveis, 4.0); // 3,50 previsto + 0,50 de ajuste
    expect(dre.receitaBruta, 100);
    expect(dre.cpv, 30);
  });
}
