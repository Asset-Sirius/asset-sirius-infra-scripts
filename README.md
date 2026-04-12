## Ordem de execução dos templates CloudFormation

Ao executar os templates de infraestrutura deste projeto, siga a seguinte ordem:

1. Network
2. Pipeline
3. Security
4. Storage
5. Compute

Essa ordem garante que os recursos de rede e pipeline sejam criados antes dos componentes de segurança, armazenamento e computação que dependem deles.

