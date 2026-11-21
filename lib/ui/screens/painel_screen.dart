import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../services/base.dart';
import '../widgets/comum.dart';
import 'pedido_detalhe_screen.dart';

const _fundoPainel = Color(0xFFEEF4E6);
const _barraPainel = Color(0xFF2F5D34);
const _bordaQuadro = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(12)),
  side: BorderSide(color: Color(0xFFE1CCD8)),
);

class PainelScreen extends StatelessWidget {
  const PainelScreen({super.key, required this.irPara});
  final ValueChanged<int> irPara;

  Future<Map<String, Object?>> _dados() async {
    final hoje = DateTime.now();
    final ini = isoData(inicioMes(hoje));
    final fim = isoData(fimMes(hoje));
    final dre = await S.dre.calcular(ini, fim);
    return {
      'negocio': await Base(banco).config('nome_negocio'),
      'mes': nomeMes(hoje),
      'faturamento': dre.receitaBruta,
      'resultado': dre.resultadoLiquido,
      'caixa': await S.fin.saldo(),
      'receber': await S.fin.totalAberto('receber'),
      'pagar': await S.fin.totalAberto('pagar'),
      'entregas': await S.pedidos.proximasEntregas(limite: 8),
      'alertas': await S.estoque.alertas(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundoPainel,
      appBar: AppBar(
        title: const Text('Painel'),
        backgroundColor: _barraPainel,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: Carregar<Map<String, Object?>>(
        futuro: _dados,
        builder: (context, d, recarregar) {
          final alertas = d['alertas'] as Map<String, List<Map<String, Object?>>>;
          final entregas = d['entregas'] as List<Map<String, Object?>>;
          final mes = d['mes'] as String;
          final hojeBr = dataBrDe(DateTime.now());
          return RefreshIndicator(
            onRefresh: () async => recarregar(),
            child: ListView(padding: const EdgeInsets.all(12), children: [
              Text((d['negocio'] as String?) ?? '', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.9,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  _Indicador('Faturamento', brl(d['faturamento'] as double), 'Receita bruta • $mes', Icons.trending_up),
                  _Indicador('Resultado líquido', brl(d['resultado'] as double), 'DRE • $mes', Icons.analytics_outlined,
                      cor: (d['resultado'] as double) < 0 ? Colors.red.shade800 : Colors.green.shade800),
                  _Indicador('Saldo de caixa', brl(d['caixa'] as double), 'Todas as contas • $hojeBr', Icons.account_balance_wallet_outlined),
                  _Indicador('A receber', brl(d['receber'] as double), 'Em aberto • $hojeBr', Icons.call_received),
                  _Indicador('A pagar', brl(d['pagar'] as double), 'Em aberto • $hojeBr', Icons.call_made),
                  _Indicador('Entregas', '${entregas.length}', 'Pedidos em aberto', Icons.local_shipping_outlined),
                ],
              ),
              Secao('Próximas entregas', acao: TextButton(onPressed: () => irPara(1), child: const Text('Ver pedidos'))),
              if (entregas.isEmpty) const Vazio('Nenhuma entrega pendente.'),
              for (final p in entregas)
                Card(
                  color: Colors.white,
                  surfaceTintColor: Colors.transparent,
                  shape: _bordaQuadro,
                  child: ListTile(
                    title: Text('#${p['id']} • ${(p['cliente'] as String?) ?? 'Sem cliente'}'),
                    subtitle: Text('${dataBr(p['data_entrega'] as String?)} ${(p['hora_entrega'] as String?) ?? ''}'),
                    trailing: Etiqueta(_rotuloStatus(p['status'] as String)),
                    onTap: () async {
                      await abrir(context, PedidoDetalheScreen(pedidoId: p['id'] as int));
                      recarregar();
                    },
                  ),
                ),
              const Secao('Alertas de estoque e validade'),
              if (alertas.values.every((l) => l.isEmpty)) const Vazio('Nenhum alerta.'),
              for (final a in alertas['vencidos']!)
                _alerta(Icons.dangerous_outlined, Colors.red,
                    '${_nome(a)} – lote ${a['codigo']} VENCIDO em ${dataBr(a['validade'] as String)}',
                    'Saldo ${numero(Base.d(a['saldo']))} bloqueado. Registre a perda no Estoque.'),
              for (final a in alertas['vencendo']!)
                _alerta(Icons.schedule, Colors.orange.shade800,
                    '${_nome(a)} – lote ${a['codigo']} vence em ${dataBr(a['validade'] as String)}',
                    'Saldo ${numero(Base.d(a['saldo']))}'),
              for (final a in alertas['minimo']!)
                _alerta(Icons.warning_amber, Colors.amber.shade900, '${_nome(a)} abaixo do mínimo',
                    'Saldo válido ${numero(Base.d(a['fisico']) - Base.d(a['vencido']))} ${a['unidade']} • mínimo ${numero(Base.d(a['estoque_minimo']))}'),
            ]),
          );
        },
      ),
    );
  }

  static String _nome(Map<String, Object?> a) =>
      a['variacao'] != null && a['variacao'] != 'Padrão' ? '${a['nome']} - ${a['variacao']}' : a['nome'] as String;

  Widget _alerta(IconData i, Color c, String t, String s) => Card(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: _bordaQuadro,
        child: ListTile(dense: true, leading: Icon(i, color: c), title: Text(t), subtitle: Text(s)),
      );
}

String _rotuloStatus(String s) => const {
      'orcamento': 'Orçamento',
      'confirmado': 'Confirmado',
      'em_producao': 'Em colheita',
      'pronto': 'Pronto',
      'entregue': 'Entregue',
      'cancelado': 'Cancelado',
    }[s] ??
    s;

class _Indicador extends StatelessWidget {
  const _Indicador(this.titulo, this.valor, this.periodo, this.icone, {this.cor});
  final String titulo, valor, periodo;
  final IconData icone;
  final Color? cor;
  @override
  Widget build(BuildContext context) => Card(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: _bordaQuadro,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Icon(icone, size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 4),
              Expanded(child: Text(titulo, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
            ]),
            FittedBox(
              child: Text(valor, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cor)),
            ),
            Text(periodo, style: TextStyle(fontSize: 10, color: Colors.grey.shade700), overflow: TextOverflow.ellipsis),
          ]),
        ),
      );
}
