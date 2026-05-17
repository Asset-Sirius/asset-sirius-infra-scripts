# Lambda Script - Orquestração CloudFormation

## Descrição
Script Python para Lambda que orquestra a criação de toda a infraestrutura AWS usando CloudFormation, seguindo uma ordem específica de dependências.

## Ordem de Criação (Garantida)
1. **Network** - VPC, Subnets, Internet Gateway, NAT Gateway, Route Tables
2. **Pipeline** - Recursos de pipeline (CodePipeline, CodeBuild, etc)
3. **Security** - Security Groups, IAM Roles, Policies
4. **Storage** - S3 Buckets, DynamoDB, etc
5. **Compute** - EC2, Lambda, ECS, etc

## Características Principais
✓ Criação sequencial garantida - cada stack espera a anterior terminar  
✓ Polling automático do status das stacks (verifica a cada 10 segundos)  
✓ Timeout de 1 hora por stack  
✓ Tratamento robusto de erros  
✓ Suporte a atualização de stacks existentes  
✓ Relatório detalhado de sucesso/falha  
✓ Tags automáticas em todos os recursos  

## Pré-requisitos

### 1. Templates CloudFormation
Os templates devem estar nos locais corretos e definir outputs apropriados:

| Stack | Template | Outputs Obrigatórios |
|-------|----------|----------------------|
| Network | `network.yaml` | `VpcId`, `PublicSubnetId`, `PrivateSubnetIds` |
| Pipeline | `pipeline.yaml` | (nenhum obrigatório) |
| Security | `security.yaml` | `NodeJsEc2SecurityGroupId`, `GrafanaEc2SecurityGroupId`, `RdsSecurityGroupId` |
| Storage | `storage.yaml` | (nenhum obrigatório) |
| Compute | `compute.yaml` | (nenhum obrigatório) |

**Nota sobre PrivateSubnetIds:** O output `PrivateSubnetIds` deve ser um join com vírgulas (ex: `subnet-1,subnet-2,subnet-3`). O script extrai automaticamente cada subnet ID.

### 2. Bucket S3 com Templates
Crie um bucket S3 e upload dos templates CloudFormation:
```bash
aws s3 mb s3://asset-sirius-bucket-templates
aws s3 cp script_cloudformation/ s3://asset-sirius-bucket-templates/cloudformation/ --recursive
```

### 3. Role IAM para Lambda
A função Lambda precisa de uma IAM Role com as seguintes permissões:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudformation:CreateStack",
        "cloudformation:UpdateStack",
        "cloudformation:DescribeStacks",
        "cloudformation:DescribeStackEvents",
        "cloudformation:GetTemplate"
      ],
      "Resource": "arn:aws:cloudformation:*:ACCOUNT_ID:stack/asset-sirius-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::asset-sirius-bucket-templates",
        "arn:aws:s3:::asset-sirius-bucket-templates/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:PutRolePolicy",
        "iam:PassRole",
        "iam:GetRole",
        "iam:CreateInstanceProfile",
        "iam:AddRoleToInstanceProfile"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "rds:*",
        "lambda:*",
        "logs:*"
      ],
      "Resource": "*"
    }
  ]
}
```

### 4. Configurar Lambda no AWS

#### Opção 1: Via Console
1. Crie uma função Lambda (Python 3.11+)
2. Copie o código de `n8n-lambda.py`
3. Associe a IAM Role criada acima
4. Configure timeout para **15+ minutos** (função -> Configuração -> Geral)
5. Defina memória para **512+ MB** (recomendado: 1024 MB)

#### Opção 2: Via AWS CLI
```bash
# Cria a função
aws lambda create-function \
  --function-name asset-sirius-orchestrator \
  --runtime python3.11 \
  --role arn:aws:iam::ACCOUNT_ID:role/lambda-cloudformation-role \
  --handler n8n-lambda.lambda_handler \
  --zip-file fileb://n8n-lambda.zip \
  --timeout 900 \
  --memory-size 1024
```

## Como Usar

### Invocação Básica
```bash
aws lambda invoke \
  --function-name asset-sirius-orchestrator \
  --payload '{}' \
  response.json

cat response.json
```

### Invocação com Parâmetros
```bash
aws lambda invoke \
  --function-name asset-sirius-orchestrator \
  --payload '{
    "template_bucket": "asset-sirius-bucket-templates",
    "template_key_prefix": "cloudformation"
  }' \
  response.json
