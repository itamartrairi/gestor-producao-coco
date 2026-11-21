import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../services/base.dart';
import '../../services/pedido_service.dart';
import '../widgets/comum.dart';
import '../widgets/pagamentos_dialog.dart';
import '../widgets/seletores.dart';

class _LinhaItem {
  _LinhaItem(this.itemId, this.variacaoId, this.nome, this.unidade, double preco, {double qtd = 1, String? pers})
      : qtd = TextEditingController(text: fmtCampo(qtd)),
        preco = TextEditingController(text: fmtCampo(preco)),
        pers = TextEditingController(text: pers ?? '');
  final int itemId, variacaoId;
  final String nome, unidade;
  final TextEditingController qtd, preco, pers;
  double get total => parseNum(qtd.text) * parseNum(preco.text);
}

/// Cadastro/edição de pedido. Para "balcao", finaliza a venda com pagamento.
class PedidoFormScreen extends StatefulWidget {
  const PedidoFormScreen({super.key, required this.tipo, this.pedidoId});
  final String tipo;
  final int? pedidoId;
  @override
  State<PedidoFormScreen> createState() => _PedidoFormScreenState();
}

class _PedidoFormScreenState extends State<PedidoFormScreen> {
  late String _tipo = widget.tipo;
  int? _clienteId;
  String? _clienteNome;
  final _canal = TextEditingController();
  String _dataPedido = hojeIso();
  String? _dataEntrega = hojeIso();
  final _hora = TextEditingController();
  final _desconto = TextEditingController();
  final _frete = TextEditingController();
  final _pers = TextEditingController();
  final _obs = TextEditingController();
  final _itens = <_LinhaItem>[];
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    if (_tipo == 'balcao') _canal.text = 'Balcão';
    if (widget.pedidoId != null) _carregar();
  }

  Future<void> _carregar() async {
    final p = (await banco.query('pedidos', where: 'id = ?', whereArgs: [widget.pedidoId])).first;
    final itens = await S.pedidos.itens(widget.pedidoId!);
    String? cli;
    if (p['cliente_id'] != null) {
      cli = (await banco.query('clientes', where: 'id = ?', whereArgs: [p['cliente_id']])).first['nome'] as String;
    }
    setState(() {
      _tipo = p['tipo'] as String;
      _clienteId = p['cliente_id'] as int?;
      _clienteNome = cli;
      _canal.text = (p['canal'] as String?) ?? '';
      _dataPedido = p['data_pedido'] as String;
      _dataEntrega = p['data_entrega'] as String?;
      _hora.text = (p['hora_entrega'] as String?) ?? '';
      _desconto.text = fmtCampo(Base.d(p['desconto']));
      _frete.text = fmtCampo(Base.d(p['frete']));
      _pers.text = (p['personalizacao'] as String?) ?? '';
      _obs.text = (p['obs'] as String?) ?? '';
      for (final i in itens) {
        _itens.add(_LinhaItem(i['item_id'] as int, i['variacao_id'] as int, nomeComVariacao(i), (i['unidade_venda'] as String?) ?? 'un',
            Base.d(i['preco_unitario']), qtd: Base.d(i['quantidade']), pers: i['personalizacao'] as String?));
      }
    });
  }

  double get _subtotal => _itens.fold(0.0, (s, i) => s + i.total);
  double get _total => r2(_subtotal - parseNum(_desconto.text) + parseNum(_frete.text));

  List<ItemPedido> _montarItens() => [
        for (final i in _itens)
          ItemPedido(
            itemId: i.itemId,
            variacaoId: i.variacaoId,
            quantidade: parseNum(i.qtd.text),
            precoUnitario: parseNum(i.preco.text),
            unidadeVenda: i.unidade,
            personalizacao: i.pers.text.isEmpty ? null : i.pers.text,
          ),
      ];

  Future<void> _salvar() async {
    if (_salvando) return;
    setState(() => _salvando = true);
    try {
      if (_tipo == 'balcao') {
        final pags = await coletarPagamentos(context, valorSugerido: _total, titulo: 'Receber venda', exigirTotal: false);
        if (pags == null) return;
        final id = await S.pedidos.vendaBalcao(
          clienteId: _clienteId,
          canal: _canal.text.isEmpty ? 'Balcão' : _canal.text,
          data: _dataPedido,
          desconto: parseNum(_desconto.text),
          itens: _montarItens(),
          pagamentos: pags,
        );
        if (mounted) {
          mostrarOk(context, 'Venda #$id registrada');
          Navigator.pop(context, id);
        }
      } else {
        final id = await S.pedidos.salvar(
          id: widget.pedidoId,
          tipo: _tipo,
          clienteId: _clienteId,
          canal: _canal.text.isEmpty ? null : _canal.text,
          dataPedido: _dataPedido,
          dataEntrega: _dataEntrega,
          horaEntrega: _hora.text.isEmpty ? null : _hora.text,
          desconto: parseNum(_desconto.text),
          frete: parseNum(_frete.text),
          personalizacao: _pers.text.isEmpty ? null : _pers.text,
          obs: _obs.text.isEmpty ? null : _obs.text,
          itens: _montarItens(),
        );
        if (mounted) Navigator.pop(context, id);
      }
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final balcao = _tipo == 'balcao';
    return Scaffold(
      appBar: AppBar(title: Text(balcao ? 'Venda à vista' : (widget.pedidoId == null ? 'Novo pedido' : 'Editar pedido #${widget.pedidoId}'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            icon: Icon(balcao ? Icons.point_of_sale : Icons.save),
            label: Text(balcao ? 'Receber ${brl(_total)}' : 'Salvar orçamento • ${brl(_total)}'),
            onPressed: _salvando ? null : _salvar,
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        if (!balcao)
          CampoLista<String>('Tipo', _tipo, const {'encomenda': 'Encomenda', 'entrega': 'Entrega'}, (v) => setState(() => _tipo = v!)),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_outline),
          title: Text(_clienteNome ?? (balcao ? 'Cliente (opcional)' : 'Selecionar cliente')),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (_clienteId != null) IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _clienteId = _clienteNome = null)),
            IconButton(
              icon: const Icon(Icons.person_add_alt),
              tooltip: 'Novo cliente',
              onPressed: () async {
                final nome = await pedirTexto(context, 'Novo cliente', rotulo: 'Nome');
                if (nome == null || nome.isEmpty) return;
                final id = await S.cad.salvarSimples('clientes', {'nome': nome});
                setState(() {
                  _clienteId = id;
                  _clienteNome = nome;
                });
              },
            ),
          ]),
          onTap: () async {
            final c = await escolherCliente(context);
            if (c != null) {
              setState(() {
                _clienteId = c['id'] as int;
                _clienteNome = c['nome'] as String;
              });
            }
          },
        ),
        CampoTexto('Canal de venda', _canal, dica: 'Atravessador, distribuidora, feira, barraca de praia, WhatsApp…'),
        CampoData(balcao ? 'Data da venda' : 'Data do pedido', _dataPedido, (v) => setState(() => _dataPedido = v ?? hojeIso())),
        if (!balcao)
          Row(children: [
            Expanded(child: CampoData('Data de entrega', _dataEntrega, (v) => setState(() => _dataEntrega = v))),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: TextField(
                  controller: _hora,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Horário', border: OutlineInputBorder(), isDense: true, suffixIcon: Icon(Icons.schedule, size: 18)),
                  onTap: () async {
                    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 14, minute: 0));
                    if (t != null) {
                      _hora.text = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                    }
                  },
                ),
              ),
            ),
          ]),
        Secao('Produtos',
            acao: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Adicionar'),
              onPressed: () async {
                final p = await escolherProduto(context);
                if (p == null) return;
                setState(() => _itens.add(_LinhaItem(p['item_id'] as int, p['variacao_id'] as int, nomeComVariacao(p),
                    (p['unidade_venda'] as String?) ?? 'un', Base.d(p['preco_venda']))));
              },
            )),
        if (_itens.isEmpty) const Vazio('Adicione os produtos do pedido.'),
        for (var i = 0; i < _itens.length; i++)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 4, 8),
              child: Column(children: [
                Row(children: [
                  Expanded(child: Text(_itens[i].nome, style: const TextStyle(fontWeight: FontWeight.w600))),
                  IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => _itens.removeAt(i))),
                ]),
                Row(children: [
                  Expanded(child: CampoNumero('Qtd', _itens[i].qtd, sufixo: _itens[i].unidade, onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 6),
                  Expanded(child: CampoNumero('Preço unit.', _itens[i].preco, prefixo: 'R\$ ', onChanged: (_) => setState(() {}))),
                ]),
                if (!balcao) CampoTexto('Observação do item (classificação, carga)', _itens[i].pers),
                Align(alignment: Alignment.centerRight, child: Text(brl(_itens[i].total))),
              ]),
            ),
          ),
        const Secao('Valores'),
        LinhaValor('Subtotal', brl(_subtotal)),
        Row(children: [
          Expanded(child: CampoNumero('Desconto', _desconto, prefixo: 'R\$ ', onChanged: (_) => setState(() {}))),
          if (!balcao) const SizedBox(width: 6),
          if (!balcao) Expanded(child: CampoNumero('Frete', _frete, prefixo: 'R\$ ', onChanged: (_) => setState(() {}))),
        ]),
        LinhaValor('Total', brl(_total), negrito: true),
        if (!balcao) ...[
          const Secao('Detalhes'),
          CampoTexto('Instruções de entrega (local, carga, veículo)', _pers, linhas: 2),
          CampoTexto('Observações', _obs, linhas: 2),
        ],
        const SizedBox(height: 40),
      ]),
    );
  }
}
