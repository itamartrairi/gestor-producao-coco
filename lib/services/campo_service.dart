import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import '../data/db.dart';
import 'base.dart';
import 'estoque_service.dart';

/// Insumo efetivamente usado num manejo ou numa colheita.
class InsumoUsado {
  InsumoUsado({required this.itemId, required this.quantidade});
  final int itemId;
  final double quantidade;
}

class PrecoSugerido {
  PrecoSugerido({
    required this.custoUnitario,
    required this.somaPct,
    this.preco,
    required this.componentes,
    this.erro,
  });
  final double custoUnitario;
  final double somaPct;
  final double? preco;
  final Map<String, double> componentes;
  final String? erro;
}

/// Gestão do coqueiral: talhões, manejos (tratos culturais) e colheitas.
///
/// Custeio: cada manejo (adubação, pulverização, roçagem, irrigação…) baixa os
/// insumos do estoque e acumula seu custo no talhão. Na conclusão de uma
/// colheita, todos os custos ainda não apropriados do talhão (até a data da
/// colheita) somados aos custos da própria colheita formam o custo do lote de
/// cocos colhidos. Assim cada real gasto no campo é reconhecido uma única vez:
/// vai para o estoque e só entra no resultado (CPV) quando o coco é vendido.
class CampoService {
  CampoService(this.db) : estoque = EstoqueService(db);
  final Database db;
  final EstoqueService estoque;

  static const operacoes = {
    'adubacao': 'Adubação',
    'pulverizacao': 'Pulverização / controle de pragas',
    'irrigacao': 'Irrigação',
    'rocagem': 'Roçagem',
    'coroamento': 'Coroamento',
    'limpeza': 'Limpeza de copa',
    'plantio': 'Plantio / replantio',
    'outro': 'Outro',
  };

  static const rotulosColheita = {
    'planejada': 'Planejada',
    'concluida': 'Concluída',
    'cancelada': 'Cancelada',
  };

  /// Preço sugerido = custo unitário ÷ (1 − soma dos percentuais).
  static PrecoSugerido precoSugerido({
    required double custoUnitario,
    required double pctTaxas,
    required double pctImpostos,
    required double pctFixas,
    required double pctMargem,
  }) {
    final soma = pctTaxas + pctImpostos + pctFixas + pctMargem;
    if (soma >= 100) {
      return PrecoSugerido(
        custoUnitario: custoUnitario,
        somaPct: soma,
        componentes: const {},
        erro: 'A soma dos percentuais (${pct(soma)}) deve ser menor que 100%.',
      );
    }
    final preco = custoUnitario / (1 - soma / 100);
    return PrecoSugerido(
      custoUnitario: custoUnitario,
      somaPct: soma,
      preco: r2(preco),
      componentes: {
        'Custo unitário': r2(custoUnitario),
        'Taxas e fretes': r2(preco * pctTaxas / 100),
        'Impostos (Funrural etc.)': r2(preco * pctImpostos / 100),
        'Despesas fixas': r2(preco * pctFixas / 100),
        'Margem desejada': r2(preco * pctMargem / 100),
      },
    );
  }

  // ---------------- Talhões ----------------

  Future<int> salvarTalhao(Map<String, Object?> dados, {int? id}) async {
    final nome = (dados['nome'] as String?)?.trim() ?? '';
    if (nome.isEmpty) throw RegraException('Informe o nome do talhão');
    if (Base.d(dados['area_ha']) < 0) throw RegraException('Área não pode ser negativa');
    if (Base.d(dados['qtd_plantas']) < 0) throw RegraException('Quantidade de plantas não pode ser negativa');
    final reg = {...dados, 'nome': nome};
    if (id == null) return db.insert('talhoes', {...reg, 'criado_em': agoraIso()});
    await db.update('talhoes', reg, where: 'id = ?', whereArgs: [id]);
    return id;
  }

