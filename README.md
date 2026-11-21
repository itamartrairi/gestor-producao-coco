# Gestor de Produção e Comercialização de Coco

Aplicativo para celulares **Android e iPhone** (Flutter, uma única base de código) para **produtores rurais de coco**. Integra talhões do coqueiral, compra de insumos, manejos (tratos culturais), colheitas com custo real, estoque de coco verde e coco seco, pedidos e vendas, fluxo de caixa e DRE gerencial.

Baseado no [Gestor de Produção e Vendas](https://github.com/itamartrairi/gestor-producao-vendas), com a produção industrial (fichas técnicas e ordens de produção) substituída pelo ciclo do campo.

- 100% **offline**: dados em **SQLite no próprio celular**, sem servidor ou nuvem. Funciona na roça, sem sinal, incluindo PDFs e backup.
- Português do Brasil, valores em R$, datas DD/MM/AAAA.
- Migrações de banco que preservam os dados ao atualizar o app.

## Navegação

`Início` · `Painel` · `Pedidos` · `Campo` (Colheitas, Manejos, Talhões) · `Estoque` (Insumos, Cocos) · `Mais` (Talhões, Compras, Financeiro, DRE, Relatórios, Cadastros, Configurações).

## Como funciona o custeio do coco

| Etapa | Implementação |
|---|---|
| Talhões | Nome, variedade (anão verde, gigante, híbrido), área (ha), nº de plantas, data de plantio. Cada talhão mostra os custos acumulados **a apropriar** e o que foi colhido nos últimos 12 meses. |
| Insumos | Adubos, corretivos, defensivos, combustível e sacaria. Compra com unidade de compra → unidade de uso (ex.: saco 50 kg → kg) e **custo médio ponderado**. Lotes com validade, alertas de mínimo e vencimento. |
| Manejos | Adubação, pulverização, irrigação, roçagem, coroamento, limpeza de copa, plantio. Cada manejo **baixa os insumos do estoque** (por ordem de vencimento) e soma mão de obra e outros custos (combustível, aluguel de máquina). O custo fica acumulado no talhão. Manejo ainda não apropriado pode ser cancelado, devolvendo os insumos ao estoque. |
| Colheitas | Planejadas por talhão e produto (com classificação: graúdo, médio…), opcionalmente vinculadas a um pedido. Ao concluir: apropria todos os manejos pendentes do talhão até a data, baixa os insumos da colheita (sacaria, diesel), soma mão de obra dos apanhadores e frete interno. **Custo unitário = custo total ÷ (aprovada + perda anormal)**. O refugo normal (rachados, fora de padrão) fica absorvido no custo; a perda anormal (chuva, praga, furto) vai para o resultado. Gera o lote com validade (coco verde ~12 dias, coco seco ~60 dias, configurável por produto). |
| Pedidos | Orçamento → confirmado → em colheita → pronto → entregue / cancelado. Reservas de estoque, colheitas vinculadas que reservam automaticamente, sinal, pagamentos mistos e parciais, devolução de sinal, estornos. Venda à vista para feira, barraca ou atravessador. |
| Entrega | Baixa única do estoque, receita e CPV reconhecidos na entrega, adiantamentos abatidos e só o saldo vai para contas a receber. |
| Financeiro | Contas a pagar/receber com parcelas, juros, descontos, baixas parciais, transferências, cartão com repasse e conciliação. Categorias rurais: arrendamento, energia da irrigação, diárias, manutenção de máquinas, ITR/CCIR, Funrural. |
| DRE | Por competência. Insumos comprados vão para o estoque; o CPV usa o custo registrado dos lotes de coco vendidos. A mão de obra e os custos de campo apropriados às colheitas são creditados das despesas do período (configurável) para não serem contados duas vezes. |
| Relatórios | Dois PDFs (A4): **Fluxo de Caixa** (realizado, projetado ou ambos) e **Vendas e Custos**, com os custos das colheitas do período por talhão. |
| Backup | Arquivo `.gpcbak` com banco + logomarca, cifrado com AES‑256‑GCM (chave PBKDF2‑SHA256). |

## Ativação (licença por aparelho)

O app só abre com um **código de ativação**. Na primeira abertura ele mostra um **número de instalação** (8 letras/números); o cliente envia esse número ao vendedor, que gera o código de 16 caracteres na página geradora, com o prazo desejado (30 dias, 1 ano, sem prazo…). O código:

- vale somente para aquele aparelho e para este app;
- traz a validade embutida e não pode ser alterado (assinatura HMAC‑SHA256 com a chave de `lib/core/licenca_config.dart`);
- é conferido sem internet; perto do vencimento o app avisa, e depois de vencido pede um código novo (os dados ficam guardados).

Em **Mais › Licença** o cliente vê a validade e renova. Para mostrar seu contato na tela de ativação, preencha `contatoVendedor` em `lib/core/licenca_config.dart`. **Não divulgue a chave** desse arquivo nem a página geradora.

## Gerar o app

Pré‑requisitos: [Flutter](https://docs.flutter.dev/get-started/install) (canal stable), Android Studio (Android) e Xcode num Mac (iOS).

```bash
git clone https://github.com/itamartrairi/gestor-producao-coco.git
cd gestor-producao-coco
bash tool/preparar_plataformas.sh   # cria android/ e ios/ e ajusta permissões
flutter pub get
flutter test                        # cenário de validação no SQLite real
flutter run                         # com o celular conectado
```

### Android (APK / Play Store)

```bash
flutter build apk --release         # build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle --release   # para publicar na Play Store
```

Para publicar, configure uma chave de assinatura própria (`android/key.properties`) conforme a [documentação do Flutter](https://docs.flutter.dev/deployment/android). O APK do GitHub Actions é assinado com a chave de depuração e serve para testes.

### iPhone

```bash
open ios/Runner.xcworkspace         # defina Team e Bundle Identifier em Signing & Capabilities
flutter build ipa --release         # requer conta Apple Developer
```

### GitHub Actions

A cada envio para `main`, o workflow `Testes e APK` roda a análise, os testes e gera o APK (aba **Actions → artefato `gestor-producao-coco-apk`**), além de compilar o iOS sem assinatura.

## Dados demonstrativos

Carregados na primeira configuração (ou em **Mais › Configurações › Carregar dados de exemplo**, com a base vazia): dois talhões (anão verde e gigante), adubos, inseticida, diesel e sacaria comprados a prazo, três manejos, colheitas de coco verde e coco seco, uma colheita planejada, pedido de distribuidora com sinal, venda à vista e despesas fixas do mês.

## Roteiro de validação

1. Compre adubo e sacaria a prazo e confira o estoque e a conta a pagar.
2. Cadastre um talhão e registre uma adubação; confira a baixa do adubo e o custo a apropriar no talhão.
3. Planeje e conclua uma colheita de coco verde; confira a apropriação do manejo e a entrada dos cocos com custo, lote e validade.
4. Registre um pedido com sinal e confira a entrada no caixa.
5. Entregue o pedido e confira a baixa dos cocos, o abatimento do sinal, o saldo a receber e o CPV na DRE.
6. Pague o fornecedor e confira a saída na conta correta.
7. Gere os dois PDFs e confira os totais com o Financeiro e a DRE.
8. Feche e reabra o app e confirme que os dados continuam salvos.
9. Exporte o backup e restaure em outro aparelho.

Os itens 1–7 e 9 (parte de dados) estão automatizados em `test/cenario_test.dart`.

## Estrutura

```
lib/
  core/format.dart          formatação pt-BR (R$, datas)
  data/db.dart              esquema SQLite e migrações
  services/                 regras de negócio (campo, estoque, compras, pedidos,
                            financeiro, DRE, relatórios, PDFs, backup, demo)
  ui/screens/               telas (campo_screen.dart: colheitas, manejos e talhões)
  ui/widgets/               componentes reutilizáveis
test/cenario_test.dart      testes do cenário completo
tool/preparar_plataformas.sh
```

Fontes dos PDFs: Noto Sans (SIL Open Font License, `assets/fonts/OFL.txt`).
