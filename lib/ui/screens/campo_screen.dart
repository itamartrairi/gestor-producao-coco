import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../services/base.dart';
import '../../services/campo_service.dart';
import '../widgets/comum.dart';
import '../widgets/seletores.dart';

/// Aba "Campo": colheitas, manejos (tratos culturais) e talhões do coqueiral.
class CampoScreen extends StatelessWidget {
  const CampoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Campo'),
          bottom: const TabBar(tabs: [Tab(text: 'Colheitas'), Tab(text: 'Manejos'), Tab(text: 'Talhões')]),
        ),
        body: const TabBarView(children: [_ListaColheitas(), _ListaManejos(), _ListaTalhoes()]),
      ),
    );
  }
}

Color _corStatus(String st) => switch (st) {
      'concluida' || 'ativo' => Colors.green.shade700,
      'cancelada' || 'cancelado' => Colors.red,
      _ => Colors.orange.shade800,
    };

// ---------------- Colheitas ----------------

class _ListaColheitas extends StatefulWidget {
  const _ListaColheitas();
  @override
  State<_ListaColheitas> createState() => _ListaColheitasState();
}

class _ListaColheitasState extends State<_ListaColheitas> {
  int _v = 0;

  Future<void> _nova() async {
    final id = await novaColheita(context);
    if (id != null && mounted) await abrir(context, ColheitaDetalheScreen(colheitaId: id));
    if (mounted) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton:
          FloatingActionButton.extended(heroTag: 'colheita', onPressed: _nova, icon: const Icon(Icons.add), label: const Text('Colheita')),
      body: Carregar<List<Map<String, Object?>>>(
        key: ValueKey(_v),
        futuro: () => S.campo.listarColheitas(),
        builder: (context, lista, rec) {
          if (lista.isEmpty) {
            return const Vazio('Nenhuma colheita. Cadastre os talhões e os produtos (coco verde, coco seco) e toque em + Colheita.');
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: lista.length,
            itemBuilder: (c, i) {
              final o = lista[i];
              final st = o['status'] as String;
              final qtd = st == 'concluida' ? Base.d(o['qtd_aprovada']) : Base.d(o['qtd_prevista']);
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.agriculture_outlined),
                  title: Text('${nomeComVariacao(o)} • ${o['talhao']}'),
                  subtitle: Text([
                    if (qtd > 0) '${numero(qtd)} ${o['unidade']}${st == 'concluida' ? '' : ' previstos'}',
                    dataBr((o['concluida_em'] ?? o['data']) as String),
                    if (o['responsavel'] != null) o['responsavel'] as String,
                    if (o['pedido_id'] != null) 'Pedido #${o['pedido_id']}',
                    if (st == 'concluida') 'Custo un. ${brl(Base.d(o['custo_unitario']))}',
                  ].join(' • ')),
                  trailing: Etiqueta(CampoService.rotulosColheita[st] ?? st, cor: _corStatus(st)),
                  onTap: () async {
                    await abrir(context, ColheitaDetalheScreen(colheitaId: o['id'] as int));
                    rec();
                  },
                  onLongPress: () async {
                    final op = await menuEditarExcluir(context, podeEditar: st == 'planejada');
                    if (op == null || !context.mounted) return;
                    if (op == 'editar') await editarColheita(context, o);
                    if (op == 'excluir') await excluirColheitaUi(context, o);
                    rec();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Edita data, quantidade prevista e responsável de uma colheita planejada.
Future<bool> editarColheita(BuildContext context, Map<String, Object?> o) async {
  final qtd = TextEditingController(text: Base.d(o['qtd_prevista']) > 0 ? fmtCampo(Base.d(o['qtd_prevista'])) : '');
  final resp = TextEditingController(text: (o['responsavel'] as String?) ?? '');
  var data = o['data'] as String;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text('Editar colheita ${o['id']}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CampoData('Data da colheita', data, (v) => set(() => data = v ?? data)),
            CampoNumero('Quantidade prevista', qtd),
            CampoTexto('Responsável / turma', resp),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salvar')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return false;
  return executar(
      context,
      () => S.campo.editarColheita(
          colheitaId: o['id'] as int, data: data, qtdPrevista: parseNum(qtd.text), responsavel: resp.text),
      sucesso: 'Colheita atualizada');
}

/// Confirma e exclui (ou estorna, se concluída) uma colheita.
Future<bool> excluirColheitaUi(BuildContext context, Map<String, Object?> o) async {
  final concluida = o['status'] == 'concluida';
  if (!await confirmarExclusao(context, 'a colheita ${o['id']}',
      detalhe: concluida
          ? 'O lote de cocos sai do estoque, os insumos da colheita voltam ao estoque e os manejos voltam a ficar '
              'pendentes no talhão. Só é possível se nenhum coco do lote foi vendido.'
          : null)) {
    return false;
  }
  if (!context.mounted) return false;
  return executar(context, () => S.campo.excluirColheita(o['id'] as int), sucesso: 'Colheita excluída');
}

/// Diálogo para planejar uma colheita. Devolve o id criado.
Future<int?> novaColheita(BuildContext context, {int? pedidoId}) async {
  final talhao = await escolherTalhao(context);
  if (talhao == null || !context.mounted) return null;
  final p = await escolherProduto(context);
  if (p == null || !context.mounted) return null;
  final qtd = TextEditingController();
  final resp = TextEditingController();
  String data = hojeIso();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text('Colheita: ${nomeComVariacao(p)}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Talhão: ${talhao['nome']}'),
            const SizedBox(height: 8),
            CampoData('Data da colheita', data, (v) => set(() => data = v ?? hojeIso())),
            CampoNumero('Quantidade prevista (opcional)', qtd, sufixo: p['unidade_venda'] as String?),
            CampoTexto('Responsável / turma', resp),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Criar')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return null;
  int? id;
  await executar(context, () async {
    id = await S.campo.planejarColheita(
      talhaoId: talhao['id'] as int,
      itemId: p['item_id'] as int,
      variacaoId: p['variacao_id'] as int,
      data: data,
      qtdPrevista: parseNum(qtd.text),
      responsavel: resp.text,
      pedidoId: pedidoId,
    );
  });
  return id;
}

class ColheitaDetalheScreen extends StatefulWidget {
  const ColheitaDetalheScreen({super.key, required this.colheitaId});
  final int colheitaId;
  @override
  State<ColheitaDetalheScreen> createState() => _ColheitaDetalheScreenState();
}

class _ColheitaDetalheScreenState extends State<ColheitaDetalheScreen> {
  int _v = 0;

  Future<Map<String, Object?>> _dados() async {
    final o = (await banco.rawQuery('''
      SELECT c.*, i.nome, i.validade_dias, v.nome variacao, t.nome talhao,
             COALESCE(v.unidade_venda, i.unidade_venda, 'un') unidade
      FROM colheitas c JOIN itens i ON i.id = c.item_id LEFT JOIN variacoes v ON v.id = c.variacao_id
      JOIN talhoes t ON t.id = c.talhao_id WHERE c.id = ?''', [widget.colheitaId])).first;
    final st = o['status'] as String;
    return {
      'o': o,
      'pendente': st == 'planejada' ? await S.campo.custoPendente(o['talhao_id'] as int) : 0.0,
      'insumos': st == 'concluida' ? await S.campo.insumosDaColheita(widget.colheitaId) : <Map<String, Object?>>[],
      'manejos': st == 'concluida' ? await S.campo.manejosDaColheita(widget.colheitaId) : <Map<String, Object?>>[],
      'lote': o['lote_id'] == null ? null : (await banco.query('lotes', where: 'id = ?', whereArgs: [o['lote_id']])).first,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Carregar<Map<String, Object?>>(
      key: ValueKey(_v),
      futuro: _dados,
      builder: (context, d, rec) {
        final o = d['o'] as Map<String, Object?>;
        final pendente = d['pendente'] as double;
        final ins = d['insumos'] as List<Map<String, Object?>>;
        final mans = d['manejos'] as List<Map<String, Object?>>;
        final lote = d['lote'] as Map<String, Object?>?;
        final st = o['status'] as String;
        final unit = Base.d(o['custo_unitario']);
        return Scaffold(
          appBar: AppBar(
            title: Text('Colheita ${o['id']}'),
            actions: [
              if (st == 'planejada')
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Editar',
                  onPressed: () async {
                    if (await editarColheita(context, o) && mounted) setState(() => _v++);
                  },
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Excluir',
                onPressed: () async {
                  if (await excluirColheitaUi(context, o) && context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.all(12), children: [
            Text(nomeComVariacao(o), style: Theme.of(context).textTheme.titleMedium),
            Text('Talhão ${o['talhao']} • ${dataBr(o['data'] as String)}'
                '${Base.d(o['qtd_prevista']) > 0 ? ' • previsto ${numero(Base.d(o['qtd_prevista']))} ${o['unidade']}' : ''}'),
            if (o['responsavel'] != null) Text('Responsável: ${o['responsavel']}'),
            if (o['pedido_id'] != null) Text('Pedido vinculado: #${o['pedido_id']}'),
            const SizedBox(height: 6),
            Align(alignment: Alignment.centerLeft, child: Etiqueta(CampoService.rotulosColheita[st] ?? st, cor: _corStatus(st))),
            if (st == 'planejada') ...[
              const Secao('Custos acumulados no talhão'),
              LinhaValor('Manejos ainda não apropriados', brl(pendente)),
              const Text(
                'Ao concluir, os custos dos manejos do talhão até a data da colheita são apropriados a este lote de cocos.',
                style: TextStyle(fontSize: 12),
              ),
            ],
            if (st == 'concluida') ...[
              const Secao('Resultado'),
              LinhaValor('Quantidade aprovada', '${numero(Base.d(o['qtd_aprovada']))} ${o['unidade']}'),
              LinhaValor('Refugo normal', numero(Base.d(o['qtd_refugo']))),
              LinhaValor('Perda anormal', numero(Base.d(o['qtd_perda_anormal']))),
              if (o['motivo_perda'] != null) LinhaValor('Motivo', o['motivo_perda'] as String),
              if (lote != null) LinhaValor('Lote', '${lote['codigo']} • validade ${dataBr(lote['validade'] as String?)}'),
              const Secao('Custos apropriados'),
              LinhaValor('Manejos do talhão', brl(Base.d(o['custo_manejo']))),
              LinhaValor('Insumos da colheita', brl(Base.d(o['custo_insumos']))),
              LinhaValor('Mão de obra da colheita', brl(Base.d(o['custo_mao_obra']))),
              LinhaValor('Outros (frete interno, diesel…)', brl(Base.d(o['custo_outros']))),
              LinhaValor('Custo total', brl(Base.d(o['custo_total'])), negrito: true),
              LinhaValor('Custo por ${o['unidade']}', brl(unit), negrito: true),
              if ('${o['unidade']}' == 'un') LinhaValor('Custo por cento', brl(unit * 100)),
              if (Base.d(o['custo_perda_anormal']) > 0)
                LinhaValor('Perda anormal (lançada no resultado)', brl(Base.d(o['custo_perda_anormal'])), cor: Colors.red),
              if (mans.isNotEmpty) ...[
                const Secao('Manejos apropriados'),
                for (final m in mans)
                  ListTile(
                    dense: true,
                    title: Text(CampoService.operacoes[m['operacao']] ?? '${m['operacao']}'),
                    subtitle: Text(dataBr(m['data'] as String)),
                    trailing: Text(brl(Base.d(m['custo_total']))),
                  ),
              ],
              if (ins.isNotEmpty) ...[
                const Secao('Insumos usados na colheita'),
                for (final c in ins)
                  ListTile(
                    dense: true,
                    title: Text(c['nome'] as String),
                    subtitle: Text('${numero(Base.d(c['quantidade']))} ${c['unidade_consumo']} × ${brl(Base.d(c['custo_unitario']))}'),
                    trailing: Text(brl(Base.d(c['custo_total']))),
                  ),
              ],
            ],
            if (o['motivo_cancelamento'] != null) LinhaValor('Motivo do cancelamento', o['motivo_cancelamento'] as String),
            const SizedBox(height: 80),
          ]),
          bottomNavigationBar: st != 'planejada'
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(children: [
                      TextButton(
                        onPressed: () async {
                          final m = await pedirTexto(context, 'Cancelar colheita');
                          if (m == null || !context.mounted) return;
                          await executar(context, () => S.campo.cancelarColheita(widget.colheitaId, m));
                          setState(() => _v++);
                        },
                        child: const Text('Cancelar', style: TextStyle(color: Colors.red)),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        icon: const Icon(Icons.check),
                        onPressed: () async {
                          final ok = await abrir<bool>(context, ConcluirColheitaScreen(colheita: o));
                          if (ok == true) setState(() => _v++);
                        },
                        label: const Text('Registrar colheita'),
                      ),
                    ]),
                  ),
                ),
        );
      },
    );
  }
}

/// Linha editável de insumo (usada em manejos e colheitas).
class _LinhaInsumo {
  _LinhaInsumo(this.item) : qtd = TextEditingController();
  final Map<String, Object?> item;
  final TextEditingController qtd;
}

Widget _blocoInsumos(BuildContext context, List<_LinhaInsumo> linhas, VoidCallback mudou, {required String titulo}) {
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Secao(titulo,
        acao: TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Insumo'),
          onPressed: () async {
            final it = await escolherInsumo(context);
            if (it == null) return;
            linhas.add(_LinhaInsumo(it));
            mudou();
          },
        )),
    if (linhas.isEmpty) const Text('Nenhum insumo.', style: TextStyle(fontSize: 12, color: Colors.grey)),
    for (final l in linhas)
      Row(children: [
        Expanded(child: CampoNumero(l.item['nome'] as String, l.qtd, sufixo: l.item['unidade_consumo'] as String?)),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () {
            linhas.remove(l);
            mudou();
          },
        ),
      ]),
  ]);
}

class ConcluirColheitaScreen extends StatefulWidget {
  const ConcluirColheitaScreen({super.key, required this.colheita});
  final Map<String, Object?> colheita;
  @override
  State<ConcluirColheitaScreen> createState() => _ConcluirColheitaScreenState();
}

class _ConcluirColheitaScreenState extends State<ConcluirColheitaScreen> {
  late final _aprovada = TextEditingController(
      text: Base.d(widget.colheita['qtd_prevista']) > 0 ? fmtCampo(Base.d(widget.colheita['qtd_prevista'])) : '');
  final _refugo = TextEditingController();
  final _perdaAnormal = TextEditingController();
  final _motivo = TextEditingController();
  final _maoObra = TextEditingController();
  final _outros = TextEditingController();
  final List<_LinhaInsumo> _insumos = [];
  late String _data = widget.colheita['data'] as String;
  String? _validade;
  bool _salvando = false;

  @override
  Widget build(BuildContext context) {
    final o = widget.colheita;
    final validadePadrao = isoData(parseIso(_data).add(Duration(days: Base.i(o['validade_dias']))));
    return Scaffold(
      appBar: AppBar(title: Text('Registrar colheita ${o['id']}')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Text('${nomeComVariacao(o)} • talhão ${o['talhao']}', style: Theme.of(context).textTheme.titleMedium),
        const Secao('Quantidades'),
        CampoData('Data da colheita', _data, (v) => setState(() => _data = v ?? hojeIso())),
        CampoNumero('Quantidade aprovada (vai para o estoque)', _aprovada, sufixo: o['unidade'] as String?),
        Row(children: [
          Expanded(child: CampoNumero('Refugo normal', _refugo)),
          const SizedBox(width: 8),
          Expanded(child: CampoNumero('Perda anormal', _perdaAnormal)),
        ]),
        CampoTexto('Motivo do refugo / perdas', _motivo),
        CampoData('Validade do lote (padrão: ${dataBr(validadePadrao)})', _validade ?? validadePadrao,
            (v) => setState(() => _validade = v)),
        const Text(
          'Refugo normal (rachados, fora de padrão): fica absorvido no custo dos cocos aprovados. '
          'Perda anormal (chuva, praga, furto): seu custo vai para o resultado como perda.',
          style: TextStyle(fontSize: 12),
        ),
        const Secao('Custos da colheita'),
        CampoNumero('Mão de obra (apanhadores, diárias)', _maoObra, prefixo: 'R\$ '),
        CampoNumero('Outros (frete interno, diesel…)', _outros, prefixo: 'R\$ '),
        _blocoInsumos(context, _insumos, () => setState(() {}), titulo: 'Insumos usados (sacaria, combustível…)'),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _salvando
              ? null
              : () async {
                  setState(() => _salvando = true);
                  final ok = await executar(context, () async {
                    await S.campo.concluirColheita(
                      colheitaId: o['id'] as int,
                      qtdAprovada: parseNum(_aprovada.text),
                      refugo: parseNum(_refugo.text),
                      perdaAnormal: parseNum(_perdaAnormal.text),
                      motivoPerda: _motivo.text,
                      insumos: [for (final l in _insumos) InsumoUsado(itemId: l.item['id'] as int, quantidade: parseNum(l.qtd.text))],
                      maoObra: parseNum(_maoObra.text),
                      outrosCustos: parseNum(_outros.text),
                      validade: _validade ?? validadePadrao,
                      data: _data,
                    );
                  }, sucesso: 'Colheita registrada e estoque atualizado');
                  if (!mounted) return;
                  setState(() => _salvando = false);
                  if (ok) Navigator.pop(context, true);
                },
          child: const Padding(padding: EdgeInsets.all(12), child: Text('Concluir colheita')),
        ),
      ]),
    );
  }
}

// ---------------- Manejos ----------------

class _ListaManejos extends StatefulWidget {
  const _ListaManejos();
  @override
  State<_ListaManejos> createState() => _ListaManejosState();
}

class _ListaManejosState extends State<_ListaManejos> {
  int _v = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'manejo',
        onPressed: () async {
          await abrir(context, const ManejoFormScreen());
          if (mounted) setState(() => _v++);
        },
        icon: const Icon(Icons.add),
        label: const Text('Manejo'),
      ),
      body: Carregar<List<Map<String, Object?>>>(
        key: ValueKey(_v),
        futuro: () => S.campo.listarManejos(),
        builder: (context, lista, rec) {
          if (lista.isEmpty) {
            return const Vazio('Nenhum manejo. Registre adubações, pulverizações, roçagens e irrigações para custear a produção.');
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: lista.length,
            itemBuilder: (c, i) {
              final m = lista[i];
              final st = m['status'] as String;
              final apropriado = m['colheita_id'] != null;
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.spa_outlined),
                  title: Text('${CampoService.operacoes[m['operacao']] ?? m['operacao']} • ${m['talhao']}'),
                  subtitle: Text([
                    dataBr(m['data'] as String),
                    if ((m['descricao'] as String?)?.isNotEmpty == true) m['descricao'] as String,
                    brl(Base.d(m['custo_total'])),
                  ].join(' • ')),
                  trailing: Etiqueta(
                    st == 'cancelado' ? 'Cancelado' : (apropriado ? 'Colheita ${m['colheita_id']}' : 'A apropriar'),
                    cor: st == 'cancelado' ? Colors.red : (apropriado ? Colors.green.shade700 : Colors.orange.shade800),
                  ),
                  onTap: () async {
                    await _detalheManejo(context, m);
                    rec();
                  },
                  onLongPress: () async {
                    final op = await menuEditarExcluir(context,
                        podeEditar: st == 'ativo' && !apropriado, podeExcluir: !apropriado);
                    if (op == null || !context.mounted) return;
                    await _acaoManejo(context, m, op);
                    rec();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _detalheManejo(BuildContext context, Map<String, Object?> m) async {
    final ins = await S.campo.insumosDoManejo(m['id'] as int);
    if (!context.mounted) return;
    final pendente = m['status'] == 'ativo' && m['colheita_id'] == null;
    final podeExcluir = m['colheita_id'] == null;
    final acao = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(CampoService.operacoes[m['operacao']] ?? '${m['operacao']}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Talhão ${m['talhao']} • ${dataBr(m['data'] as String)}'),
            if (m['responsavel'] != null) Text('Responsável: ${m['responsavel']}'),
            if (m['descricao'] != null) Text('${m['descricao']}'),
            const SizedBox(height: 8),
            for (final i in ins)
              LinhaValor('${i['nome']} (${numero(Base.d(i['quantidade']))} ${i['unidade_consumo']})', brl(Base.d(i['custo_total']))),
            LinhaValor('Insumos', brl(Base.d(m['custo_insumos']))),
            LinhaValor('Mão de obra', brl(Base.d(m['custo_mao_obra']))),
            LinhaValor('Outros', brl(Base.d(m['custo_outros']))),
            LinhaValor('Total', brl(Base.d(m['custo_total'])), negrito: true),
            if (m['motivo_cancelamento'] != null) Text('Cancelado: ${m['motivo_cancelamento']}'),
            if (m['colheita_id'] != null)
              Text('Apropriado à colheita ${m['colheita_id']}: para editar ou excluir, exclua a colheita antes.',
                  style: const TextStyle(fontSize: 12)),
          ]),
        ),
        actions: [
          if (podeExcluir)
            TextButton(onPressed: () => Navigator.pop(c, 'excluir'), child: const Text('Excluir', style: TextStyle(color: Colors.red))),
          if (pendente) TextButton(onPressed: () => Navigator.pop(c, 'cancelar'), child: const Text('Cancelar manejo')),
          if (pendente) TextButton(onPressed: () => Navigator.pop(c, 'editar'), child: const Text('Editar')),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Fechar')),
        ],
      ),
    );
    if (acao == null || !context.mounted) return;
    await _acaoManejo(context, m, acao);
  }
}

/// Executa Editar / Excluir / Cancelar de um manejo.
Future<void> _acaoManejo(BuildContext context, Map<String, Object?> m, String acao) async {
  switch (acao) {
    case 'editar':
      await abrir(context, ManejoFormScreen(manejo: m));
    case 'excluir':
      if (!await confirmarExclusao(context, 'este manejo',
          detalhe: 'Os insumos aplicados voltam para o estoque.')) {
        return;
      }
      if (!context.mounted) return;
      await executar(context, () => S.campo.excluirManejo(m['id'] as int), sucesso: 'Manejo excluído e insumos devolvidos');
    case 'cancelar':
      final motivo = await pedirTexto(context, 'Cancelar manejo');
      if (motivo == null || !context.mounted) return;
      await executar(context, () => S.campo.cancelarManejo(m['id'] as int, motivo), sucesso: 'Manejo cancelado e insumos devolvidos');
  }
}

class ManejoFormScreen extends StatefulWidget {
  const ManejoFormScreen({super.key, this.talhao, this.manejo});
  final Map<String, Object?>? talhao;
  /// Manejo existente (modo edição).
  final Map<String, Object?>? manejo;
  @override
  State<ManejoFormScreen> createState() => _ManejoFormScreenState();
}

class _ManejoFormScreenState extends State<ManejoFormScreen> {
  late Map<String, Object?>? _talhao = widget.talhao;
  String _operacao = 'adubacao';
  String _data = hojeIso();
  final _desc = TextEditingController();
  final _resp = TextEditingController();
  final _maoObra = TextEditingController();
  final _outros = TextEditingController();
  final List<_LinhaInsumo> _insumos = [];
  bool _salvando = false;
  List<Map<String, Object?>> _insumosExistentes = [];