  /// Exclui um talhão sem manejos nem colheitas (senão, desative-o).
  Future<void> excluirTalhao(int talhaoId) async {
    await db.transaction((txn) async {
      final m = await txn.rawQuery('SELECT COUNT(*) c FROM manejos WHERE talhao_id = ?', [talhaoId]);
      final c = await txn.rawQuery('SELECT COUNT(*) c FROM colheitas WHERE talhao_id = ?', [talhaoId]);
      if (Base.i(m.first['c']) + Base.i(c.first['c']) > 0) {
        throw RegraException('O talhão tem manejos ou colheitas registrados. Desative-o em vez de excluir.');
      }
      await txn.delete('talhoes', where: 'id = ?', whereArgs: [talhaoId]);
      await Base.auditar(txn, 'excluir_talhao', entidade: 'talhoes', entidadeId: talhaoId);
    });
  }

  /// Talhões com custo acumulado a apropriar e produção dos últimos 365 dias.
  Future<List<Map<String, Object?>>> listarTalhoes({bool apenasAtivos = false}) {
    final desde = isoData(DateTime.now().subtract(const Duration(days: 365)));
    return db.rawQuery('''
      SELECT t.*,
        (SELECT COALESCE(SUM(m.custo_total),0) FROM manejos m
          WHERE m.talhao_id = t.id AND m.status = 'ativo' AND m.colheita_id IS NULL) custo_pendente,
        (SELECT COALESCE(SUM(c.qtd_aprovada),0) FROM colheitas c
          WHERE c.talhao_id = t.id AND c.status = 'concluida' AND c.concluida_em >= ?) colhido_12m,
        (SELECT MAX(c.concluida_em) FROM colheitas c
          WHERE c.talhao_id = t.id AND c.status = 'concluida') ultima_colheita
      FROM talhoes t ${apenasAtivos ? 'WHERE t.ativo = 1' : ''}
      ORDER BY t.ativo DESC, t.nome''', [desde]);
  }

  /// Custo dos manejos ainda não apropriados do talhão até [ate] (inclusive).
  Future<double> custoPendente(int talhaoId, {String? ate, DatabaseExecutor? ex}) async {
    final r = await (ex ?? db).rawQuery('''
      SELECT COALESCE(SUM(custo_total),0) v FROM manejos
      WHERE talhao_id = ? AND status = 'ativo' AND colheita_id IS NULL AND data <= ?''',
        [talhaoId, ate ?? '9999-12-31']);
    return r2(Base.d(r.first['v']));
  }

  // ---------------- Manejos ----------------

