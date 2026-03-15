# asset-sirius-infra-scripts

Repositório de automação de infraestrutura AWS do projeto Asset Sirius, com scripts para criação e destruição completa do ambiente.

## Visão geral

O projeto possui dois fluxos principais:

- **Criação de infraestrutura**: provisiona VPC, subnets, gateways, rotas, security groups, EC2 e RDS.
- **Destruição de infraestrutura**: remove os recursos criados, com confirmação explícita de segurança.

## Estrutura principal

- `app/`
	- `automacao-criar-infra.sh`: script principal para provisionamento da infraestrutura.
	- `automacao-derrubar-infra.sh`: script para remoção da infraestrutura.
	- `lib/`: funções auxiliares para validações, utilitários e operações AWS.
		- `utils.sh`: mensagens, menu e helpers de fluxo.
		- `validacao.sh`: validação de entradas e confirmações.
		- `aws_helpers.sh`: agregador de módulos AWS.
		- `aws-helpers/`: funções por recurso (VPC, Subnet, SG, EC2, RDS, NAT, Route Table etc.).

## Pré-requisitos

- Bash (macOS/Linux)
- AWS CLI v2 instalado e configurado
- Credenciais AWS válidas no perfil padrão (`aws configure`)
- Permissões IAM para gerenciamento de:
	- EC2 (VPC, Subnet, SG, Route Table, IGW, NAT Gateway, EIP, Instâncias, Key Pair)
	- RDS (DB Instance e DB Subnet Group)

Exemplo de validação rápida:

```bash
aws sts get-caller-identity
```

## Configurações padrão

No arquivo `app/automacao-criar-infra.sh`, estão definidos os parâmetros padrão:

- Região: `us-east-1`
- Zonas: `us-east-1a` e `us-east-1b`
- AMI EC2: `ami-0b6c6ebed2801a5cb`
- Tipo EC2: `t2.micro`
- Pasta do par de chaves local: `$HOME/Downloads/par de chaves EC2`

Se necessário, ajuste esses valores antes da execução.

## Como executar

No diretório raiz do projeto:

### 1) Criar infraestrutura

```bash
bash app/automacao-criar-infra.sh
```

No menu, escolha a opção `1` para provisionar a infraestrutura.

Durante o processo, o script solicita:

- configuração/seleção do par de chaves EC2;
- usuário master do RDS;
- senha master do RDS (mínimo 8 caracteres).

### 2) Derrubar infraestrutura

Você pode:

- executar novamente `bash app/automacao-criar-infra.sh` e escolher a opção `2`; ou
- executar diretamente:

```bash
bash app/automacao-derrubar-infra.sh
```

O script de destruição exige confirmação digitando `CONFIRMAR`.

## Recursos gerenciados

### Provisionamento

- VPC (`10.0.0.0/16`)
- 1 subnet pública + 3 subnets privadas/auxiliares
- Internet Gateway
- NAT Gateway + Elastic IP
- Route tables pública e privada
- 5 Security Groups (Frontend, Backend, Python, Bedrock, RDS)
- 4 instâncias EC2 (Frontend, Backend, Python, Bedrock)
- RDS MySQL (`db.t3.micro`) + DB Subnet Group

### Destruição

Remove os recursos acima em ordem segura para evitar dependências pendentes.

## Observações

- A criação de NAT Gateway e RDS pode levar alguns minutos.
- Este projeto gera custos reais na AWS enquanto os recursos estiverem ativos.
- Recomenda-se executar primeiro em conta de homologação/sandbox.
