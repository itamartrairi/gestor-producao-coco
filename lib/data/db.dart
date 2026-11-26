import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Banco SQLite local. Cada instalação mantém sua própria base no aparelho.
/// As migrações são incrementais e preservam os dados existentes.
class AppDb {
  AppDb._(this.db, this.path, this.factory);

  final Database db;
  final String path;
  final DatabaseFactory factory;

  static AppDb? _instance;
  static AppDb get instance {
    final i = _instance;
    if (i == null) throw StateError('Banco não inicializado');
    return i;
  }

  static const String nomeArquivo = 'gestor_producao_coco.db';

  /// Versão atual do esquema. Ao alterar o banco, acrescente um item em
  /// [migracoes] e incremente este número.
  static int get versaoEsquema => migracoes.length;

  static Future<String> caminhoPadrao() async {
    final dir = await getDatabasesPath();
    return p.join(dir, nomeArquivo);
  }

  static Future<AppDb> abrir({String? caminho, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final path = caminho ?? await caminhoPadrao();
    final db = await f.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: versaoEsquema,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await _migrar(db, 0, version);
        },
        onUpgrade: (db, oldV, newV) async {
          await _migrar(db, oldV, newV);
        },
        onDowngrade: (db, oldV, newV) async {
          throw StateError(
              'Esta base foi criada por uma versão mais nova do aplicativo (v$oldV).');
        },
      ),
    );
    final app = AppDb._(db, path, f);
    _instance = app;
    return app;
  }

  static void definirInstancia(AppDb app) => _instance = app;

  /// Apaga toda a base e recria vazia (volta à tela de boas-vindas).
  static Future<AppDb> zerar(AppDb atual) async {
    final f = atual.factory;
    final caminho = atual.path;
    await atual.fechar();
    await f.deleteDatabase(caminho);
    return abrir(caminho: caminho, factory: f);
  }

  Future<void> fechar() async {
    await db.close();
  }

  static Future<void> _migrar(Database db, int de, int para) async {
    for (var v = de; v < para; v++) {
      final batch = db.batch();
      for (final sql in migracoes[v]) {
        batch.execute(sql);
      }
      await batch.commit(noResult: true);
    }
  }

  /// Lista de migrações. Índice 0 = versão 1.
  static final List<List<String>> migracoes = [
    _v1,
  ];

  static final List<String> _v1 = [
    '''CREATE TABLE config (chave TEXT PRIMARY KEY, valor TEXT)''',
    '''CREATE TABLE categorias (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nome TEXT NOT NULL,
      tipo TEXT NOT NULL DEFAULT 'produto'
    )''',
    // tipo: insumo (adubo, defensivo, combustível…) | embalagem (sacaria) | acabado (produto: coco)
    '''CREATE TABLE itens (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tipo TEXT NOT NULL,
      nome TEXT NOT NULL,
      categoria_id INTEGER REFERENCES categorias(id),
      unidade_compra TEXT,
      unidade_consumo TEXT NOT NULL DEFAULT 'un',
      fator_conversao REAL NOT NULL DEFAULT 1,
      estoque_minimo REAL NOT NULL DEFAULT 0,
      custo_medio REAL NOT NULL DEFAULT 0,
      unidade_venda TEXT,
      variavel_pct_cpv REAL,
      validade_dias INTEGER NOT NULL DEFAULT 15,
      ativo INTEGER NOT NULL DEFAULT 1,
      criado_em TEXT NOT NULL
    )''',
    '''CREATE TABLE variacoes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES itens(id),
      nome TEXT NOT NULL,
      tamanho TEXT, sabor TEXT, acabamento TEXT,
      unidade_venda TEXT NOT NULL DEFAULT 'un',
      preco_venda REAL NOT NULL DEFAULT 0,
      estoque_minimo REAL NOT NULL DEFAULT 0,
      ativo INTEGER NOT NULL DEFAULT 1
    )''',
    '''CREATE TABLE clientes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nome TEXT NOT NULL, telefone TEXT, documento TEXT, endereco TEXT, obs TEXT,
      criado_em TEXT NOT NULL
    )''',
    '''CREATE TABLE fornecedores (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nome TEXT NOT NULL, telefone TEXT, documento TEXT, endereco TEXT, obs TEXT,
      criado_em TEXT NOT NULL
    )''',
    // tipo: caixa | banco | carteira | outro
    '''CREATE TABLE contas_financeiras (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nome TEXT NOT NULL,
      tipo TEXT NOT NULL DEFAULT 'caixa',
      saldo_inicial REAL NOT NULL DEFAULT 0,
      data_saldo_inicial TEXT NOT NULL,
      ativo INTEGER NOT NULL DEFAULT 1
    )''',
    // tipo: dinheiro | pix | cartao | outro
    '''CREATE TABLE meios_pagamento (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nome TEXT NOT NULL,
      tipo TEXT NOT NULL,
      taxa_pct REAL NOT NULL DEFAULT 0,
      dias_repasse INTEGER NOT NULL DEFAULT 0,
      conta_id INTEGER REFERENCES contas_financeiras(id),
      ativo INTEGER NOT NULL DEFAULT 1
    )''',
    // grupo_dre: receita_bruta | desconto | devolucao | imposto_venda | cpv |
    // despesa_variavel | despesa_fixa | receita_financeira | despesa_financeira | nao_dre
    '''CREATE TABLE categorias_financeiras (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nome TEXT NOT NULL,
      tipo TEXT NOT NULL,
      grupo_dre TEXT NOT NULL DEFAULT 'nao_dre',
      codigo TEXT UNIQUE,
      ativo INTEGER NOT NULL DEFAULT 1
    )''',
    // ----- Estoque -----
    '''CREATE TABLE lotes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES itens(id),
      variacao_id INTEGER NOT NULL DEFAULT 0,
      codigo TEXT NOT NULL,
      data_fabricacao TEXT,
      validade TEXT,
      qtd_inicial REAL NOT NULL,
      saldo REAL NOT NULL,
      custo_unitario REAL NOT NULL DEFAULT 0,
      origem TEXT NOT NULL,
      origem_id INTEGER,
      criado_em TEXT NOT NULL,
      CHECK (saldo >= -0.0000001)
    )''',
    '''CREATE INDEX ix_lotes_item ON lotes(item_id, variacao_id)''',
    // tipo: compra | consumo_manejo | consumo_colheita | colheita | venda | ajuste | perda | estorno
    '''CREATE TABLE movimentos_estoque (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      data TEXT NOT NULL,
      item_id INTEGER NOT NULL REFERENCES itens(id),
      variacao_id INTEGER NOT NULL DEFAULT 0,
      lote_id INTEGER REFERENCES lotes(id),
      tipo TEXT NOT NULL,
      quantidade REAL NOT NULL,
      custo_unitario REAL NOT NULL DEFAULT 0,
      custo_total REAL NOT NULL DEFAULT 0,
      ref_tipo TEXT, ref_id INTEGER,
      motivo TEXT,
      criado_em TEXT NOT NULL
    )''',
    '''CREATE INDEX ix_mov_est_item ON movimentos_estoque(item_id, variacao_id)''',
    '''CREATE TABLE reservas (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      pedido_id INTEGER NOT NULL,
      pedido_item_id INTEGER NOT NULL,
      item_id INTEGER NOT NULL,
      variacao_id INTEGER NOT NULL DEFAULT 0,
      quantidade REAL NOT NULL,
      ativa INTEGER NOT NULL DEFAULT 1,
      criado_em TEXT NOT NULL,
      liberada_em TEXT
    )''',
    // ----- Campo: talhões, manejos (tratos culturais) e colheitas -----
    '''CREATE TABLE talhoes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nome TEXT NOT NULL,
      area_ha REAL NOT NULL DEFAULT 0,
      qtd_plantas INTEGER NOT NULL DEFAULT 0,
      variedade TEXT,
      data_plantio TEXT,
      obs TEXT,
      ativo INTEGER NOT NULL DEFAULT 1,
      criado_em TEXT NOT NULL
    )''',
    // operacao: adubacao | pulverizacao | irrigacao | rocagem | coroamento | limpeza | plantio | outro
    // colheita_id nulo = custo ainda não apropriado a uma colheita.
    '''CREATE TABLE manejos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      talhao_id INTEGER NOT NULL REFERENCES talhoes(id),
      data TEXT NOT NULL,
      operacao TEXT NOT NULL,
      descricao TEXT,
      responsavel TEXT,
      custo_insumos REAL NOT NULL DEFAULT 0,
      custo_mao_obra REAL NOT NULL DEFAULT 0,
      custo_outros REAL NOT NULL DEFAULT 0,
      custo_total REAL NOT NULL DEFAULT 0,
      colheita_id INTEGER,
      status TEXT NOT NULL DEFAULT 'ativo',
      cancelado_em TEXT,
      motivo_cancelamento TEXT,
      criado_em TEXT NOT NULL
    )''',
    '''CREATE INDEX ix_manejos_talhao ON manejos(talhao_id, colheita_id)''',
    '''CREATE TABLE manejo_insumos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      manejo_id INTEGER NOT NULL REFERENCES manejos(id),
      item_id INTEGER NOT NULL REFERENCES itens(id),
      quantidade REAL NOT NULL,
      custo_unitario REAL NOT NULL,
      custo_total REAL NOT NULL
    )''',
    // status: planejada | concluida | cancelada
    '''CREATE TABLE colheitas (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      talhao_id INTEGER NOT NULL REFERENCES talhoes(id),
      item_id INTEGER NOT NULL REFERENCES itens(id),
      variacao_id INTEGER NOT NULL DEFAULT 0,
      data TEXT NOT NULL,
      qtd_prevista REAL NOT NULL DEFAULT 0,
      responsavel TEXT,
      pedido_id INTEGER,
      status TEXT NOT NULL DEFAULT 'planejada',
      qtd_aprovada REAL, qtd_refugo REAL, qtd_perda_anormal REAL,
      motivo_perda TEXT,
      lote_id INTEGER,
      custo_manejo REAL, custo_insumos REAL, custo_mao_obra REAL, custo_outros REAL,
      custo_total REAL, custo_unitario REAL, custo_perda_anormal REAL,
      concluida_em TEXT, cancelada_em TEXT, motivo_cancelamento TEXT,
      criado_em TEXT NOT NULL
    )''',
    '''CREATE TABLE colheita_insumos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      colheita_id INTEGER NOT NULL REFERENCES colheitas(id),
      item_id INTEGER NOT NULL REFERENCES itens(id),
      quantidade REAL NOT NULL,
      custo_unitario REAL NOT NULL,
      custo_total REAL NOT NULL
    )''',
    // ----- Compras -----
    '''CREATE TABLE compras (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      fornecedor_id INTEGER REFERENCES fornecedores(id),
      data TEXT NOT NULL,
      documento TEXT,
      condicao TEXT NOT NULL DEFAULT 'avista',
      parcelas INTEGER NOT NULL DEFAULT 1,
      primeiro_vencimento TEXT,
      intervalo_dias INTEGER NOT NULL DEFAULT 30,
      conta_id INTEGER REFERENCES contas_financeiras(id),
      total REAL NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'rascunho',
      confirmada_em TEXT,
      obs TEXT,
      criado_em TEXT NOT NULL
    )''',
    '''CREATE TABLE compra_itens (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      compra_id INTEGER NOT NULL REFERENCES compras(id) ON DELETE CASCADE,
      item_id INTEGER NOT NULL REFERENCES itens(id),
      quantidade REAL NOT NULL,
      custo_total REAL NOT NULL,
      lote TEXT,
      validade TEXT
    )''',
    // ----- Pedidos e vendas -----
    '''CREATE TABLE pedidos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tipo TEXT NOT NULL DEFAULT 'encomenda',
      cliente_id INTEGER REFERENCES clientes(id),
      canal TEXT,
      status TEXT NOT NULL DEFAULT 'orcamento',
      data_pedido TEXT NOT NULL,
      data_entrega TEXT,
      hora_entrega TEXT,
      desconto REAL NOT NULL DEFAULT 0,
      frete REAL NOT NULL DEFAULT 0,
      personalizacao TEXT,
      obs TEXT,
      entregue_em TEXT,
      data_competencia TEXT,
      cancelado_em TEXT,
      motivo_cancelamento TEXT,
      criado_em TEXT NOT NULL
    )''',
    '''CREATE TABLE pedido_itens (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      pedido_id INTEGER NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
      item_id INTEGER NOT NULL REFERENCES itens(id),
      variacao_id INTEGER NOT NULL DEFAULT 0,
      quantidade REAL NOT NULL,
      preco_unitario REAL NOT NULL,
      unidade_venda TEXT,
      personalizacao TEXT,
      colheita_id INTEGER,
      custo_total REAL,
      qtd_devolvida REAL NOT NULL DEFAULT 0
    )''',
    '''CREATE TABLE pagamentos_pedido (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      pedido_id INTEGER NOT NULL REFERENCES pedidos(id),
      data TEXT NOT NULL,
      meio_id INTEGER NOT NULL REFERENCES meios_pagamento(id),
      valor REAL NOT NULL,
      movimento_id INTEGER,
      titulo_cartao_id INTEGER,
      estornado INTEGER NOT NULL DEFAULT 0,
      criado_em TEXT NOT NULL
    )''',
    '''CREATE TABLE pedido_historico (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      pedido_id INTEGER NOT NULL REFERENCES pedidos(id),
      data TEXT NOT NULL,
      evento TEXT NOT NULL,
      valor REAL,
      motivo TEXT
    )''',
    // ----- Financeiro -----
    // tipo: pagar | receber ; status: aberto | parcial | quitado | cancelado
    '''CREATE TABLE titulos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tipo TEXT NOT NULL,
      descricao TEXT NOT NULL,
      categoria_id INTEGER REFERENCES categorias_financeiras(id),
      cliente_id INTEGER, fornecedor_id INTEGER,
      ref_tipo TEXT, ref_id INTEGER,
      parcela INTEGER NOT NULL DEFAULT 1,
      total_parcelas INTEGER NOT NULL DEFAULT 1,
      valor REAL NOT NULL,
      valor_bruto REAL,
      taxa_prevista REAL,
      vencimento TEXT NOT NULL,
      nova_previsao TEXT,
      competencia TEXT NOT NULL,
      conta_prevista_id INTEGER,
      valor_compensado REAL NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'aberto',
      motivo_cancelamento TEXT,
      criado_em TEXT NOT NULL
    )''',
    '''CREATE INDEX ix_titulos_status ON titulos(status, tipo)''',
    '''CREATE TABLE movimentos_financeiros (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      data TEXT NOT NULL,
      conta_id INTEGER NOT NULL REFERENCES contas_financeiras(id),
      tipo TEXT NOT NULL,
      valor REAL NOT NULL CHECK (valor >= 0),
      categoria_id INTEGER REFERENCES categorias_financeiras(id),
      descricao TEXT,
      titulo_id INTEGER REFERENCES titulos(id),
      valor_principal REAL NOT NULL DEFAULT 0,
      juros REAL NOT NULL DEFAULT 0,
      desconto REAL NOT NULL DEFAULT 0,
      tarifa REAL NOT NULL DEFAULT 0,
      ref_tipo TEXT, ref_id INTEGER,
      transferencia_id TEXT,
      meio_id INTEGER,
      estorno_de INTEGER,
      estornado INTEGER NOT NULL DEFAULT 0,
      motivo TEXT,
      chave TEXT UNIQUE,
      criado_em TEXT NOT NULL
    )''',
    '''CREATE INDEX ix_movfin_data ON movimentos_financeiros(data)''',
    // Lançamentos por competência que formam a DRE (fonte única do resultado).
    '''CREATE TABLE lancamentos_resultado (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      data TEXT NOT NULL,
      grupo TEXT NOT NULL,
      descricao TEXT NOT NULL,
      valor REAL NOT NULL,
      categoria_id INTEGER,
      ref_tipo TEXT, ref_id INTEGER,
      item_id INTEGER, variacao_id INTEGER,
      quantidade REAL,
      canal TEXT,
      variavel INTEGER NOT NULL DEFAULT 1,
      chave TEXT UNIQUE,
      criado_em TEXT NOT NULL
    )''',
    '''CREATE INDEX ix_lanc_data ON lancamentos_resultado(data, grupo)''',
    '''CREATE TABLE auditoria (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      data_hora TEXT NOT NULL,
      acao TEXT NOT NULL,
      entidade TEXT,
      entidade_id INTEGER,
      motivo TEXT,
      detalhes TEXT
    )''',
    // ----- Dados padrão -----
    '''INSERT INTO contas_financeiras (nome, tipo, saldo_inicial, data_saldo_inicial)
       VALUES ('Caixa (dinheiro)', 'caixa', 0, date('now','localtime'))''',
    '''INSERT INTO contas_financeiras (nome, tipo, saldo_inicial, data_saldo_inicial)
       VALUES ('Conta bancária', 'banco', 0, date('now','localtime'))''',
    '''INSERT INTO meios_pagamento (nome, tipo, taxa_pct, dias_repasse, conta_id) VALUES
       ('Dinheiro', 'dinheiro', 0, 0, 1),
       ('Pix', 'pix', 0, 0, 2),
       ('Cartão de débito', 'cartao', 1.5, 1, 2),
       ('Cartão de crédito', 'cartao', 3.5, 30, 2)''',
    '''INSERT INTO categorias_financeiras (nome, tipo, grupo_dre, codigo) VALUES
       ('Recebimento de vendas', 'entrada', 'nao_dre', 'VENDA_RECEB'),
       ('Adiantamento de clientes (sinal)', 'entrada', 'nao_dre', 'ADIANT_CLIENTE'),
       ('Repasse de cartão', 'entrada', 'nao_dre', 'CARTAO_REPASSE'),
       ('Devolução de sinal / estorno a cliente', 'saida', 'nao_dre', 'DEVOL_CLIENTE'),
       ('Compra de insumos agrícolas e sacaria', 'saida', 'nao_dre', 'COMPRA_INSUMO'),
       ('Transferência entre contas', 'ambos', 'nao_dre', 'TRANSF'),
       ('Aporte / retirada dos sócios', 'ambos', 'nao_dre', 'SOCIOS'),
       ('Juros e multas pagos', 'saida', 'despesa_financeira', 'JUROS_PAGOS'),
       ('Juros recebidos', 'entrada', 'receita_financeira', 'JUROS_RECEB'),
       ('Descontos obtidos', 'entrada', 'receita_financeira', 'DESC_OBTIDOS'),
       ('Descontos concedidos em recebimentos', 'saida', 'despesa_financeira', 'DESC_CONCEDIDOS'),
       ('Tarifas bancárias', 'saida', 'despesa_financeira', 'TARIFA'),
       ('Taxas de cartão e apps', 'saida', 'despesa_variavel', 'TAXA_CARTAO'),
       ('Comissões de venda', 'saida', 'despesa_variavel', 'COMISSAO'),
       ('Fretes e entregas', 'saida', 'despesa_variavel', 'FRETE_ENTREGA'),
       ('Perdas de estoque e de colheita', 'saida', 'despesa_variavel', 'PERDAS'),
       ('Impostos sobre vendas (Funrural etc.)', 'saida', 'imposto_venda', 'IMPOSTO_VENDA'),
       ('Arrendamento da terra', 'saida', 'despesa_fixa', 'ALUGUEL'),
       ('Energia e irrigação', 'saida', 'despesa_fixa', 'UTILIDADES'),
       ('Salários, diárias e pró-labore', 'saida', 'despesa_fixa', 'PESSOAL'),
       ('Manutenção de máquinas e equipamentos', 'saida', 'despesa_fixa', 'MANUTENCAO'),
       ('ITR, CCIR e taxas rurais', 'saida', 'despesa_fixa', 'TAXAS_RURAIS'),
       ('Marketing', 'saida', 'despesa_fixa', 'MARKETING'),
       ('Outras despesas', 'saida', 'despesa_fixa', 'OUTRAS_DESP'),
       ('Outras receitas', 'entrada', 'receita_financeira', 'OUTRAS_REC')''',
    '''INSERT INTO categorias (nome, tipo) VALUES
       ('Coco verde', 'produto'), ('Coco seco', 'produto'), ('Mudas', 'produto'),
       ('Fertilizantes e corretivos', 'insumo'), ('Defensivos', 'insumo'),
       ('Combustíveis e lubrificantes', 'insumo'), ('Sacaria e embalagens', 'insumo'),
       ('Mudas e sementes', 'insumo')''',
    '''INSERT INTO config (chave, valor) VALUES ('pct_imposto_vendas', '0'),
       ('alerta_validade_dias', '3')''',
  ];
}

/// Erro de regra de negócio com mensagem pronta para o usuário.
class RegraException implements Exception {
  RegraException(this.mensagem);
  final String mensagem;
  @override
  String toString() => mensagem;
}