  bool get _edicao => widget.manejo != null;

  @override
  void initState() {
    super.initState();
    final m = widget.manejo;
    if (m != null) {
      _talhao = {'id': m['talhao_id'], 'nome': m['talhao']};
      _operacao = m['operacao'] as String;
      _data = m['data'] as String;
      _desc.text = (m['descricao'] as String?) ?? '';
      _resp.text = (m['responsavel'] as String?) ?? '';
      _maoObra.text = fmtCampo(Base.d(m['custo_mao_obra']));
      _outros.text = fmtCampo(Base.d(m['custo_outros']));
      S.campo.insumosDoManejo(m['id'] as int).then((l) {
        if (mounted) setState(() => _insumosExistentes = l);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_edicao ? 'Editar manejo' : 'Novo manejo'),
        actions: [
          if (_edicao)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Excluir',
              onPressed: () async {
                if (!await confirmarExclusao(context, 'este manejo', detalhe: 'Os insumos aplicados voltam para o estoque.')) return;
                if (!context.mounted) return;
                final ok = await executar(context, () => S.campo.excluirManejo(widget.manejo!['id'] as int), sucesso: 'Manejo excluído');
                if (ok && context.mounted) Navigator.pop(context, true);
              },
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.grid_on_outlined),
          title: Text(_talhao == null ? 'Selecionar talhão' : 'Talhão: ${_talhao!['nome']}'),
          trailing: _edicao ? null : const Icon(Icons.search),
          onTap: _edicao
              ? null
              : () async {
                  final t = await escolherTalhao(context);
                  if (t != null) setState(() => _talhao = t);
                },
        ),
        CampoLista<String>('Operação', _operacao, CampoService.operacoes, (v) => setState(() => _operacao = v ?? 'outro')),
        CampoData('Data', _data, (v) => setState(() => _data = v ?? hojeIso())),
        CampoTexto('Descrição (ex.: NPK 20-05-20, 1 kg por planta)', _desc),
        CampoTexto('Responsável', _resp),
        if (_edicao) ...[
          const Secao('Insumos aplicados'),
          if (_insumosExistentes.isEmpty) const Text('Nenhum insumo.', style: TextStyle(fontSize: 12, color: Colors.grey)),
          for (final i in _insumosExistentes)
            LinhaValor('${i['nome']} (${numero(Base.d(i['quantidade']))} ${i['unidade_consumo']})', brl(Base.d(i['custo_total']))),
          const Text('Para corrigir os insumos, exclua este manejo (eles voltam ao estoque) e lance de novo.',
              style: TextStyle(fontSize: 12)),
        ] else
          _blocoInsumos(context, _insumos, () => setState(() {}), titulo: 'Insumos aplicados (baixa do estoque)'),
        const Secao('Outros custos'),
        CampoNumero('Mão de obra (diárias, empreita)', _maoObra, prefixo: 'R\$ '),
        CampoNumero('Outros (combustível, aluguel de máquina…)', _outros, prefixo: 'R\$ '),
        const Text(
          'O custo fica acumulado no talhão e é apropriado aos cocos na próxima colheita registrada.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _salvando
              ? null
              : () async {
                  if (_talhao == null) {
                    mostrarErro(context, 'Selecione o talhão');
                    return;
                  }
                  setState(() => _salvando = true);
                  final ok = await executar(context, () async {
                    if (_edicao) {
                      await S.campo.editarManejo(
                        manejoId: widget.manejo!['id'] as int,
                        data: _data,
                        operacao: _operacao,
                        descricao: _desc.text,
                        responsavel: _resp.text,
                        maoObra: parseNum(_maoObra.text),
                        outrosCustos: parseNum(_outros.text),
                      );
                      return;
                    }
                    await S.campo.registrarManejo(
                      talhaoId: _talhao!['id'] as int,
                      data: _data,
                      operacao: _operacao,
                      descricao: _desc.text,
                      responsavel: _resp.text,
                      insumos: [for (final l in _insumos) InsumoUsado(itemId: l.item['id'] as int, quantidade: parseNum(l.qtd.text))],
                      maoObra: parseNum(_maoObra.text),
                      outrosCustos: parseNum(_outros.text),
                    );
                  }, sucesso: _edicao ? 'Manejo atualizado' : 'Manejo registrado');
                  if (!mounted) return;
                  setState(() => _salvando = false);
                  if (ok) Navigator.pop(context, true);
                },
          child: const Padding(padding: EdgeInsets.all(12), child: Text('Salvar manejo')),
        ),
      ]),
    );
  }
}

