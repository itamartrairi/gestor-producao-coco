import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/licenca.dart';
import '../../core/licenca_config.dart';

String _dataBr(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Só deixa usar o app com licença válida. Mostra um aviso quando faltam
/// 7 dias ou menos para vencer.
class PortaoLicenca extends StatefulWidget {
  const PortaoLicenca({super.key, required this.child});
  final Widget child;

  /// Avisa o portão para conferir de novo (após ativar/renovar).
  static final ValueNotifier<int> reconferir = ValueNotifier(0);

  @override
  State<PortaoLicenca> createState() => _PortaoLicencaState();
}

class _PortaoLicencaState extends State<PortaoLicenca> {
  late Future<StatusLicenca> _status = LicencaLocal.verificar();
  bool _avisoFechado = false;

  @override
  void initState() {
    super.initState();
    PortaoLicenca.reconferir.addListener(_conferir);
  }

  @override
  void dispose() {
    PortaoLicenca.reconferir.removeListener(_conferir);
    super.dispose();
  }

  void _conferir() => setState(() => _status = LicencaLocal.verificar());

  @override
  Widget build(BuildContext context) => FutureBuilder<StatusLicenca>(
        future: _status,
        builder: (context, s) {
          if (s.hasError) {
            return Scaffold(body: Center(child: Text('Erro ao conferir a licença: ${s.error}')));
          }
          if (!s.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          final st = s.data!;
          if (!st.valida) return LicencaScreen(status: st, bloqueio: true);
          if (!st.vencendo || _avisoFechado) return widget.child;
          return Column(children: [
            Material(
              color: Colors.orange.shade100,
              child: SafeArea(
                bottom: false,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.warning_amber_rounded, color: Colors.deepOrange),
                  title: Text(st.diasRestantes == 0
                      ? 'A licença vence hoje.'
                      : 'A licença vence em ${st.diasRestantes} dia(s), em ${_dataBr(st.validade!)}.'),
                  subtitle: const Text('Toque para renovar.'),
                  trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _avisoFechado = true)),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LicencaScreen(status: st))),
                ),
              ),
            ),
            Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: widget.child)),
          ]);
        },
      );
}

/// Tela de ativação/renovação: mostra o número de instalação e recebe o código.
class LicencaScreen extends StatefulWidget {
  const LicencaScreen({super.key, required this.status, this.bloqueio = false});
  final StatusLicenca status;
  final bool bloqueio;
  @override
  State<LicencaScreen> createState() => _LicencaScreenState();
}

class _LicencaScreenState extends State<LicencaScreen> {
  final _codigo = TextEditingController();
  bool _ativando = false;
  String? _erro;

  Future<void> _ativar() async {
    setState(() {
      _ativando = true;
      _erro = null;
    });
    try {
      final st = await LicencaLocal.ativar(_codigo.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(st.permanente ? 'App ativado sem prazo.' : 'App ativado até ${_dataBr(st.validade!)}.')));
      PortaoLicenca.reconferir.value++;
      if (!widget.bloqueio && mounted) Navigator.of(context).pop(true);
    } on FormatException catch (e) {
      setState(() => _erro = e.message);
    } catch (e) {
      setState(() => _erro = 'Erro: $e');
    } finally {
      if (mounted) setState(() => _ativando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.status;
    final tema = Theme.of(context);
    final instalacao = numeroInstalacao(st.instalacao);
    String situacao;
    Color cor;
    if (st.relogioAtrasado) {
      situacao = 'A data do celular está anterior à última utilização. Acerte a data e a hora do aparelho.';
      cor = Colors.red;
    } else if (st.validade == null) {
      situacao = 'Este aparelho ainda não foi ativado.';
      cor = Colors.orange.shade800;
    } else if (st.diasRestantes < 0) {
      situacao = 'A licença venceu em ${_dataBr(st.validade!)}. Seus dados estão guardados; renove para continuar.';
      cor = Colors.red;
    } else if (st.permanente) {
      situacao = 'Licença ativa, sem prazo de validade.';
      cor = Colors.green.shade700;
    } else {
      situacao = 'Licença ativa até ${_dataBr(st.validade!)} (${st.diasRestantes} dia(s)).';
      cor = Colors.green.shade700;
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.bloqueio ? appLicencaNome : 'Licença do aplicativo'), automaticallyImplyLeading: !widget.bloqueio),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Icon(Icons.verified_user_outlined, size: 56, color: tema.colorScheme.primary),
        const SizedBox(height: 8),
        Text(widget.bloqueio ? 'Ativação do aplicativo' : 'Renovar licença',
            textAlign: TextAlign.center, style: tema.textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(situacao, textAlign: TextAlign.center, style: TextStyle(color: cor, fontWeight: FontWeight.w600)),
        const SizedBox(height: 20),
        Text('1. Envie este número de instalação do app "$appLicencaNome" para quem lhe vendeu o aplicativo:'),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            title: SelectableText(instalacao,
                textAlign: TextAlign.center, style: tema.textTheme.headlineMedium?.copyWith(letterSpacing: 4, fontWeight: FontWeight.bold)),
            trailing: IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copiar',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: instalacao));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Número de instalação copiado')));
                }
              },
            ),
          ),
        ),
        if (contatoVendedor.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Contato: $contatoVendedor', textAlign: TextAlign.center),
        ],
        const SizedBox(height: 20),
        const Text('2. Cole aqui o código de ativação recebido (pode colar a mensagem inteira) e toque em Ativar:'),
        const SizedBox(height: 8),
        TextField(
          controller: _codigo,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: 'XXXX-XXXX-XXXX-XXXX',
            errorText: _erro,
            suffixIcon: IconButton(
              icon: const Icon(Icons.paste),
              tooltip: 'Colar',
              onPressed: () async {
                final d = await Clipboard.getData(Clipboard.kTextPlain);
                if (d?.text != null) _codigo.text = d!.text!.trim();
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.lock_open),
          label: Padding(padding: const EdgeInsets.all(12), child: Text(_ativando ? 'Conferindo…' : 'Ativar')),
          onPressed: _ativando ? null : _ativar,
        ),
        const SizedBox(height: 16),
        const Text(
          'O código vale somente para este aparelho. Se o app for desinstalado ou os dados forem apagados, '
          'um novo número de instalação é gerado e será preciso um novo código.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ]),
    );
  }
}

/// Item para a tela "Mais": situação da licença e acesso à renovação.
class LicencaTile extends StatefulWidget {
  const LicencaTile({super.key});
  @override
  State<LicencaTile> createState() => _LicencaTileState();
}

class _LicencaTileState extends State<LicencaTile> {
  late Future<StatusLicenca> _f = LicencaLocal.verificar();

  @override
  Widget build(BuildContext context) => FutureBuilder<StatusLicenca>(
        future: _f,
        builder: (context, s) {
          final st = s.data;
          final sub = st == null
              ? 'Conferindo…'
              : st.permanente
                  ? 'Ativa, sem prazo'
                  : (st.valida ? 'Válida até ${_dataBr(st.validade!)} (${st.diasRestantes} dia(s))' : 'Vencida');
          return ListTile(
            leading: Icon(Icons.verified_user_outlined, color: st != null && st.vencendo ? Colors.deepOrange : null),
            title: const Text('Licença'),
            subtitle: Text(sub),
            trailing: const Icon(Icons.chevron_right),
            onTap: st == null
                ? null
                : () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LicencaScreen(status: st)));
                    if (mounted) setState(() => _f = LicencaLocal.verificar());
                  },
          );
        },
      );
}