```

## Resposta da Lambda

### Sucesso
```json
{
  "statusCode": 200,
  "body": {
    "successful": [
      "asset-sirius-network",
      "asset-sirius-pipeline",
      "asset-sirius-security",
      "asset-sirius-storage",
      "asset-sirius-compute"
    ],
    "failed": [],
    "timestamp": 1234567890
  }
}
```

### Falha
```json
{
  "statusCode": 500,
  "body": {
    "successful": [
      "asset-sirius-network",
      "asset-sirius-pipeline"
    ],
    "failed": [
      "asset-sirius-security"
    ],
    "timestamp": 1234567890
  }
}
```

## Resolução Automática de Parâmetros

O script utiliza um mecanismo inteligente de resolução de parâmetros que passa automaticamente os outputs de uma stack como parâmetros da próxima stack.

### Como Funciona

1. **Network Stack** é criada primeiro (sem parâmetros, usa defaults)
2. Seus outputs (`VpcId`, `PublicSubnetId`, `PrivateSubnetIds`) são capturados
3. **Security Stack** recebe `VpcId` como parâmetro (resolvido automaticamente)
4. Seus outputs (`NodeJsEc2SecurityGroupId`, `GrafanaEc2SecurityGroupId`, `RdsSecurityGroupId`) são capturados
5. **Storage Stack** recebe:
   - `PrivateSubnet2Id` e `PrivateSubnet3Id` (extraídos de `PrivateSubnetIds` da Network)
   - `RdsSecurityGroupId` (output da Security)
6. **Compute Stack** recebe:
   - `GrafanaSecurityGroupId` e `NodeJsSecurityGroupId` (outputs da Security)
   - `GrafanaSubnetId` (PublicSubnetId da Network)
   - `NodeJsSubnetId` (PrivateSubnet1Id extraído da Network)

### Exemplo de Resolução

Quando a Storage stack é criada, o script:
1. Recupera o output `PrivateSubnetIds` da Network: `"subnet-12345,subnet-67890,subnet-abcde"`
2. Divide por vírgula e atribui:
   - `PrivateSubnet1Id` = `subnet-12345`
   - `PrivateSubnet2Id` = `subnet-67890`
   - `PrivateSubnet3Id` = `subnet-abcde`
3. Passa para o template CloudFormation como parâmetros

## Customizações

### Fluxo Automático de Parâmetros

O script resolve automaticamente os parâmetros de cada stack usando os outputs das stacks anteriores:

**Network** → Sem parâmetros (usa defaults)
- Outputs: `VpcId`, `PublicSubnetId`, `PrivateSubnetIds`

**Pipeline** → Sem parâmetros (usa defaults)
- Outputs: depende do seu template

**Security** → Recebe automaticamente:
- `VpcId` (do output da Network)

**Storage** → Recebe automaticamente:
- `PrivateSubnet2Id` (extraído do PrivateSubnetIds da Network)
- `PrivateSubnet3Id` (extraído do PrivateSubnetIds da Network)
- `RdsSecurityGroupId` (do output da Security)

**Compute** → Recebe automaticamente:
- `GrafanaSecurityGroupId` (do output da Security)
- `GrafanaSubnetId` (PublicSubnetId da Network)
- `NodeJsSecurityGroupId` (do output da Security)
- `NodeJsSubnetId` (extraído como PrivateSubnet1Id do Network)

### Modificar Configuração das Stacks

Para customizar parâmetros adicionais, edite a seção `STACKS_CONFIG` em `n8n-lambda.py`:

```python
STACKS_CONFIG = [
    {
        'name': 'asset-sirius-network',
        'template': 'network.yaml',
        'parameters': {},  # Sem parâmetros - usa defaults do template
        'depends_on': []
    },
    {
        'name': 'asset-sirius-security',
        'template': 'security.yaml',
        'parameters': {
            'VpcId': 'VpcId',  # Recuperado do output VpcId da network
            'SshAccessCidr': '0.0.0.0/0',  # Exemplo de parâmetro literal
        },
        'depends_on': ['asset-sirius-network']
    },
]
```

**Nota importante:**
- Valores que correspondem a nomes de outputs (ex: `'VpcId': 'VpcId'`) são resolvidos automaticamente
- Valores literais (ex: `'SshAccessCidr': '0.0.0.0/0'`) são usados como estão
- O script extrai automaticamente subnet IDs individuais do output `PrivateSubnetIds` (que é um join com vírgulas)

### Modificar Timeouts
- **Stack timeout**: Edite `TimeoutInMinutes=30` em `create_stack()`
- **Lambda timeout**: Configure via AWS Console (máximo 15 minutos, recomendado)
- **Poll interval**: Edite `poll_interval = 10` em `wait_stack_creation()`

## Monitoramento

### CloudWatch Logs
A função Lambda registra logs detalhados:
```bash
aws logs tail /aws/lambda/asset-sirius-orchestrator --follow
```

### Verificar Status de Stacks
```bash
aws cloudformation describe-stacks \
  --stack-name asset-sirius-network \
  --query 'Stacks[0].StackStatus'
```

## Troubleshooting

### "alreadyexistsexception"
A stack já existe. O script tentará atualizar automaticamente.

### "Timeout"
Stack levou mais de 1 hora para criar. Verifique:
- CloudWatch Logs da stack
- Recursos que estão sendo criados (RDS, NAT Gateway podem levar tempo)
- Aumente `max_wait_time` no script

### "Access Denied"
Verifique as permissões da IAM Role associada à Lambda.

### Templates não encontrados
Certifique-se de que:
1. O bucket `template_bucket` existe
2. Os templates estão em `s3://bucket/cloudformation/`
3. A Lambda tem permissão `s3:GetObject`

## Exemplo de Fluxo Completo

```bash
# 1. Preparar bucket
aws s3 mb s3://asset-sirius-bucket-templates
aws s3 sync script_cloudformation/ s3://asset-sirius-bucket-templates/cloudformation/

# 2. Criar Lambda com código
# (use AWS Console ou AWS CLI como descrito acima)

# 3. Executar
aws lambda invoke \
  --function-name asset-sirius-orchestrator \
  --payload '{"template_bucket": "meu-projeto-templates"}' \
  response.json

# 4. Verificar resultado
cat response.json
```

## Limpeza

Para remover toda a infraestrutura criada:

```bash
# Remove na ordem inversa (dependências)
aws cloudformation delete-stack --stack-name asset-sirius-compute
aws cloudformation delete-stack --stack-name asset-sirius-storage
aws cloudformation delete-stack --stack-name asset-sirius-security
aws cloudformation delete-stack --stack-name asset-sirius-pipeline
aws cloudformation delete-stack --stack-name asset-sirius-network
```

## Notas de Segurança

- 🔒 A Lambda precisa de acesso ao S3, CloudFormation e recursos AWS
- 🔒 Armazene credenciais AWS em variáveis de ambiente, nunca no código
- 🔒 Configure a Lambda em VPC privada se necessário
- 🔒 Use CloudTrail para auditar todas as operações CloudFormation
