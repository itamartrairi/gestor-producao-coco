import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import '../data/db.dart';

class CadastroService {
  CadastroService(this.db);
  final Database db;

  static const tiposItem = {
    'insumo': 'Insumo agrícola (adubo, defensivo, combustível…)',
    'embalagem': 'Sacaria / embalagem',
    'acabado': 'Produto (coco)',
  };

  static const unidadesVenda = ['un', 'cento', 'milheiro', 'saco', 'cacho', 'kg'];
  static const unidadesConsumo = ['kg', 'g', 'l', 'ml', 'un', 'saco', 'muda'];

  /// Salva um item. Produtos (cocos) recebem uma classificação "Padrão"
  /// quando não possuem nenhuma.
  Future<int> salvarItem(Map<String, Object?> dados, {int? id}) async {
    final nome = (dados['nome'] as String?)?.trim() ?? '';
    if (nome.isEmpty) throw RegraException('Informe o nome');
    return db.transaction((txn) async {
      int itemId;
      if (id == null) {
        itemId = await txn.insert('itens', {...dados, 'criado_em': agoraIso()});
      } else {
        await txn.update('itens', dados, where: 'id = ?', whereArgs: [id]);
        itemId = id;
      }
      final tipo = dados['tipo'] as String;
      if (tipo != 'insumo' && tipo != 'embalagem') {
        final v = await txn.query('variacoes', where: 'item_id = ?', whereArgs: [itemId]);
        if (v.isEmpty) {
          await txn.insert('variacoes', {
            'item_id': itemId,
            'nome': 'Padrão',
            'unidade_venda': dados['unidade_venda'] ?? 'un',
            'preco_venda': 0,
          });
        }
      }
      return itemId;
    });
  }

  Future<int> salvarVariacao(Map<String, Object?> dados, {int? id}) async {
    if (((dados['nome'] as String?) ?? '').trim().isEmpty) throw RegraException('Informe o nome da variação');
    if (id == null) return db.insert('variacoes', dados);
    await db.update('variacoes', dados, where: 'id = ?', whereArgs: [id]);
    return id;
  }

  Future<List<Map<String, Object?>>> itens({List<String>? tipos, bool apenasAtivos = true}) {
    final w = <String>[];
    final a = <Object?>[];
    if (apenasAtivos) w.add('i.ativo = 1');
    if (tipos != null) {
      w.add('i.tipo IN (${List.filled(tipos.length, '?').join(',')})');
      a.addAll(tipos);
    }
    return db.rawQuery('''
      SELECT i.*, c.nome categoria FROM itens i LEFT JOIN categorias c ON c.id = i.categoria_id
      ${w.isEmpty ? '' : 'WHERE ${w.join(' AND ')}'} ORDER BY i.nome''', a);
  }

  /// Lista produto+classificação para seleção em pedidos e colheitas.
  Future<List<Map<String, Object?>>> produtosVendaveis({List<String> tipos = const ['acabado']}) {
    return db.rawQuery('''
      SELECT i.id item_id, v.id variacao_id, i.nome, v.nome variacao, i.tipo,
             v.preco_venda, v.unidade_venda, i.categoria_id
      FROM itens i JOIN variacoes v ON v.item_id = i.id
      WHERE i.ativo = 1 AND v.ativo = 1 AND i.tipo IN (${List.filled(tipos.length, '?').join(',')})
      ORDER BY i.nome, v.nome''', tipos);
  }

  Future<List<Map<String, Object?>>> variacoes(int itemId) =>
      db.query('variacoes', where: 'item_id = ?', whereArgs: [itemId], orderBy: 'id');

  Future<List<Map<String, Object?>>> tabela(String nome, {String orderBy = 'nome'}) =>
      db.query(nome, orderBy: orderBy);

  Future<int> salvarSimples(String tabela, Map<String, Object?> dados, {int? id}) async {
    if (((dados['nome'] as String?) ?? '').trim().isEmpty) throw RegraException('Informe o nome');
    if (id == null) {
      final comData = ['clientes', 'fornecedores'].contains(tabela) ? {...dados, 'criado_em': agoraIso()} : dados;
      return db.insert(tabela, comData);
    }
    await db.update(tabela, dados, where: 'id = ?', whereArgs: [id]);
    return id;
  }
}
