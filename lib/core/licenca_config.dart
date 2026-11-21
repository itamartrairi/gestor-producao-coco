/// Configuração dos códigos de ativação deste app.
/// A chave abaixo é a mesma da página geradora de códigos: não divulgue.
library;

/// Identificação do app dentro do código (diferente em cada app).
const appLicencaId = 'COC';

/// Nome mostrado na tela de ativação.
const appLicencaNome = 'Gestor de Produção de Coco';

/// Contato do vendedor exibido na tela de ativação (ex.: 'WhatsApp (85) 99999-0000').
/// Deixe vazio para não mostrar.
const contatoVendedor = '';

/// Chave secreta HMAC-SHA256 (32 bytes).
const List<int> chaveLicenca = [
  108, 109, 51, 5, 157, 129, 121, 2,
  244, 74, 135, 3, 223, 33, 244, 118,
  89, 230, 148, 162, 232, 187, 172, 50,
  154, 218, 125, 75, 121, 4, 227, 186,
];
