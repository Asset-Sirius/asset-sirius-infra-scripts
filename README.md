## Ordem de execução dos templates CloudFormation

Ao executar os templates de infraestrutura deste projeto, siga a seguinte ordem:

1. EIPs
2. Network
3. ALB (Load Balancer)
4. Pipeline
5. Security
6. Storage
7. Compute

Essa ordem garante que os recursos de rede e pipeline sejam criados antes dos componentes de segurança, armazenamento e computação que dependem deles.

O ALB (`alb.yaml`) é criado depois da rede (precisa de 2 subnets públicas em AZs diferentes) e antes do compute, que restringe o acesso HTTP das instâncias do frontend ao Security Group do ALB.

## Load balancing do frontend

Duas instâncias servem o frontend (porta 80) e são registradas como alvos do Target Group do ALB:

| Instância | Subnet / AZ | Conteúdo |
|---|---|---|
| `GrafanaEc2Instance` | subnet pública 1 (us-east-1a) | Grafana + frontend |
| `FrontendEc2Instance2` | subnet pública 2 (us-east-1b) | apenas o frontend |

O Grafana continua apenas na instância principal e é publicado pelo próprio ALB (listener na porta 3000, Target Group dedicado `AlbGrafanaTargetGroup`), de modo que o iframe do frontend usa o DNS do ALB em vez de um IP público hardcoded. O Target Group do Grafana tem apenas a instância principal registrada, para que os dashboards não divirjam entre instâncias.

O registro dos alvos no Target Group é feito pelo orquestrador (n8n-lambda.py), ao final do ciclo de deploy, porque o CloudFormation não tem recurso para registrar alvo de outra stack. A sincronização também remove alvos obsoletos (quando o CloudFormation recria uma instância, o ID antigo continuaria registrado e o ALB mandaria tráfego para uma instância inexistente).

## Validação dos templates

Antes do deploy, valide os templates contra o schema do CloudFormation:

```bash
pip install cfn-lint
cfn-lint script_cloudformation/*.yaml
```

