# Documentação da Ingestão de Dados CVM

## 1) Objetivo
Este projeto automatiza o download de arquivos públicos da CVM para os tipos de fundo:

- **FI**
- **FIP**
- **FIF**
- **FACFIF**

A solução foi desenhada para execução recorrente (**cron**) e possui regra automática de carga:

- **Carga histórica** quando o diretório de saída está vazio.
- **Carga incremental** quando já existe pelo menos um arquivo no diretório de saída.

---

## 2) Estrutura dos arquivos

### `ingestao_dados_main.py`
Arquivo de entrada da aplicação (entrypoint). Responsável por:

1. Ler configurações fixas definidas no próprio arquivo.
2. Definir o tipo de carga (`auto`, `historica`, `incremental`).
3. Chamar a execução do download.

### `ingestao_dados_functions.py`
Contém toda a lógica funcional:

- mapeamento de fontes da CVM;
- coleta e parsing dos links do diretório web;
- regras de filtro por carga;
- download de arquivos.

---

## 3) Fontes de dados usadas
A base raiz é:

- `https://dados.cvm.gov.br/dados/`

Mapeamentos implementados:

- **FI**:
  - `FI/CAD/DADOS/`
  - `FI/DOC/INF_DIARIO/DADOS/`
- **FIP**:
  - `FIP/DOC/INF_TRIMESTRAL/DADOS/`
  - `FIP/DOC/INF_QUADRIMESTRAL/DADOS/`
- **FIF**:
  - `FI/CAD/DADOS/` (subtipo tratado via base de cadastro FI)
- **FACFIF**:
  - `FI/CAD/DADOS/` (subtipo tratado via base de cadastro FI)

> Observação: FIF e FACFIF não estão como diretórios independentes no mesmo padrão de FI/FIP.

---

## 4) Fluxo de execução (passo a passo)

## 4.1 Entrada (`main`)
No arquivo `ingestao_dados_main.py`, a função `main()`:

1. Lê as constantes de configuração do arquivo (`DIRETORIO_SAIDA`, `SOBRESCREVER`, `TIMEOUT_SEGUNDOS`, `MODO_CARGA`).
2. Resolve diretório de saída.
3. Define `tipo_carga`:
   - se `MODO_CARGA = "auto"`:
     - diretório sem arquivo => `historica`
     - diretório com arquivo => `incremental`
4. Chama `executar_download(...)`.

## 4.2 Execução principal (`executar_download`)
No arquivo `ingestao_dados_functions.py`, a função `executar_download(...)`:

1. Define `data_execucao = datetime.now()`.
2. Para cada tipo mapeado em `FONTES` (FI/FIP/FIF/FACFIF):
   - coleta arquivos remotos via `coletar_arquivos_tipo`;
   - aplica filtro de carga com `filtrar_por_carga`;
   - para cada arquivo elegível, chama `baixar_arquivo`;
   - grava em subpasta por tipo (`fi/`, `fip/`, etc.);
   - imprime resumo final por tipo.

## 4.3 Coleta dos arquivos remotos
A função `coletar_arquivos_tipo(tipo, timeout)`:

1. Busca as URLs base do tipo no dicionário `FONTES`.
2. Para cada URL, baixa HTML com `baixar_html`.
3. Extrai links válidos com `extrair_arquivos_cvm`.
4. Remove duplicados por URL.
5. Retorna lista ordenada por nome.

## 4.4 Parsing do HTML da CVM
A função `extrair_arquivos_cvm(html, base_url)`:

1. Aplica regex para capturar:
   - `href` do arquivo
   - data/hora de modificação exibida na listagem
2. Ignora diretórios (`../`, `./`, links que terminam com `/`).
3. Aceita apenas extensões: `.zip`, `.csv`, `.txt`, `.xml`.
4. Monta `ArquivoCVM(url, nome, data_modificacao)`.

## 4.5 Regra de carga (histórica vs incremental)
A função `filtrar_por_carga(arquivos, tipo_carga, data_execucao)` implementa:

### Incremental
Seleciona apenas:

- arquivos com `data_modificacao` igual ao dia da execução, ou
- fallback para nomes contendo data do dia (`YYYYMMDD`) quando a data não estiver disponível.

### Histórica
Seleciona arquivos com modificação nos **últimos 90 dias** (aproximação do último trimestre).

## 4.6 Download físico
A função `baixar_arquivo(url, destino, sobrescrever, timeout)`:

1. Garante criação da pasta de destino.
2. Se arquivo existe e `sobrescrever=False`, ignora.
3. Caso contrário, baixa o conteúdo e grava no disco.
4. Retorna status e mensagem para log.

---

## 5) Configuração fixa

As configurações ficam no início de `ingestao_dados_main.py`:

- `DIRETORIO_SAIDA`
- `SOBRESCREVER`
- `TIMEOUT_SEGUNDOS`
- `MODO_CARGA` (`auto`, `incremental`, `historica`)

Para alterar comportamento, edite essas constantes diretamente no arquivo.

---

## 6) Execução

### Execução padrão (ideal para cron)
```bash
python3 ingestao_dados_main.py
```

Para forçar histórica/incremental, ajuste `MODO_CARGA` em `ingestao_dados_main.py`.

---

## 7) Agendamento no cron (macOS/Linux)

Exemplo para rodar todos os dias às 06:00 com log:

```cron
0 6 * * * cd "/Users/caioacayabafurtado/Documents/GIT-HUB/arquivos-sptech/Materiais - Semestre5/Análise de dados/atividade1" && /usr/bin/python3 ingestao_dados_main.py >> logs_ingestao.log 2>&1
```

Boas práticas para cron:

- use caminho absoluto do Python;
- use caminho absoluto do diretório;
- redirecione stdout/stderr para arquivo de log;
- monitore o log em caso de indisponibilidade da CVM.

---

## 8) Comportamento de idempotência

- O processo **não baixa novamente** arquivos já existentes por padrão.
- Para reprocessar arquivos, altere `SOBRESCREVER = True` em `ingestao_dados_main.py`.

Isso evita crescimento desnecessário de tráfego e tempo de execução em rotinas de automação.

---

## 9) Tratamento de erros

O script trata erros por tipo e por arquivo:

- falhas de coleta de links em um tipo não interrompem os demais;
- falhas de download de um arquivo não interrompem o restante;
- mensagens são exibidas no console/log para diagnóstico.

---

## 10) Como evoluir o projeto

Possíveis melhorias futuras:

1. Persistir metadados de execução (arquivo de controle `.json`).
2. Validar checksum/tamanho para garantir integridade de download.
3. Implementar retries com backoff em falhas temporárias HTTP.
4. Extrair e filtrar automaticamente subtipos (`FIF`, `FACFIF`) a partir dos CSVs baixados.
5. Adicionar testes unitários para parsing de HTML e regras de carga.

---

## 11) Resumo técnico

- Arquitetura em 2 módulos (`main` + `functions`).
- Fluxo compatível com execução agendada.
- Modo automático de carga baseado no estado do diretório de saída.
- Regras de carga simplificadas e objetivas para operação contínua.
