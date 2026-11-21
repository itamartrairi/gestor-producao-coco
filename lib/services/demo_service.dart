import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import 'cadastro_service.dart';
import 'campo_service.dart';
import 'compra_service.dart';
import 'financeiro_service.dart';
import 'pedido_service.dart';

/// Dados demonstrativos de um coqueiral (carregados na primeira configuração
/// ou em Configurações > Carregar dados de exemplo).
class DemoService {
  DemoService(this.db);
  final Database db;

  Future<int> _categoria(String nome) async =>
      (await db.query('categorias', where: 'nome = ?', whereArgs: [nome])).first['id'] as int;

  Future<int> _catFin(String codigo) async =>
      (await db.query('categorias_financeiras', where: 'codigo = ?', whereArgs: [codigo])).first['id'] as int;

  Future<void> carregar() async {
    final cad = CadastroService(db);
    final campo = CampoService(db);
    final hoje = DateTime.now();
    final h = isoData(hoje);
    final fin = FinanceiroService(db);

    // Aporte inicial no caixa e no banco.
    final catSocios = await _catFin('SOCIOS');
    await db.transaction((txn) async {
      await fin.criarMovimento(txn,
          data: h, contaId: 1, tipo: 'entrada', valor: 500, categoriaId: catSocios, descricao: 'Aporte inicial (demo)');
      await fin.criarMovimento(txn,
          data: h, contaId: 2, tipo: 'entrada', valor: 5000, categoriaId: catSocios, descricao: 'Aporte inicial (demo)');
    });

    Future<int> insumo(String nome, String tipo, String uCompra, String uUso, double fator, double min, int cat) =>
        cad.salvarItem({
          'tipo': tipo,
          'nome': nome,
          'categoria_id': cat,
          'unidade_compra': uCompra,
          'unidade_consumo': uUso,
          'fator_conversao': fator,
          'estoque_minimo': min,
        });

    final catFert = await _categoria('Fertilizantes e corretivos');
    final catDef = await _categoria('Defensivos');
    final catComb = await _categoria('Combustíveis e lubrificantes');
    final catSaco = await _categoria('Sacaria e embalagens');
    final npk = await insumo('Adubo NPK 20-05-20', 'insumo', 'saco 50 kg', 'kg', 50, 100, catFert);
    final kcl = await insumo('Cloreto de potássio (KCl)', 'insumo', 'saco 50 kg', 'kg', 50, 50, catFert);
    final inseticida = await insumo('Inseticida (broca-do-olho)', 'insumo', 'frasco 1 l', 'ml', 1000, 500, catDef);
    final diesel = await insumo('Óleo diesel', 'insumo', 'litro', 'l', 1, 20, catComb);
    final saco = await insumo('Saco de ráfia (50 cocos)', 'embalagem', 'fardo 100 un', 'un', 100, 30, catSaco);

    // Produtos e classificações.
    final cocoVerde = await cad.salvarItem({
      'tipo': 'acabado',
      'nome': 'Coco verde',
      'categoria_id': await _categoria('Coco verde'),
      'unidade_consumo': 'un',
      'unidade_venda': 'un',
      'variavel_pct_cpv': 100,
      'validade_dias': 12,
    });
    final vGraudo = (await cad.variacoes(cocoVerde)).first['id'] as int;
    await db.update('variacoes',
        {'nome': 'Graúdo', 'tamanho': 'Graúdo', 'sabor': 'Tipo A', 'preco_venda': 2.0, 'estoque_minimo': 200},
        where: 'id = ?', whereArgs: [vGraudo]);
    final vMedio = await cad.salvarVariacao({
      'item_id': cocoVerde,
      'nome': 'Médio',
      'tamanho': 'Médio',
      'sabor': 'Tipo B',
      'unidade_venda': 'un',
      'preco_venda': 1.5,
    });
    final cocoSeco = await cad.salvarItem({
      'tipo': 'acabado',
      'nome': 'Coco seco',
      'categoria_id': await _categoria('Coco seco'),
      'unidade_consumo': 'un',
      'unidade_venda': 'un',
      'variavel_pct_cpv': 100,
      'validade_dias': 60,
    });
    final vSeco = (await cad.variacoes(cocoSeco)).first['id'] as int;
    await db.update('variacoes', {'preco_venda': 1.8}, where: 'id = ?', whereArgs: [vSeco]);

    // Talhões.
    final t1 = await campo.salvarTalhao({
      'nome': 'Talhão 1 - Baixada',
      'area_ha': 4,
      'qtd_plantas': 820,
      'variedade': 'Anão verde',
      'data_plantio': '2019-03-15',
      'obs': 'Irrigado por microaspersão',
    });
    final t2 = await campo.salvarTalhao({
      'nome': 'Talhão 2 - Tabuleiro',
      'area_ha': 6,
      'qtd_plantas': 960,
      'variedade': 'Gigante do Brasil',
      'data_plantio': '2012-06-10',
    });

    final distribuidora = await db.insert('clientes', {
      'nome': 'Distribuidora Água de Coco Litoral',
      'telefone': '(79) 99999-0000',
      'criado_em': agoraIso(),
    });
    await db.insert('clientes', {'nome': 'Barraca do Zé (praia)', 'telefone': '(79) 98888-0000', 'criado_em': agoraIso()});
    final forn = await db.insert('fornecedores',
        {'nome': 'Agropecuária São José', 'telefone': '(79) 3333-0000', 'criado_em': agoraIso()});

    // Compra de insumos a prazo.
    final compras = CompraService(db);
    final validade = isoData(hoje.add(const Duration(days: 365)));
    final cid = await compras.salvar(
      fornecedorId: forn,
      data: h,
      documento: 'NF 5501',
      condicao: 'prazo',
      parcelas: 2,
      primeiroVencimento: isoData(hoje.add(const Duration(days: 30))),
      intervaloDias: 30,
      contaId: 2,
      itens: [
        ItemCompra(itemId: npk, quantidade: 4, custoTotal: 680, lote: 'NPK-24', validade: validade),
        ItemCompra(itemId: kcl, quantidade: 2, custoTotal: 360, validade: validade),
        ItemCompra(itemId: inseticida, quantidade: 2, custoTotal: 190, validade: validade),
        ItemCompra(itemId: diesel, quantidade: 100, custoTotal: 610),
        ItemCompra(itemId: saco, quantidade: 1, custoTotal: 120),
      ],
    );
    await compras.confirmar(cid);

    // Manejos (tratos culturais).
    await campo.registrarManejo(
      talhaoId: t1,
      data: h,
      operacao: 'adubacao',
      descricao: 'NPK + KCl em cobertura, na projeção da copa',
      responsavel: 'João',
      insumos: [InsumoUsado(itemId: npk, quantidade: 150), InsumoUsado(itemId: kcl, quantidade: 60)],
      maoObra: 240,
    );
    await campo.registrarManejo(
      talhaoId: t1,
      data: h,
      operacao: 'pulverizacao',
      descricao: 'Controle da broca-do-olho',
      responsavel: 'João',
      insumos: [InsumoUsado(itemId: inseticida, quantidade: 500)],
      maoObra: 120,
      outrosCustos: 40,
    );
    await campo.registrarManejo(
      talhaoId: t2,
      data: h,
      operacao: 'rocagem',
      descricao: 'Roçagem mecanizada nas entrelinhas',
      responsavel: 'Pedro',
      insumos: [InsumoUsado(itemId: diesel, quantidade: 30)],
      maoObra: 180,
    );

    // Colheitas concluídas.
    final c1 = await campo.planejarColheita(
        talhaoId: t1, itemId: cocoVerde, variacaoId: vGraudo, data: h, qtdPrevista: 2500, responsavel: 'Turma do João');
    await campo.concluirColheita(
      colheitaId: c1,
      qtdAprovada: 2400,
      refugo: 120,
      motivoPerda: 'Rachados e fora de padrão',
      maoObra: 360,
      outrosCustos: 80,
      data: h,
    );
    final c2 = await campo.planejarColheita(
        talhaoId: t2, itemId: cocoSeco, variacaoId: vSeco, data: h, qtdPrevista: 1500, responsavel: 'Pedro');
    await campo.concluirColheita(
      colheitaId: c2,
      qtdAprovada: 1500,
      refugo: 50,
      motivoPerda: 'Cocos chochos',
      insumos: [InsumoUsado(itemId: saco, quantidade: 30)],
      maoObra: 200,
      data: h,
    );
    // Próxima colheita planejada.
    await campo.planejarColheita(
        talhaoId: t1,
        itemId: cocoVerde,
        variacaoId: vMedio,
        data: isoData(hoje.add(const Duration(days: 20))),
        qtdPrevista: 2000,
        responsavel: 'Turma do João');

    // Pedido com sinal e venda à vista.
    final ped = PedidoService(db);
    final pid = await ped.salvar(
      tipo: 'encomenda',
      clienteId: distribuidora,
      canal: 'Distribuidora',
      dataPedido: h,
      dataEntrega: isoData(hoje.add(const Duration(days: 2))),
      horaEntrega: '07:00',
      personalizacao: 'Carregar no caminhão da distribuidora, na porteira',
      itens: [ItemPedido(itemId: cocoVerde, variacaoId: vGraudo, quantidade: 1000, precoUnitario: 1.8, unidadeVenda: 'un')],
    );
    await ped.confirmar(pid);
    await ped.registrarPagamento(pedidoId: pid, meioId: 2, valor: 500, data: h);
    await ped.vendaBalcao(
      data: h,
      itens: [ItemPedido(itemId: cocoVerde, variacaoId: vGraudo, quantidade: 200, precoUnitario: 2.0, unidadeVenda: 'un')],
      pagamentos: [PagamentoInfo(meioId: 1, valor: 400)],
    );

    // Despesas fixas do mês.
    await fin.lancarContaAvulsa(
      tipo: 'pagar',
      descricao: 'Arrendamento da área do Talhão 2',
      categoriaId: await _catFin('ALUGUEL'),
      valor: 800,
      competencia: h,
      primeiroVencimento: isoData(hoje.add(const Duration(days: 10))),
      contaPrevistaId: 2,
    );
    await fin.lancarContaAvulsa(
      tipo: 'pagar',
      descricao: 'Energia da irrigação',
      categoriaId: await _catFin('UTILIDADES'),
      valor: 350,
      competencia: h,
      primeiroVencimento: isoData(hoje.add(const Duration(days: 15))),
      contaPrevistaId: 2,
    );
  }
}