  /// Registra um trato cultural: baixa os insumos (por ordem de vencimento) e
  /// acumula o custo no talhão até a próxima colheita.
  Future<int> registrarManejo({
    required int talhaoId,
    required String data,
    required String operacao,
    String? descricao,
    String? responsavel,
    List<InsumoUsado> insumos = const [],
    double maoObra = 0,
    double outrosCustos = 0,
  }) async {
    if (!operacoes.containsKey(operacao)) throw RegraException('Operação inválida');
    if (maoObra < 0 || outrosCustos < 0) throw RegraException('Custos não podem ser negativos');
    final usados = insumos.where((i) => i.quantidade > Base.eps).toList();
    if (insumos.any((i) => i.quantidade < 0)) throw RegraException('Quantidade de insumo não pode ser negativa');
    if (usados.isEmpty && maoObra <= 0 && outrosCustos <= 0) {
      throw RegraException('Informe ao menos um insumo, a mão de obra ou outros custos');
    }
    return db.transaction((txn) async {
      final t = await txn.query('talhoes', where: 'id = ?', whereArgs: [talhaoId]);
      if (t.isEmpty) throw RegraException('Talhão não encontrado');
      if (Base.i(t.first['ativo']) != 1) throw RegraException('Talhão inativo');
      final id = await txn.insert('manejos', {
        'talhao_id': talhaoId,
        'data': data,
        'operacao': operacao,
        'descricao': (descricao == null || descricao.trim().isEmpty) ? null : descricao.trim(),
        'responsavel': (responsavel == null || responsavel.trim().isEmpty) ? null : responsavel.trim(),
        'status': 'ativo',
        'criado_em': agoraIso(),
      });
      var custoInsumos = 0.0;
      for (final u in usados) {
        final it = await Base.item(txn, u.itemId);
        if (!Base.ehInsumo(it['tipo'] as String)) {
          throw RegraException('${it['nome']} não é insumo nem embalagem');
        }
        final res = await estoque.consumir(txn,
            itemId: u.itemId,
            variacaoId: 0,
            quantidade: u.quantidade,
            data: data,
            tipoMov: 'consumo_manejo',
            refTipo: 'manejo',
            refId: id);
        custoInsumos += res.custoTotal;
        await txn.insert('manejo_insumos', {
          'manejo_id': id,
          'item_id': u.itemId,
          'quantidade': u.quantidade,
          'custo_unitario': r6(res.custoUnitario),
          'custo_total': res.custoTotal,
        });
      }
      final mo = r2(maoObra);
      final outros = r2(outrosCustos);
      await txn.update('manejos', {
        'custo_insumos': r2(custoInsumos),
        'custo_mao_obra': mo,
        'custo_outros': outros,
        'custo_total': r2(custoInsumos + mo + outros),
      }, where: 'id = ?', whereArgs: [id]);
      return id;
    });
  }

  /// Cancela um manejo ainda não apropriado, devolvendo os insumos ao estoque
  /// pelo mesmo custo da baixa.
  Future<void> cancelarManejo(int manejoId, String motivo) async {
    if (motivo.trim().isEmpty) throw RegraException('Informe o motivo do cancelamento');
    await db.transaction((txn) async {
      final r = await txn.query('manejos', where: 'id = ?', whereArgs: [manejoId]);
      if (r.isEmpty) throw RegraException('Manejo não encontrado');
      final m = r.first;
      if (m['status'] != 'ativo') throw RegraException('Manejo já cancelado');
      if (m['colheita_id'] != null) {
        throw RegraException('Este manejo já foi apropriado à colheita ${m['colheita_id']} e não pode ser cancelado.');
      }
      final upd = await txn.update('manejos',
          {'status': 'cancelado', 'cancelado_em': agoraIso(), 'motivo_cancelamento': motivo},
          where: "id = ? AND status = 'ativo' AND colheita_id IS NULL", whereArgs: [manejoId]);
      if (upd != 1) throw RegraException('Cancelamento duplicado bloqueado.');
      final usados = await txn.query('manejo_insumos', where: 'manejo_id = ?', whereArgs: [manejoId]);
      for (final u in usados) {
        await estoque.entradaInsumo(txn,
            itemId: u['item_id'] as int,
            qtdConsumo: Base.d(u['quantidade']),
            custoTotal: Base.d(u['custo_total']),
            data: hojeIso(),
            lote: 'EST-M$manejoId',
            refTipo: 'manejo',
            refId: manejoId,
            tipoMov: 'estorno',
            motivo: 'Cancelamento do manejo $manejoId: $motivo');
      }
      await Base.auditar(txn, 'cancelar_manejo', entidade: 'manejos', entidadeId: manejoId, motivo: motivo);
    });
  }

