import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import '../data/db.dart';
import 'base.dart';
import 'estoque_service.dart';
import 'financeiro_service.dart';

class ItemCompra {
  ItemCompra({
    required this.itemId,
    required this.quantidade,
    required this.custoTotal,
    this.lote,
    this.validade,
  });
  final int itemId;
  /// Quantidade na unidade de compra (ex.: 1 pacote de 5 kg).
  final double quantidade;
  final double custoTotal;
  final String? lote;
  final String? validade;
}

class CompraService {
  CompraService(this.db)
      : estoque = EstoqueService(db),
        fin = FinanceiroService(db);
  final Database db;
  final EstoqueService estoque;
  final FinanceiroService fin;

  /// Salva a compra como rascunho e devolve o id.
  Future<int> salvar({
    int? id,
    int? fornecedorId,
    required String data,
    String? documento,
    required String condicao, // avista | prazo
    int parcelas = 1,
    String? primeiroVencimento,
    int intervaloDias = 30,
    int? contaId,
    String? obs,
    required List<ItemCompra> itens,
  }) async {
    if (itens.isEmpty) throw RegraException('Inclua ao menos um item');
    return db.transaction((txn) async {
      final dados = {
        'fornecedor_id': fornecedorId,
        'data': data,
        'documento': documento,
        'condicao': condicao,
        'parcelas': condicao == 'avista' ? 1 : (parcelas < 1 ? 1 : parcelas),
        'primeiro_vencimento': primeiroVencimento,
        'intervalo_dias': intervaloDias,
        'conta_id': contaId,
        'obs': obs,
        'total': r2(itens.fold(0.0, (s, i) => s + i.custoTotal)),
      };
      int compraId;
      if (id == null) {
        compraId = await txn.insert('compras', {...dados, 'status': 'rascunho', 'criado_em': agoraIso()});
      } else {
        final c = await txn.query('compras', where: 'id = ?', whereArgs: [id]);
        if (c.first['status'] != 'rascunho') throw RegraException('Compra já confirmada não pode ser editada');
        await txn.update('compras', dados, where: 'id = ?', whereArgs: [id]);
        await txn.delete('compra_itens', where: 'compra_id = ?', whereArgs: [id]);
        compraId = id;
      }
      for (final i in itens) {
        if (i.quantidade <= 0 || i.custoTotal < 0) throw RegraException('Quantidade e custo devem ser positivos');
        await txn.insert('compra_itens', {
          'compra_id': compraId,
          'item_id': i.itemId,
          'quantidade': i.quantidade,
          'custo_total': r2(i.custoTotal),
          'lote': i.lote,
          'validade': i.validade,
        });
      }
      return compraId;
    });
  }

