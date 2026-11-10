# Lambda Script - Orquestração CloudFormation

## Descrição
Script Python para Lambda que orquestra a criação de toda a infraestrutura AWS usando CloudFormation, seguindo uma ordem específica de dependências.

## Ordem de Criação (Garantida)
1. **EIPs** - Elastic IPs do Node.js, Grafana e da segunda instância do frontend
2. **Network** - VPC, Subnets, Internet Gateway, NAT Gateway, Route Tables
3. **ALB** - Application Load Balancer, SG do ALB, Target Groups (frontend e Grafana) e Listeners
4. **Pipeline** - Recursos de pipeline (CodePipeline, CodeBuild, etc)
5. **Security** - Security Groups, IAM Roles, Policies
6. **Storage** - S3 Buckets, DynamoDB, etc
7. **Compute** - EC2 (Node.js, Grafana+frontend e segunda instância do frontend)

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
| Network | `network.yaml` | `VpcId`, `PublicSubnetId`, `PublicSubnet2Id`, `PublicSubnetIds`, `PrivateSubnetIds` |
| ALB | `alb.yaml` | `TargetGroupArn`, `GrafanaTargetGroupArn`, `AlbSgId`, `AlbDns` |
| Pipeline | `pipeline.yaml` | (nenhum obrigatório) |
| Security | `security.yaml` | `NodeJsEc2SecurityGroupId`, `GrafanaEc2SecurityGroupId`, `RdsSecurityGroupId` |
| Storage | `storage.yaml` | (nenhum obrigatório) |
| Compute | `compute.yaml` | `GrafanaEc2InstanceId`, `FrontendEc2InstanceId2`, `FrontendEc2InstanceIds` |

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
          "logs:*",
          "elasticloadbalancing:*"
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
      "asset-sirius-alb",
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
2. Seus outputs (`VpcId`, `PublicSubnetId`, `PublicSubnet2Id`, `PublicSubnetIds`, `PrivateSubnetIds`) são capturados
3. **ALB Stack** recebe `VpcId` e `PublicSubnets` (lista de subnets públicas)
4. **Security Stack** recebe `VpcId` como parâmetro (resolvido automaticamente)
5. Seus outputs (`NodeJsEc2SecurityGroupId`, `GrafanaEc2SecurityGroupId`, `RdsSecurityGroupId`) são capturados
6. **Storage Stack** recebe:
   - `PrivateSubnet2Id` e `PrivateSubnet3Id` (extraídos de `PrivateSubnetIds` da Network)
   - `RdsSecurityGroupId` (output da Security)
7. **Compute Stack** recebe:
   - `GrafanaSecurityGroupId` e `NodeJsSecurityGroupId` (outputs da Security)
   - `GrafanaSubnetId` (PublicSubnetId da Network)
   - `Frontend2SubnetId` (PublicSubnet2Id da Network, outra AZ)
   - `NodeJsSubnetId` (PrivateSubnet1Id extraído da Network)
   - `TargetGroupArn`, `AlbSgId` e `AlbDns` (outputs da ALB Stack)
   - `GrafanaEipAllocationId`, `NodeEipAllocationId` e `Frontend2EipAllocationId` (outputs da stack de EIPs)

### Registro dos alvos no Target Group do ALB

O CloudFormation **não possui** recurso para registrar um alvo que vive em outra stack
(não existe `AWS::ElasticLoadBalancingV2::TargetGroupAttachment`; o `Targets` inline do
Target Group exige o alvo na mesma stack).

Por isso, ao concluir a stack `asset-sirius-compute`, o orquestrador chama
`register_alb_targets`, que sincroniza dois Target Groups:

| Target Group | Porta | Alvos | Origem |
|---|---|---|---|
| `TargetGroupArn` (frontend) | 80 | Todas as instâncias que servem o frontend | output `FrontendEc2InstanceIds` (lista separada por vírgulas) |
| `GrafanaTargetGroupArn` | 3000 | Apenas a instância que roda o Grafana | output `GrafanaEc2InstanceId` |

Sem `Port`, o alvo passa a escutar na porta do próprio Target Group.

A sincronização (`sync_target_group`) também **remove os alvos obsoletos**: se o
CloudFormation recriar uma instância, o ID antigo continua registrado e o ALB
passaria a mandar tráfego para uma instância inexistente (erros 502). Antes de
registrar, o orquestrador consulta `describe_target_health`, desregistra o que não
está mais na lista e registra o que falta.

> `describe_target_health` **não é uma operação paginada** na API do ELBv2 —
> chamá-la via `get_paginator()` levanta `Operation cannot be paginated` e
> aborta a execução antes do registro. A chamada é feita direto.

A role IAM da Lambda precisa de `elasticloadbalancing:RegisterTargets`,
`elasticloadbalancing:DeregisterTargets` e `elasticloadbalancing:DescribeTargetHealth`
(a policy de exemplo abaixo já cobre com `elasticloadbalancing:*`).

### Logs e rastreabilidade

Cada linha de log sai no formato `timestamp [NÍVEL] mensagem | chave=valor`, com
timestamp UTC e `flush=True` (a linha é gravada no CloudWatch mesmo se a Lambda
for encerrada por timeout no meio da execução).

| Nível | Significado |
|---|---|
| `INFO` | fluxo normal: status de cada stack, parâmetros resolvidos, outputs, alvos registrados |
| `WARN` | a stack já existia e foi atualizada, ou o Grafana não foi registrado |
| `ERROR` | falha: stack em rollback, dado ausente para o registro, permissão negada, tempo insuficiente |