  /// Edita os dados de um manejo ainda não apropriado. Os insumos não mudam
  /// aqui: para corrigi-los, exclua o manejo e lance de novo.
  Future<void> editarManejo({
    required int manejoId,
    required String data,
    required String operacao,
    String? descricao,
    String? responsavel,
    required double maoObra,
    required double outrosCustos,
  }) async {
    if (!operacoes.containsKey(operacao)) throw RegraException('Operação inválida');
    if (maoObra < 0 || outrosCustos < 0) throw RegraException('Custos não podem ser negativos');
    await db.transaction((txn) async {
      final r = await txn.query('manejos', where: 'id = ?', whereArgs: [manejoId]);
      if (r.isEmpty) throw RegraException('Manejo não encontrado');
      final m = r.first;
      if (m['status'] != 'ativo') throw RegraException('Manejo cancelado não pode ser editado');
      if (m['colheita_id'] != null) {
        throw RegraException('Este manejo já foi apropriado à colheita ${m['colheita_id']}. Exclua a colheita para editá-lo.');
      }
      final insumos = Base.d(m['custo_insumos']);
      if (insumos <= 0 && maoObra <= 0 && outrosCustos <= 0) {
        throw RegraException('Informe a mão de obra ou outros custos');
      }
      await txn.update('manejos', {
        'data': data,
        'operacao': operacao,
        'descricao': (descricao == null || descricao.trim().isEmpty) ? null : descricao.trim(),
        'responsavel': (responsavel == null || responsavel.trim().isEmpty) ? null : responsavel.trim(),
        'custo_mao_obra': r2(maoObra),
        'custo_outros': r2(outrosCustos),
        'custo_total': r2(insumos + maoObra + outrosCustos),
      }, where: 'id = ?', whereArgs: [manejoId]);
      await Base.auditar(txn, 'editar_manejo', entidade: 'manejos', entidadeId: manejoId);
    });
  }

  /// Exclui um manejo não apropriado, devolvendo os insumos ao estoque.
  Future<void> excluirManejo(int manejoId) async {
    final r = await db.query('manejos', where: 'id = ?', whereArgs: [manejoId]);
    if (r.isEmpty) throw RegraException('Manejo não encontrado');
    if (r.first['colheita_id'] != null) {
      throw RegraException('Este manejo já foi apropriado à colheita ${r.first['colheita_id']}. Exclua a colheita antes.');
    }
    if (r.first['status'] == 'ativo') await cancelarManejo(manejoId, 'Exclusão do manejo');
    await db.transaction((txn) async {
      await txn.delete('manejo_insumos', where: 'manejo_id = ?', whereArgs: [manejoId]);
      await txn.delete('manejos', where: 'id = ?', whereArgs: [manejoId]);
      await Base.auditar(txn, 'excluir_manejo', entidade: 'manejos', entidadeId: manejoId);
    });
  }

  Future<List<Map<String, Object?>>> listarManejos({int? talhaoId}) => db.rawQuery('''
      SELECT m.*, t.nome talhao FROM manejos m JOIN talhoes t ON t.id = m.talhao_id
      ${talhaoId != null ? 'WHERE m.talhao_id = ?' : ''}
      ORDER BY m.data DESC, m.id DESC LIMIT 300''', [if (talhaoId != null) talhaoId]);

  Future<List<Map<String, Object?>>> insumosDoManejo(int manejoId) => db.rawQuery('''
      SELECT mi.*, i.nome, i.unidade_consumo FROM manejo_insumos mi
      JOIN itens i ON i.id = mi.item_id WHERE mi.manejo_id = ?''', [manejoId]);

  // ---------------- Colheitas ----------------

  Future<int> planejarColheita({
    required int talhaoId,
    required int itemId,
    int variacaoId = 0,
    required String data,
    double qtdPrevista = 0,
    String? responsavel,
    int? pedidoId,
    DatabaseExecutor? ex,
  }) async {
    if (qtdPrevista < 0) throw RegraException('Quantidade prevista não pode ser negativa');
    final e = ex ?? db;
    final t = await e.query('talhoes', where: 'id = ?', whereArgs: [talhaoId]);
    if (t.isEmpty) throw RegraException('Selecione o talhão');
    final it = await Base.item(e, itemId);
    if (it['tipo'] != 'acabado') throw RegraException('Selecione um produto (coco) para a colheita');
    return e.insert('colheitas', {
      'talhao_id': talhaoId,
      'item_id': itemId,
      'variacao_id': variacaoId,
      'data': data,
      'qtd_prevista': qtdPrevista,
      'responsavel': (responsavel == null || responsavel.trim().isEmpty) ? null : responsavel.trim(),
      'pedido_id': pedidoId,
      'status': 'planejada',
      'criado_em': agoraIso(),
    });
  }