  /// Confirma a compra: entrada no estoque (custo médio), obrigação financeira
  /// e, se à vista, a quitação com saída na conta selecionada. Tudo numa transação.
  Future<void> confirmar(int compraId) async {
    await db.transaction((txn) async {
      final rows = await txn.query('compras', where: 'id = ?', whereArgs: [compraId]);
      if (rows.isEmpty) throw RegraException('Compra não encontrada');
      final c = rows.first;
      if (c['status'] != 'rascunho') throw RegraException('Esta compra já foi confirmada.');
      final upd = await txn.update('compras', {'status': 'confirmada', 'confirmada_em': agoraIso()},
          where: "id = ? AND status = 'rascunho'", whereArgs: [compraId]);
      if (upd != 1) throw RegraException('Confirmação duplicada bloqueada.');
      final data = c['data'] as String;
      final itens = await txn.query('compra_itens', where: 'compra_id = ?', whereArgs: [compraId]);
      for (final i in itens) {
        final it = await Base.item(txn, i['item_id'] as int);
        if (!Base.ehInsumo(it['tipo'] as String)) {
          throw RegraException('${it['nome']} não é insumo nem embalagem.');
        }
        final fator = Base.d(it['fator_conversao']) <= 0 ? 1.0 : Base.d(it['fator_conversao']);
        await estoque.entradaInsumo(txn,
            itemId: i['item_id'] as int,
            qtdConsumo: Base.d(i['quantidade']) * fator,
            custoTotal: Base.d(i['custo_total']),
            data: data,
            lote: i['lote'] as String?,
            validade: i['validade'] as String?,
            refTipo: 'compra',
            refId: compraId);
      }
      final total = Base.d(c['total']);
      if (total <= 0) return;
      final cat = await Base.categoriaFin(txn, 'COMPRA_INSUMO');
      String nomeForn = '';
      if (c['fornecedor_id'] != null) {
        final f = await txn.query('fornecedores', where: 'id = ?', whereArgs: [c['fornecedor_id']]);
        if (f.isNotEmpty) nomeForn = ' - ${f.first['nome']}';
      }
      final doc = (c['documento'] as String?)?.isNotEmpty == true ? ' doc ${c['documento']}' : '';
      final desc = 'Compra #$compraId$doc$nomeForn';
      if (c['condicao'] == 'avista') {
        final conta = c['conta_id'] as int?;
        if (conta == null) throw RegraException('Selecione a conta de pagamento da compra à vista');
        final saldoConta = await fin.saldoConta(conta, ex: txn);
        if (total > saldoConta + 0.005) {
          throw RegraException('Saldo insuficiente na conta (${brl(saldoConta)}). Registre um aporte ou escolha outra conta.');
        }
        final tid = await fin.criarTitulo(txn,
            tipo: 'pagar',
            descricao: desc,
            categoriaId: cat,
            valor: total,
            vencimento: data,
            competencia: data,
            fornecedorId: c['fornecedor_id'] as int?,
            refTipo: 'compra',
            refId: compraId,
            contaPrevistaId: conta);
        await fin.baixarTitulo(ex: txn, tituloId: tid, data: data, contaId: conta, principal: total);
      } else {
        final n = Base.i(c['parcelas']) < 1 ? 1 : Base.i(c['parcelas']);
        final valores = FinanceiroService.dividir(total, n);
        final venc0 = parseIso((c['primeiro_vencimento'] as String?) ??
            isoData(parseIso(data).add(Duration(days: Base.i(c['intervalo_dias'])))));
        for (var p = 0; p < n; p++) {
          await fin.criarTitulo(txn,
              tipo: 'pagar',
              descricao: n > 1 ? '$desc (${p + 1}/$n)' : desc,
              categoriaId: cat,
              valor: valores[p],
              vencimento: isoData(venc0.add(Duration(days: Base.i(c['intervalo_dias']) * p))),
              competencia: data,
              fornecedorId: c['fornecedor_id'] as int?,
              refTipo: 'compra',
              refId: compraId,
              parcela: p + 1,
              totalParcelas: n,
              contaPrevistaId: c['conta_id'] as int?);
        }
      }
      await Base.auditar(txn, 'confirmar_compra', entidade: 'compras', entidadeId: compraId,
          detalhes: 'Total ${brl(total)}');
    });
  }

  Future<void> excluirRascunho(int compraId) async {
    final c = await db.query('compras', where: 'id = ?', whereArgs: [compraId]);
    if (c.isEmpty || c.first['status'] != 'rascunho') {
      throw RegraException('Somente rascunhos podem ser excluídos');
    }
    await db.delete('compras', where: 'id = ?', whereArgs: [compraId]);
  }

  Future<List<Map<String, Object?>>> listar() => db.rawQuery('''
      SELECT c.*, f.nome fornecedor FROM compras c LEFT JOIN fornecedores f ON f.id = c.fornecedor_id
      ORDER BY c.data DESC, c.id DESC''');

  Future<List<Map<String, Object?>>> itens(int compraId) => db.rawQuery('''
      SELECT ci.*, i.nome, i.unidade_compra, i.unidade_consumo, i.fator_conversao
      FROM compra_itens ci JOIN itens i ON i.id = ci.item_id WHERE ci.compra_id = ?''', [compraId]);
}
