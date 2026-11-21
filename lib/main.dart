import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'data/db.dart';
import 'services/base.dart';
import 'services/demo_service.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/licenca_screen.dart';
import 'ui/screens/mais_screen.dart';
import 'ui/screens/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'pt_BR';
  await initializeDateFormatting('pt_BR');
  await AppDb.abrir();
  runApp(const GestorApp());
}

class GestorApp extends StatefulWidget {
  const GestorApp({super.key});

  static final ValueNotifier<int> reiniciar = ValueNotifier(0);

  @override
  State<GestorApp> createState() => _GestorAppState();
}

class _GestorAppState extends State<GestorApp> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: GestorApp.reiniciar,
      builder: (context, v, _) => MaterialApp(
        key: ValueKey(v),
        title: 'Gestor de Produção e Comercialização de Coco',
        debugShowCheckedModeBanner: false,
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF2E6B3A),
          useMaterial3: true,
          inputDecorationTheme: const InputDecorationTheme(isDense: true),
        ),
        home: const PortaoLicenca(child: _Inicio()),
      ),
    );
  }
}


class _Inicio extends StatelessWidget {
  const _Inicio();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
        valueListenable: ContaLocal.sessao,
        builder: (context, email, _) =>
            email == null ? const _Acesso() : const _Negocio(),
      );
}

class _Acesso extends StatefulWidget {
  const _Acesso();

  @override
  State<_Acesso> createState() => _AcessoState();
}

class _AcessoState extends State<_Acesso> {
  late Future<bool> _contaExiste = ContaLocal.existe();

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFEEF4E6),
        appBar: AppBar(
          title: const Text('Gestor do Coco'),
          backgroundColor: const Color(0xFF2F5D34),
          foregroundColor: Colors.white,
        ),
        body: FutureBuilder<bool>(
          future: _contaExiste,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: TextButton(
                  onPressed: () => setState(() => _contaExiste = ContaLocal.existe()),
                  child: const Text('Erro ao consultar a conta. Tentar novamente'),
                ),
              );
            }
            return FormularioConta(!snapshot.requireData);
          },
        ),
      );
}

class _Negocio extends StatefulWidget {
  const _Negocio();

  @override
  State<_Negocio> createState() => _NegocioState();
}

class _NegocioState extends State<_Negocio> {
  late final _preparacao = _preparar();
  bool _continuar = false;

  Future<({bool configurado, bool erroExemplos})> _preparar() async {
    final db = AppDb.instance.db;
    final nome = await Base(db).config('nome_negocio');
    if (nome == null || nome.trim().isEmpty) {
      return (configurado: false, erroExemplos: false);
    }
    final temDados = (await db.rawQuery('''
      SELECT EXISTS (SELECT 1 FROM itens)
          OR EXISTS (SELECT 1 FROM clientes)
          OR EXISTS (SELECT 1 FROM fornecedores)
          OR EXISTS (SELECT 1 FROM compras)
          OR EXISTS (SELECT 1 FROM pedidos)
          OR EXISTS (SELECT 1 FROM colheitas)
          OR EXISTS (SELECT 1 FROM talhoes)
          OR EXISTS (SELECT 1 FROM titulos)
          OR EXISTS (SELECT 1 FROM movimentos_financeiros)
          OR EXISTS (SELECT 1 FROM lancamentos_resultado) AS resultado
    ''')).single['resultado'] == 1;
    if (!temDados) {
      try {
        await DemoService(db).carregar();
      } on Exception catch (erro, pilha) {
        debugPrint('Falha ao carregar exemplos: $erro\n$pilha');
        return (configurado: true, erroExemplos: true);
      }
    }
    return (configurado: true, erroExemplos: false);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _preparacao,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return const Scaffold(
              body: Center(child: Text('Erro ao abrir os dados. Feche e abra o aplicativo novamente.')),
            );
          }
          final dados = snapshot.requireData;
          if (!dados.configurado) return const OnboardingScreen();
          if (dados.erroExemplos && !_continuar) {
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => setState(() => _continuar = true),
                  child: const Text('A carga de exemplos falhou. Ir para Início'),
                ),
              ),
            );
          }
          return const HomeScreen();
        },
      );
}
