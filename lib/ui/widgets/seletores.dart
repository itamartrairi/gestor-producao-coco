import 'package:flutter/material.dart';

import '../../core/format.dart';
import 'comum.dart';

String nomeComVariacao(Map<String, Object?> m) {
  final v = m['variacao'] as String?;
  return v == null || v == 'Padrão' ? (m['nome'] as String? ?? '') : '${m['nome']} - $v';
}

/// Lista pesquisável em diálogo de tela cheia.
Future<Map<String, Object?>?> escolherDaLista(
  BuildContext context, {
  required String titulo,
  required List<Map<String, Object?>> itens,
  required String Function(Map<String, Object?>) rotulo,
  String Function(Map<String, Object?>)? subtitulo,
}) {
  return showDialog<Map<String, Object?>>(
    context: context,
    builder: (c) {
      var filtro = '';
      return StatefulBuilder(builder: (c, set) {
        final lista = itens.where((i) => rotulo(i).toLowerCase().contains(filtro.toLowerCase())).toList();
        return Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(title: Text(titulo)),
            body: Column(children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  autofocus: false,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Pesquisar', border: OutlineInputBorder()),
                  onChanged: (v) => set(() => filtro = v),
                ),
              ),
              Expanded(
                child: lista.isEmpty
                    ? const Vazio('Nada encontrado. Cadastre em Mais > Cadastros.')
                    : ListView.builder(
                        itemCount: lista.length,
                        itemBuilder: (c, i) => ListTile(
                          title: Text(rotulo(lista[i])),
                          subtitle: subtitulo == null ? null : Text(subtitulo(lista[i])),
                          onTap: () => Navigator.pop(c, lista[i]),
                        ),
                      ),
              ),
            ]),
          ),
        );
      });
    },
  );
}

Future<Map<String, Object?>?> escolherProduto(BuildContext context,
    {List<String> tipos = const ['acabado']}) async {
  final itens = await S.cad.produtosVendaveis(tipos: tipos);
  if (!context.mounted) return null;
  return escolherDaLista(context,
      titulo: 'Escolher produto',
      itens: itens,
      rotulo: nomeComVariacao,
      subtitulo: (m) => '${brl(m['preco_venda'] as num?)} / ${m['unidade_venda']}');
}

Future<Map<String, Object?>?> escolherInsumo(BuildContext context) async {
  final itens = await S.cad.itens(tipos: ['insumo', 'embalagem']);
  if (!context.mounted) return null;
  return escolherDaLista(context,
      titulo: 'Escolher insumo',
      itens: itens,
      rotulo: (m) => m['nome'] as String,
      subtitulo: (m) => 'Compra: ${m['unidade_compra'] ?? '-'} = ${numero(m['fator_conversao'] as num?)} ${m['unidade_consumo']}');
}

Future<Map<String, Object?>?> escolherTalhao(BuildContext context) async {
  final itens = await S.campo.listarTalhoes(apenasAtivos: true);
  if (!context.mounted) return null;
  return escolherDaLista(context,
      titulo: 'Escolher talhão',
      itens: itens,
      rotulo: (m) => m['nome'] as String,
      subtitulo: (m) => [
            if ((m['variedade'] as String?)?.isNotEmpty == true) m['variedade'] as String,
            '${numero(m['area_ha'] as num?, casas: 2)} ha',
            '${m['qtd_plantas']} plantas',
          ].join(' • '));
}

Future<Map<String, Object?>?> escolherCliente(BuildContext context) async {
  final itens = await S.cad.tabela('clientes');
  if (!context.mounted) return null;
  return escolherDaLista(context,
      titulo: 'Cliente', itens: itens, rotulo: (m) => m['nome'] as String, subtitulo: (m) => (m['telefone'] as String?) ?? '');
}

Future<Map<int, String>> opcoesTabela(String tabela, {String? where}) async {
  final r = await banco.query(tabela, where: where ?? 'ativo = 1', orderBy: 'nome');
  return {for (final x in r) x['id'] as int: x['nome'] as String};
}