Linhas para rastrear o registro dos alvos do ALB:

```
[INFO] parametro resolvido | stack=asset-sirius-compute parametro=TargetGroupArn valor=arn:... origem=output asset-sirius-alb.TargetGroupArn
[INFO] outputs da stack | stack=asset-sirius-compute outputs={"GrafanaEc2InstanceId": "i-...", "FrontendEc2InstanceIds": "i-...,i-..."}
[INFO] registro dos alvos do ALB | tg_frontend=arn:... tg_grafana=arn:... instancias_frontend=[...] instancias_grafana=[...]
[INFO] alvos atualmente registrados | target_group=arn:... alvos=[]
[INFO] alvos registrados no Target Group | target_group=arn:... alvos=['i-...', 'i-...']
```

Se aparecer `[ERROR] FrontendEc2InstanceIds ausente nos outputs da stack asset-sirius-compute`
ou `[ERROR] TargetGroupArn do frontend ausente nos outputs da stack asset-sirius-alb`,
o log mostra **qual** dos dois dados faltou e quais outputs estavam disponíveis.

Para ver os logs da função (o nome da função no workflow n8n é `asset-sirius-infra`):

```bash
aws logs tail /aws/lambda/asset-sirius-infra --since 1h --follow --region us-east-1
```

### Timeout da Lambda e retomada (auto-continuação)

A Lambda tem limite máximo de 900s (15 min) e a orquestração das 8 stacks
**não cabe nesse tempo**: numa criação do zero, o tempo medido foi

| Stack | Tempo |
|---|---|
| eips | ~30s |
| network | ~120s (NAT Gateway) |
| alb | ~150s |
| pipeline | ~20s |
| security | ~30s |
| **storage** | **~490s (RDS)** — e só isso |
| crawler + compute | ~150s+ |

Por isso o handler é **auto-contínuo**: cada execução avança até onde o tempo
permite e **reagenda a si mesma** (`lambda:InvokeFunction` com
`InvocationType=Event`) para continuar a partir dali. O stack `tentativa` no
payload conta as continuações, com limite de 12 (`MAX_TENTATIVAS`).

Com isso:
- Stack que ficou em `CREATE_IN_PROGRESS` é apenas **aguardada** na execução
  seguinte — o `update_stack` não é reenviado (o CFN rejeita update em stack
  em andamento com *"can not be updated"*);
- Stacks já atualizadas retornam rápido ("No updates are to be performed");
- A execução para de forma limpa (sem ser morta no meio de um update) quando o
  tempo acaba, e registra `"interrupted": true` / `"reagendado": true`;
- O registro dos alvos do ALB acontece **após** o laço de stacks (e não dentro
  dele), para que uma stack intermediária com falha não impeça o registro;
- Se o registro falhar, a Lambda responde **HTTP 500** e o motivo vai para o
  log. Antes, o retorno era ignorado e a Lambda respondia 200 mesmo com o
  Target Group vazio (ALB respondendo 503 sem nenhum rastro).

A role IAM precisa de `lambda:InvokeFunction` na própria função (a policy de
exemplo abaixo já cobre com `lambda:*`).

### Retry com backoff

Chamadas de API subjectas a throttling (`Rate exceeded`) são repetidas com
backoff exponencial (2s, 4s, 8s... até 60s, 6 tentativas). Isso vale para
`CreateStack`, `UpdateStack`, `RegisterTargets` e `DeregisterTargets`.

Antes o `CreateStack` era disparado para toda stack e o `AlreadyExistsException`
era tratado como erro — o que gerava um `Rate exceeded` no meio da orquestração
(com 4 retries internos do botocore esgotados). Agora o estado da stack é
consultado antes (`describe_stacks`) e só a operação necessária é disparada.

### Testes

Os testes usam o `boto3` mockado e não tocam na AWS:

```bash
python n8n-lambda/test_n8n_lambda.py
```

Cobrem: registro dos alvos, retomada com stack em andamento, retry de
throttling, auto-continuação por falta de tempo, diagnóstico do dado ausente e
limite de continuações.


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
- Outputs: `VpcId`, `PublicSubnetId`, `PublicSubnet2Id`, `PublicSubnetIds`, `PrivateSubnetIds`

**ALB** → Recebe automaticamente:
- `VpcId` (do output da Network)
- `PublicSubnets` (do output PublicSubnetIds da Network)

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
- `Frontend2SubnetId` (PublicSubnet2Id da Network)
- `NodeJsSecurityGroupId` (do output da Security)
- `NodeJsSubnetId` (extraído como PrivateSubnet1Id do Network)
- `TargetGroupArn`, `AlbSgId` e `AlbDns` (do output da ALB)

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
A função registra o log a cada linha (timestamp, nível, mensagem e campos).
```bash
aws logs tail /aws/lambda/asset-sirius-infra --follow --region us-east-1
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
aws cloudformation delete-stack --stack-name asset-sirius-alb
aws cloudformation delete-stack --stack-name asset-sirius-network
aws cloudformation delete-stack --stack-name asset-sirius-eips
```

## Notas de Segurança

- 🔒 A Lambda precisa de acesso ao S3, CloudFormation e recursos AWS
- 🔒 Armazene credenciais AWS em variáveis de ambiente, nunca no código
- 🔒 Configure a Lambda em VPC privada se necessário
- 🔒 Use CloudTrail para auditar todas as operações CloudFormation
