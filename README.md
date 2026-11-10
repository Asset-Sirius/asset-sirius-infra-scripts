## Ordem de execução dos templates CloudFormation

Ao executar os templates de infraestrutura deste projeto, siga a seguinte ordem:

1. Network
2. ALB (Load Balancer)
3. Pipeline
4. Security
5. Storage
6. Compute

Essa ordem garante que os recursos de rede e pipeline sejam criados antes dos componentes de segurança, armazenamento e computação que dependem deles.

O ALB (`alb.yaml`) é criado depois da rede (precisa de 2 subnets públicas em AZs diferentes) e antes do compute, que restringe o acesso HTTP da instância do frontend ao Security Group do ALB. O registro da instância como alvo do Target Group é feito pelo orquestrador (n8n-lambda.py), ao final do ciclo de deploy.

## Validação dos templates

Antes do deploy, valide os templates contra o schema do CloudFormation:

```bash
pip install cfn-lint
cfn-lint script_cloudformation/*.yaml
```