// ---------------- Talhões ----------------

class _ListaTalhoes extends StatefulWidget {
  const _ListaTalhoes();
  @override
  State<_ListaTalhoes> createState() => _ListaTalhoesState();
}

class _ListaTalhoesState extends State<_ListaTalhoes> {
  int _v = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'talhao',
        onPressed: () async {
          await abrir(context, const TalhaoFormScreen());
          if (mounted) setState(() => _v++);
        },
        icon: const Icon(Icons.add),
        label: const Text('Talhão'),
      ),
      body: Carregar<List<Map<String, Object?>>>(
        key: ValueKey(_v),
        futuro: () => S.campo.listarTalhoes(),
        builder: (context, lista, rec) {
          if (lista.isEmpty) return const Vazio('Nenhum talhão. Cadastre as áreas do coqueiral para registrar manejos e colheitas.');
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: lista.length,
            itemBuilder: (c, i) => _CartaoTalhao(lista[i], () async {
              await abrir(context, TalhaoFormScreen(talhaoId: lista[i]['id'] as int));
              rec();
            }, () async {
              final op = await menuEditarExcluir(context);
              if (op == null || !context.mounted) return;
              if (op == 'editar') await abrir(context, TalhaoFormScreen(talhaoId: lista[i]['id'] as int));
              if (op == 'excluir' && await confirmarExclusao(context, 'o talhão "${lista[i]['nome']}"') && context.mounted) {
                await executar(context, () => S.campo.excluirTalhao(lista[i]['id'] as int), sucesso: 'Talhão excluído');
              }
              rec();
            }),
          );
        },
      ),
    );
  }
}