  /// Edita uma colheita planejada.
  Future<void> editarColheita({
    required int colheitaId,
    required String data,
    double qtdPrevista = 0,
    String? responsavel,
  }) async {
    if (qtdPrevista < 0) throw RegraException('Quantidade prevista não pode ser negativa');
    final c = await db.query('colheitas', where: 'id = ?', whereArgs: [colheitaId]);
    if (c.isEmpty) throw RegraException('Colheita não encontrada');
    if (c.first['status'] != 'planejada') throw RegraException('Somente colheitas planejadas podem ser editadas');
    await db.update('colheitas', {
      'data': data,
      'qtd_prevista': qtdPrevista,
      'responsavel': (responsavel == null || responsavel.trim().isEmpty) ? null : responsavel.trim(),
    }, where: 'id = ?', whereArgs: [colheitaId]);
  }

  /// Exclui a colheita. Planejada ou cancelada: apenas apaga. Concluída: estorna
  /// tudo (lote de cocos, insumos da colheita, apropriação dos manejos e
  /// lançamentos na DRE), desde que nenhum coco do lote tenha sido vendido.
  Future<void> excluirColheita(int colheitaId) async {
    await db.transaction((txn) async {
      final r = await txn.query('colheitas', where: 'id = ?', whereArgs: [colheitaId]);
      if (r.isEmpty) throw RegraException('Colheita não encontrada');
      final c = r.first;
      if (c['status'] == 'concluida') {
        final loteId = c['lote_id'] as int?;
        if (loteId != null) {
          final l = (await txn.query('lotes', where: 'id = ?', whereArgs: [loteId])).first;
          if ((Base.d(l['saldo']) - Base.d(l['qtd_inicial'])).abs() > Base.eps) {
            throw RegraException('Não é possível excluir: parte dos cocos desta colheita já foi vendida ou baixada.');
          }
          final s = await estoque.saldo(l['item_id'] as int, l['variacao_id'] as int, ex: txn);
          if (s.valido - Base.d(l['qtd_inicial']) < s.reservado - Base.eps) {
            throw RegraException('Não é possível excluir: os cocos desta colheita estão reservados para pedidos.');
          }
          await txn.delete('movimentos_estoque', where: 'lote_id = ?', whereArgs: [loteId]);
          await txn.update('colheitas', {'lote_id': null}, where: 'id = ?', whereArgs: [colheitaId]);
          await txn.delete('lotes', where: 'id = ?', whereArgs: [loteId]);
        }
        // Devolve ao estoque os insumos usados na colheita.
        for (final u in await txn.query('colheita_insumos', where: 'colheita_id = ?', whereArgs: [colheitaId])) {
          await estoque.entradaInsumo(txn,
              itemId: u['item_id'] as int,
              qtdConsumo: Base.d(u['quantidade']),
              custoTotal: Base.d(u['custo_total']),
              data: hojeIso(),
              lote: 'EST-C$colheitaId',
              refTipo: 'colheita',
              refId: colheitaId,
              tipoMov: 'estorno',
              motivo: 'Exclusão da colheita $colheitaId');
        }
        // Os manejos voltam a ficar pendentes no talhão.
        await txn.update('manejos', {'colheita_id': null}, where: 'colheita_id = ?', whereArgs: [colheitaId]);
        await txn.delete('lancamentos_resultado', where: "ref_tipo = 'colheita' AND ref_id = ?", whereArgs: [colheitaId]);
      }
      await txn.update('pedido_itens', {'colheita_id': null}, where: 'colheita_id = ?', whereArgs: [colheitaId]);
      await txn.delete('colheita_insumos', where: 'colheita_id = ?', whereArgs: [colheitaId]);
      await txn.delete('colheitas', where: 'id = ?', whereArgs: [colheitaId]);
      await Base.auditar(txn, 'excluir_colheita', entidade: 'colheitas', entidadeId: colheitaId,
          detalhes: 'Status ${c['status']}');
    });
  }

