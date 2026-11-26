import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/base.dart';
import '../widgets/comum.dart';
import '../widgets/rodape.dart';
import '../widgets/logo.dart';

import 'campo_screen.dart';
import 'estoque_screen.dart';
import 'mais_screen.dart';
import 'painel_screen.dart';
import 'pedidos_screen.dart';

/// Navegação inferior: Início, Painel, Pedidos, Campo, Estoque e Mais.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _aba = 0;
  int _versao = 0;

  void _selecionarAba(int indice) => setState(() {
        _aba = indice;
        _versao++;
      });

  @override
  Widget build(BuildContext context) {
    final telas = [
      _InicioScreen(key: ValueKey('inicio$_versao'), abrirPainel: () => _selecionarAba(1)),
      PainelScreen(key: ValueKey('p$_versao'), irPara: (i) => _selecionarAba(i + 1)),
      PedidosScreen(key: ValueKey('ped$_versao')),
      CampoScreen(key: ValueKey('campo$_versao')),
      EstoqueScreen(key: ValueKey('est$_versao')),
      const MaisScreen(),
    ];
    return Scaffold(
      body: telas[_aba],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _aba,
        onDestinationSelected: _selecionarAba,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Início'),
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Painel'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Pedidos'),
          NavigationDestination(icon: Icon(Icons.agriculture_outlined), selectedIcon: Icon(Icons.agriculture), label: 'Campo'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Estoque'),
          NavigationDestination(icon: Icon(Icons.menu), label: 'Mais'),
        ],
      ),
    );
  }
}

class _InicioScreen extends StatelessWidget {
  const _InicioScreen({super.key, required this.abrirPainel});

  final VoidCallback abrirPainel;

  Future<({String nome, Uint8List? logo})> _dados() async => (
        nome: await Base(banco).config('nome_negocio') ?? '',
        logo: await Logo.bytes(),
      );

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFEEF4E6),
      appBar: AppBar(
        title: const Text('Início'),
        backgroundColor: const Color(0xFF2F5D34),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: Carregar<({String nome, Uint8List? logo})>(
        futuro: _dados,
        builder: (context, dados, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    if (dados.logo case final caminho?)
                      Image.memory(
                        caminho,
                        height: 88,
                        fit: BoxFit.contain,
                        semanticLabel: 'Logotipo da empresa',
                        errorBuilder: (_, error, stackTrace) =>
                            const Icon(Icons.storefront_outlined, size: 56),
                      )
                    else
                      Icon(Icons.storefront_outlined, size: 56, color: tema.colorScheme.primary),
                    const SizedBox(height: 12),
                    if (dados.nome.isNotEmpty)
                      Text(
                        dados.nome,
                        textAlign: TextAlign.center,
                        style: tema.textTheme.headlineSmall,
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Gestor de Produção e Comercialização de Coco',
                      textAlign: TextAlign.center,
                      style: tema.textTheme.titleMedium?.copyWith(
                        color: tema.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                _Ilustracao(icone: Icons.park_outlined, rotulo: 'Coqueiral', cor: Color(0xFFDCEFD9)),
                SizedBox(width: 8),
                _Ilustracao(icone: Icons.agriculture_outlined, rotulo: 'Colheita', cor: Color(0xFFF3E7CF)),
                SizedBox(width: 8),
                _Ilustracao(icone: Icons.local_shipping_outlined, rotulo: 'Vendas', cor: Color(0xFFDDEBEA)),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: abrirPainel,
              icon: const Icon(Icons.dashboard_outlined),
              label: const Text('Abrir painel'),
            ),
            const RodapeIG(),
          ],
        ),
      ),
    );
  }
}

class _Ilustracao extends StatelessWidget {
  const _Ilustracao({
    required this.icone,
    required this.rotulo,
    required this.cor,
  });

  final IconData icone;
  final String rotulo;
  final Color cor;

  @override
  Widget build(BuildContext context) => Expanded(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: cor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            child: Column(
              children: [
                Icon(icone, size: 32, color: const Color(0xFF2F5D34)),
                const SizedBox(height: 6),
                Text(rotulo, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
}
