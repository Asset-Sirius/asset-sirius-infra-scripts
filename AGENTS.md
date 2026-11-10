Objetivo
Explica a função e dependências dos diretórios script_cloudformation e n8n-lambda. Ignorar a pasta app.

1) script_cloudformation — propósito e dependências
- O que é: coleção de templates CloudFormation separados por responsabilidade.
- Principais templates:
  - network.yaml — VPC, subnets, IGW, NAT, route tables.
    - Outputs obrigatórios: VpcId, PublicSubnetId, PrivateSubnetIds (vírgula-separated), PublicSubnetIds (vírgula-separated, subnets públicas do ALB).
  - eips.yaml — reserva EIPs e exporta AllocationIds/PublicIps.
  - pipeline.yaml — Lambdas e Glue.
  - alb.yaml — ALB internet-facing (porta 80), SG do ALB e Target Group da aplicação frontend.
    - Depende de: Network (VpcId, PublicSubnetIds).
    - Outputs: TargetGroupArn, AlbSgId, AlbDns (com Export ${AWS::StackName}-...).
  - security.yaml — Security Groups (NodeJs, Grafana, RDS).
    - Outputs: NodeJsEc2SecurityGroupId, GrafanaEc2SecurityGroupId, RdsSecurityGroupId.
    - A porta do frontend (80) não é liberada aqui: o acesso direto é bloqueado e a entrada passa a vir do SG do ALB (regra criada em compute.yaml).
  - storage.yaml — S3 buckets (bronze/silver/gold) e RDS MySQL.
    - Depende de: PrivateSubnet2Id, PrivateSubnet3Id (extraídos de PrivateSubnetIds) e RdsSecurityGroupId.
    - Outputs: nomes de buckets e endpoint/porta do RDS.
  - crawler.yaml — Glue Crawler que varre s3://asset-sirius-gold/cvm/.
  - compute.yaml — EC2 Node.js e Grafana, EBS volume, associa EIPs.
    - Depende de: Security (SGs), Network (subnets), EIPs (AllocationIds), ALB (TargetGroupArn, AlbSgId).
    - A entrada HTTP da instância Grafana/Frontend vem só do SG do ALB (ingress em compute.yaml).
    - O registro da instância como alvo do Target Group é feito pelo orquestrador (n8n-lambda.py): o CloudFormation não tem recurso para registrar alvo de outra stack.
- deploy.yaml — cria bucket infra e placeholder Lambda (uso opcional).
- Ordem de deploy (usada pelo orquestrador):
  1. asset-sirius-eips (eips.yaml)
  2. asset-sirius-network (network.yaml)
  3. asset-sirius-alb (alb.yaml)
  4. asset-sirius-pipeline (pipeline.yaml)
  5. asset-sirius-security (security.yaml)
  6. asset-sirius-storage (storage.yaml)
  7. asset-sirius-crawler (crawler.yaml)
  8. asset-sirius-compute (compute.yaml)
- Como os parâmetros são passados:
  - Orquestrador (Lambda) lê outputs da stack anterior e passa como parâmetros à próxima.
  - PrivateSubnetIds é splitado por vírgula para gerar PrivateSubnet1/2/3.
- Dicas rápidas:
  - Garanta o bucket S3 com templates antes de executar.
  - Verifique/ajuste KeyName, AMI, roles e ARNs antes do deploy.
  - Valide os templates com `cfn-lint script_cloudformation/*.yaml` antes do deploy.
  - Teste em conta/região de dev antes de rodar em produção.

2) n8n-lambda — propósito e como usar
- O que é: código Python para ser empacotado e implantado como uma AWS Lambda cujo job é orquestrar a criação das stacks CloudFormation.
- Arquivos principais:
  - n8n-lambda.py — handler: lambda_handler(event, context). Recupera templates do S3, resolve parâmetros, cria/atualiza stacks, faz polling do status.
  - README.md — instruções de uso, permissões necessárias e exemplos de invocação.
  - n8n JSONs — workflows para upload dos templates ao bucket S3 e invocação da Lambda.
- Observações operacionais:
  - Handler para criar/atualizar stacks: use runtime Python 3.11+.
  - Lambda precisa de IAM com permissões: CloudFormation create/update/describe, S3 GetObject/ListBucket e permissões para criar/atualizar recursos que os templates exigirem.
  - Timeout do Lambda: o script faz polling por stack (padrão 1h); configure timeout da função para cobrir o tempo total esperado.
  - Uso típico: invocar a Lambda com event contendo template_bucket e template_key_prefix; o orquestrador baixa templates do S3 e executa.
- Observação: pasta n8n-lambda foi criada para ser colocada no Lambda e também contém fluxos n8n para automação do upload + trigger.

Pontos de atenção
- Verifique valores padrões/hardcoded nos templates e em STACKS_CONFIG (KeyName, AMI, ARNs, imagens Docker, Layer ARNs) antes de rodar em outra conta/região.
- Ajuste permissões IAM da Lambda conforme o princípio do menor privilégio.