  Future<void> cancelarColheita(int colheitaId, String motivo) async {
    if (motivo.trim().isEmpty) throw RegraException('Informe o motivo do cancelamento');
    await db.transaction((txn) async {
      final c = (await txn.query('colheitas', where: 'id = ?', whereArgs: [colheitaId])).first;
      if (c['status'] != 'planejada') throw RegraException('Colheita já ${c['status']}');
      await txn.update('colheitas',
          {'status': 'cancelada', 'cancelada_em': agoraIso(), 'motivo_cancelamento': motivo},
          where: 'id = ?', whereArgs: [colheitaId]);
      await txn.update('pedido_itens', {'colheita_id': null}, where: 'colheita_id = ?', whereArgs: [colheitaId]);
      await Base.auditar(txn, 'cancelar_colheita', entidade: 'colheitas', entidadeId: colheitaId, motivo: motivo);
    });
  }

  /// Conclui a colheita numa única transação: apropria os manejos pendentes do
  /// talhão, baixa os insumos usados na colheita (sacaria, combustível…), apura
  /// o custo do lote e dá entrada nos cocos aprovados.
  ///
  /// Custo unitário = custo total ÷ (aprovada + perda anormal). O refugo normal
  /// (cocos rachados, fora de padrão, descarte habitual) fica absorvido no custo
  /// dos aprovados; a perda anormal (chuva, praga, roubo) vai para o resultado.
  Future<int> concluirColheita({
    required int colheitaId,
    required double qtdAprovada,
    double refugo = 0,
    double perdaAnormal = 0,
    String? motivoPerda,
    List<InsumoUsado> insumos = const [],
    double maoObra = 0,
    double outrosCustos = 0,
    String? validade,
    String? data,
  }) async {
    if (qtdAprovada <= 0) throw RegraException('Informe a quantidade colhida aprovada');
    if (refugo < 0 || perdaAnormal < 0) throw RegraException('Perdas não podem ser negativas');
    if (maoObra < 0 || outrosCustos < 0) throw RegraException('Custos não podem ser negativos');
    if ((refugo + perdaAnormal) > 0 && (motivoPerda == null || motivoPerda.trim().isEmpty)) {
      throw RegraException('Informe o motivo do refugo/perdas');
    }
    return db.transaction((txn) async {
      final r = await txn.query('colheitas', where: 'id = ?', whereArgs: [colheitaId]);
      if (r.isEmpty) throw RegraException('Colheita não encontrada');
      final c = r.first;
      if (c['status'] == 'concluida') throw RegraException('Esta colheita já foi concluída.');
      if (c['status'] == 'cancelada') throw RegraException('Colheita cancelada');
      final upd = await txn.update('colheitas', {'status': 'concluida'},
          where: "id = ? AND status = 'planejada'", whereArgs: [colheitaId]);
      if (upd != 1) throw RegraException('Conclusão duplicada bloqueada.');
      final dt = data ?? hojeIso();
      final talhaoId = c['talhao_id'] as int;
      final itemId = c['item_id'] as int;
      final varId = c['variacao_id'] as int;

      // 1. Manejos pendentes do talhão até a data da colheita.
      final pend = await txn.rawQuery('''
        SELECT COALESCE(SUM(custo_total),0) total, COALESCE(SUM(custo_mao_obra + custo_outros),0) mo_outros
        FROM manejos WHERE talhao_id = ? AND status = 'ativo' AND colheita_id IS NULL AND data <= ?''',
          [talhaoId, dt]);
      final custoManejo = r2(Base.d(pend.first['total']));
      final moOutrosManejo = r2(Base.d(pend.first['mo_outros']));
      await txn.update('manejos', {'colheita_id': colheitaId},
          where: "talhao_id = ? AND status = 'ativo' AND colheita_id IS NULL AND data <= ?",
          whereArgs: [talhaoId, dt]);

      // 2. Insumos usados na própria colheita.
      var custoInsumos = 0.0;
      for (final u in insumos) {
        if (u.quantidade < 0) throw RegraException('Quantidade de insumo não pode ser negativa');
        if (u.quantidade <= Base.eps) continue;
        final it = await Base.item(txn, u.itemId);
        if (!Base.ehInsumo(it['tipo'] as String)) throw RegraException('${it['nome']} não é insumo nem embalagem');
        final res = await estoque.consumir(txn,
            itemId: u.itemId,
            variacaoId: 0,
            quantidade: u.quantidade,
            data: dt,
            tipoMov: 'consumo_colheita',
            refTipo: 'colheita',
            refId: colheitaId);
        custoInsumos += res.custoTotal;
        await txn.insert('colheita_insumos', {
          'colheita_id': colheitaId,
          'item_id': u.itemId,
          'quantidade': u.quantidade,
          'custo_unitario': r6(res.custoUnitario),
          'custo_total': res.custoTotal,
        });
      }

      // 3. Custo do lote.
      final mo = r2(maoObra);
      final outros = r2(outrosCustos);
      final total = r2(custoManejo + custoInsumos + mo + outros);
      final unit = total / (qtdAprovada + perdaAnormal);
      final custoAnormal = r2(unit * perdaAnormal);
      final it = await Base.item(txn, itemId);
      final validadeLote = (validade != null && validade.isNotEmpty)
          ? validade
          : isoData(parseIso(dt).add(Duration(days: Base.i(it['validade_dias']))));
      final codigo = 'C${dt.replaceAll('-', '').substring(2)}-$colheitaId';
      final loteId = await estoque.entradaProduzido(txn,
          itemId: itemId,
          variacaoId: varId,
          quantidade: qtdAprovada,
          custoUnitario: unit,
          codigoLote: codigo,
          fabricacao: dt,
          validade: validadeLote,
          refTipo: 'colheita',
          refId: colheitaId,
          tipoMov: 'colheita');
      final nome = await Base.nomeItem(txn, itemId, varId);
      if (custoAnormal > 0) {
        await Base.lancarResultado(txn,
            data: dt,
            grupo: 'despesa_variavel',
            descricao: 'Perda anormal na colheita: $nome (colheita $colheitaId) - ${motivoPerda ?? ''}',
            valor: custoAnormal,
            categoriaId: await Base.categoriaFin(txn, 'PERDAS'),
            refTipo: 'colheita',
            refId: colheitaId,
            chave: 'colheita:$colheitaId:perda_anormal');
      }
      // Mão de obra e outros custos de campo apropriados aos cocos saem das
      // despesas do período (entram no CPV quando o coco for vendido).
      final creditar = (await Base(db).config('creditar_custos_apropriados', ex: txn)) != '0';
      final apropriado = r2(moOutrosManejo + mo + outros);
      if (creditar && apropriado > 0) {
        await Base.lancarResultado(txn,
            data: dt,
            grupo: 'despesa_fixa',
            descricao: '(-) Mão de obra e custos de campo apropriados ao estoque (colheita $colheitaId)',
            valor: -apropriado,
            refTipo: 'colheita',
            refId: colheitaId,
            variavel: false,
            chave: 'colheita:$colheitaId:apropriacao');
      }
      await txn.update('colheitas', {
        'qtd_aprovada': qtdAprovada,
        'qtd_refugo': refugo,
        'qtd_perda_anormal': perdaAnormal,
        'motivo_perda': (motivoPerda == null || motivoPerda.trim().isEmpty) ? null : motivoPerda.trim(),
        'lote_id': loteId,
        'custo_manejo': custoManejo,
        'custo_insumos': r2(custoInsumos),
        'custo_mao_obra': mo,
        'custo_outros': outros,
        'custo_total': total,
        'custo_unitario': r6(unit),
        'custo_perda_anormal': custoAnormal,
        'concluida_em': dt,
      }, where: 'id = ?', whereArgs: [colheitaId]);

      // 4. Reserva automática para o pedido vinculado.
      final pedidoId = c['pedido_id'] as int?;
      if (pedidoId != null) {
        final itensPed = await txn.query('pedido_itens',
            where: 'pedido_id = ? AND item_id = ? AND variacao_id = ?', whereArgs: [pedidoId, itemId, varId]);
        for (final pi in itensPed) {
          final jaRes = await estoque.reservadoPara(txn, pi['id'] as int);
          final falta = Base.d(pi['quantidade']) - jaRes;
          if (falta <= Base.eps) continue;
          final s = await estoque.saldo(itemId, varId, ex: txn);
          final q = falta < s.disponivel ? falta : s.disponivel;
          if (q > Base.eps) {
            await estoque.reservar(txn,
                pedidoId: pedidoId, pedidoItemId: pi['id'] as int, itemId: itemId, variacaoId: varId, quantidade: q);
          }
        }
        await atualizarStatusPedidoPronto(txn, pedidoId);
      }
      return loteId;
    });
  }