class _CartaoTalhao extends StatelessWidget {
  const _CartaoTalhao(this.t, this.onTap, this.onLongPress);
  final Map<String, Object?> t;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final ativo = Base.i(t['ativo']) == 1;
    return Card(
      child: ListTile(
        leading: Icon(Icons.park_outlined, color: ativo ? Colors.green.shade700 : Colors.grey),
        title: Text('${t['nome']}${ativo ? '' : ' (inativo)'}'),
        subtitle: Text([
          if ((t['variedade'] as String?)?.isNotEmpty == true) t['variedade'] as String,
          '${numero(Base.d(t['area_ha']), casas: 2)} ha • ${Base.i(t['qtd_plantas'])} plantas',
          'Colhido 12 meses: ${numero(Base.d(t['colhido_12m']))}',
          if (t['ultima_colheita'] != null) 'Última colheita ${dataBr(t['ultima_colheita'] as String)}',
        ].join('\n')),
        isThreeLine: true,
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Text('A apropriar', style: TextStyle(fontSize: 11)),
          Text(brl(Base.d(t['custo_pendente'])), style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}

/// Tela independente (usada em Mais > Cadastros).
class TalhoesScreen extends StatelessWidget {
  const TalhoesScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Talhões')),
        body: const _ListaTalhoes(),
      );
}

class TalhaoFormScreen extends StatefulWidget {
  const TalhaoFormScreen({super.key, this.talhaoId});
  final int? talhaoId;
  @override
  State<TalhaoFormScreen> createState() => _TalhaoFormScreenState();
}

class _TalhaoFormScreenState extends State<TalhaoFormScreen> {
  final _nome = TextEditingController();
  final _area = TextEditingController();
  final _plantas = TextEditingController();
  final _variedade = TextEditingController();
  final _obs = TextEditingController();
  String? _plantio;
  bool _ativo = true;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (widget.talhaoId != null) {
      final t = (await banco.query('talhoes', where: 'id = ?', whereArgs: [widget.talhaoId])).first;
      _nome.text = t['nome'] as String;
      _area.text = fmtCampo(Base.d(t['area_ha']));
      _plantas.text = '${Base.i(t['qtd_plantas'])}';
      _variedade.text = (t['variedade'] as String?) ?? '';
      _obs.text = (t['obs'] as String?) ?? '';
      _plantio = t['data_plantio'] as String?;
      _ativo = Base.i(t['ativo']) == 1;
    }
    if (mounted) setState(() => _ok = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ok) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final area = parseNum(_area.text);
    final plantas = parseNum(_plantas.text);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.talhaoId == null ? 'Novo talhão' : 'Editar talhão'),
        actions: [
          if (widget.talhaoId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Excluir',
              onPressed: () async {
                if (!await confirmarExclusao(context, 'este talhão')) return;
                if (!context.mounted) return;
                final ok = await executar(context, () => S.campo.excluirTalhao(widget.talhaoId!), sucesso: 'Talhão excluído');
                if (ok && context.mounted) Navigator.pop(context, true);
              },
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: () async {
              final ok = await executar(context, () async {
                await S.campo.salvarTalhao({
                  'nome': _nome.text,
                  'area_ha': parseNum(_area.text),
                  'qtd_plantas': parseNum(_plantas.text).round(),
                  'variedade': _variedade.text.trim().isEmpty ? null : _variedade.text.trim(),
                  'data_plantio': _plantio,
                  'obs': _obs.text.trim().isEmpty ? null : _obs.text.trim(),
                  'ativo': _ativo ? 1 : 0,
                }, id: widget.talhaoId);
              }, sucesso: 'Talhão salvo');
              if (ok && context.mounted) Navigator.pop(context, true);
            },
            child: const Text('Salvar'),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        CampoTexto('Nome (ex.: Talhão 1 - Baixada)', _nome),
        CampoTexto('Variedade (ex.: Anão verde, Gigante, Híbrido)', _variedade),
        CampoNumero('Área', _area, sufixo: 'ha', onChanged: (_) => setState(() {})),
        CampoNumero('Quantidade de plantas', _plantas, inteiro: true, onChanged: (_) => setState(() {})),
        if (area > 0 && plantas > 0)
          Text('Densidade: ${numero(plantas / area, casas: 0)} plantas/ha', style: const TextStyle(fontSize: 12)),
        CampoData('Data de plantio', _plantio, (v) => setState(() => _plantio = v), permiteVazio: true),
        CampoTexto('Observações', _obs, linhas: 3),
        SwitchListTile(
            contentPadding: EdgeInsets.zero, value: _ativo, onChanged: (v) => setState(() => _ativo = v), title: const Text('Ativo')),
        if (widget.talhaoId != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.spa_outlined),
            label: const Text('Registrar manejo neste talhão'),
            onPressed: () async {
              final t = (await banco.query('talhoes', where: 'id = ?', whereArgs: [widget.talhaoId])).first;
              if (!context.mounted) return;
              await abrir(context, ManejoFormScreen(talhao: t));
            },
          ),
        ],
      ]),
    );
  }
}