  /// Marca o pedido como pronto quando todos os itens estão reservados.
  Future<void> atualizarStatusPedidoPronto(DatabaseExecutor ex, int pedidoId) async {
    final p = (await ex.query('pedidos', where: 'id = ?', whereArgs: [pedidoId])).first;
    if (!['confirmado', 'em_producao'].contains(p['status'])) return;
    final itens = await ex.query('pedido_itens', where: 'pedido_id = ?', whereArgs: [pedidoId]);
    for (final pi in itens) {
      final r = await estoque.reservadoPara(ex, pi['id'] as int);
      if (r + Base.eps < Base.d(pi['quantidade'])) return;
    }
    await ex.update('pedidos', {'status': 'pronto'}, where: 'id = ?', whereArgs: [pedidoId]);
  }

  Future<List<Map<String, Object?>>> listarColheitas({String? status, int? talhaoId}) {
    final w = <String>[];
    final a = <Object?>[];
    if (status != null) {
      w.add('c.status = ?');
      a.add(status);
    }
    if (talhaoId != null) {
      w.add('c.talhao_id = ?');
      a.add(talhaoId);
    }
    return db.rawQuery('''
      SELECT c.*, i.nome, v.nome variacao, t.nome talhao, COALESCE(v.unidade_venda, i.unidade_venda, 'un') unidade
      FROM colheitas c JOIN itens i ON i.id = c.item_id
      LEFT JOIN variacoes v ON v.id = c.variacao_id
      JOIN talhoes t ON t.id = c.talhao_id
      ${w.isEmpty ? '' : 'WHERE ${w.join(' AND ')}'}
      ORDER BY CASE c.status WHEN 'planejada' THEN 0 WHEN 'concluida' THEN 1 ELSE 2 END,
               c.data DESC, c.id DESC''', a);
  }

  Future<List<Map<String, Object?>>> insumosDaColheita(int colheitaId) => db.rawQuery('''
      SELECT ci.*, i.nome, i.unidade_consumo FROM colheita_insumos ci
      JOIN itens i ON i.id = ci.item_id WHERE ci.colheita_id = ?''', [colheitaId]);

  Future<List<Map<String, Object?>>> manejosDaColheita(int colheitaId) =>
      db.query('manejos', where: 'colheita_id = ?', whereArgs: [colheitaId], orderBy: 'data, id');
}
