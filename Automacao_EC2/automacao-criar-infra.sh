#!/bin/bash

# ============================================================================
# SCRIPT DE CRIAÇÃO DA INFRAESTRUTURA COMPLETA - ASSET SIRIUS
# ============================================================================
# Descrição: Levanta toda a infraestrutura AWS baseada na arquitetura de
#            referência do projeto Asset Sirius
# Autor: Asset Sirius Team
# ============================================================================

# Obter o diretório do script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Importar funções auxiliares
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/validacao.sh"
source "$SCRIPT_DIR/lib/aws_helpers.sh"

# ============================================================================
# CONFIGURAÇÕES DA INFRAESTRUTURA
# ============================================================================
REGIAO="us-east-1"
ZONA_PRIMARIA="us-east-1a"
ZONA_SECUNDARIA="us-east-1b"

# VPC
VPC_CIDR="10.0.0.0/16"
VPC_NOME="AssetSirius-VPC"

# Subnets
SUBNET_PUBLICA_CIDR="10.0.0.0/24"
SUBNET_PRIVADA_1_CIDR="10.0.1.0/24"
SUBNET_PRIVADA_2_CIDR="10.0.2.0/24"
SUBNET_RDS_AUX_CIDR="10.0.3.0/24"

# Instâncias EC2
IMAGE_ID="ami-0b6c6ebed2801a5cb"
INSTANCE_TYPE="t2.micro"

# Par de Chaves
PASTA_PAR_CHAVES="$HOME/Downloads/par de chaves EC2"

# ============================================================================
# INÍCIO DO SCRIPT
# ============================================================================
exibir_banner

echo "Gerenciamento da Infraestrutura Asset Sirius na AWS" >&2
echo "Região: $REGIAO | Zona: $ZONA_PRIMARIA" >&2
separador

opcao_menu=$(exibir_menu_principal)

case $opcao_menu in
    1)
        msg_info "Iniciando criação da infraestrutura..."
        separador
        pausar 2
        ;;
    2)
        msg_info "Redirecionando para o script de destruição da infraestrutura..."
        separador
        pausar 1
        bash "$SCRIPT_DIR/automacao-derrubar-infra.sh"
        exit $?
        ;;
    *)
        msg_erro "Opção inválida! Escolha 1 ou 2."
        exit 1
        ;;
esac

# ============================================================================
# ETAPA 1: CRIAR VPC
# ============================================================================
titulo_etapa "1" "Criando VPC ($VPC_CIDR)"
separador

vpc_id=$(criar_vpc "$VPC_CIDR" "$VPC_NOME")

if [ $? -ne 0 ] || [ -z "$vpc_id" ]; then
    msg_erro "Falha ao criar VPC. Abortando."
    exit 1
fi

msg_sucesso "VPC criada: $vpc_id"
separador
pausar 2

# ============================================================================
# ETAPA 2: CRIAR SUBNETS
# ============================================================================
titulo_etapa "2" "Criando Subnets (1 pública + 2 privadas)"
separador

# Subnet Pública (10.0.0.0/24)
msg_info ">> Subnet Pública"
subnet_publica_id=$(criar_subnet "$vpc_id" "$SUBNET_PUBLICA_CIDR" "$ZONA_PRIMARIA" "AssetSirius-Subnet-Publica")

if [ $? -ne 0 ] || [ -z "$subnet_publica_id" ]; then
    msg_erro "Falha ao criar Subnet Pública. Abortando."
    exit 1
fi

habilitar_ip_publico_subnet "$subnet_publica_id"

# Subnet Privada 1 (10.0.1.0/24)
msg_info ">> Subnet Privada 1"
subnet_privada_1_id=$(criar_subnet "$vpc_id" "$SUBNET_PRIVADA_1_CIDR" "$ZONA_PRIMARIA" "AssetSirius-Subnet-Privada-1")

if [ $? -ne 0 ] || [ -z "$subnet_privada_1_id" ]; then
    msg_erro "Falha ao criar Subnet Privada 1. Abortando."
    exit 1
fi

# Subnet Privada 2 (10.0.2.0/24)
msg_info ">> Subnet Privada 2"
subnet_privada_2_id=$(criar_subnet "$vpc_id" "$SUBNET_PRIVADA_2_CIDR" "$ZONA_PRIMARIA" "AssetSirius-Subnet-Privada-2")

if [ $? -ne 0 ] || [ -z "$subnet_privada_2_id" ]; then
    msg_erro "Falha ao criar Subnet Privada 2. Abortando."
    exit 1
fi

# Subnet auxiliar para RDS (AWS exige subnets em pelo menos 2 AZs para o DB Subnet Group)
msg_info ">> Subnet auxiliar RDS (us-east-1b - necessária para DB Subnet Group)"
subnet_rds_aux_id=$(criar_subnet "$vpc_id" "$SUBNET_RDS_AUX_CIDR" "$ZONA_SECUNDARIA" "AssetSirius-Subnet-RDS-Aux")

if [ $? -ne 0 ] || [ -z "$subnet_rds_aux_id" ]; then
    msg_erro "Falha ao criar Subnet auxiliar RDS. Abortando."
    exit 1
fi

msg_sucesso "Todas as Subnets criadas com sucesso!"
separador
pausar 2

# ============================================================================
# ETAPA 3: CRIAR INTERNET GATEWAY
# ============================================================================
titulo_etapa "3" "Criando Internet Gateway"
separador

igw_id=$(criar_internet_gateway "$vpc_id" "AssetSirius-IGW")

if [ $? -ne 0 ] || [ -z "$igw_id" ]; then
    msg_erro "Falha ao criar Internet Gateway. Abortando."
    exit 1
fi

separador
pausar 2

# ============================================================================
# ETAPA 4: CRIAR NAT GATEWAY
# ============================================================================
titulo_etapa "4" "Criando NAT Gateway (na Subnet Pública)"
separador

eip_alloc_id=$(alocar_elastic_ip "AssetSirius-NAT-EIP")

if [ $? -ne 0 ] || [ -z "$eip_alloc_id" ]; then
    msg_erro "Falha ao alocar Elastic IP. Abortando."
    exit 1
fi

nat_gw_id=$(criar_nat_gateway "$subnet_publica_id" "$eip_alloc_id" "AssetSirius-NAT-GW")

if [ $? -ne 0 ] || [ -z "$nat_gw_id" ]; then
    msg_erro "Falha ao criar NAT Gateway. Abortando."
    exit 1
fi

aguardar_nat_gateway "$nat_gw_id"

if [ $? -ne 0 ]; then
    msg_erro "NAT Gateway não ficou disponível. Abortando."
    exit 1
fi

separador
pausar 2

# ============================================================================
# ETAPA 5: CRIAR TABELAS DE ROTEAMENTO
# ============================================================================
titulo_etapa "5" "Criando Tabelas de Roteamento"
separador

# Route Table Pública: 0.0.0.0/0 -> Internet Gateway
msg_info ">> Route Table Pública"
rt_publica_id=$(criar_route_table "$vpc_id" "AssetSirius-RT-Publica")

if [ $? -ne 0 ] || [ -z "$rt_publica_id" ]; then
    msg_erro "Falha ao criar Route Table Pública. Abortando."
    exit 1
fi

criar_rota "$rt_publica_id" "0.0.0.0/0" "gateway" "$igw_id"
associar_route_table "$rt_publica_id" "$subnet_publica_id"
msg_sucesso "Route Table Pública configurada: $rt_publica_id"
separador

# Route Table Privada: 0.0.0.0/0 -> NAT Gateway
msg_info ">> Route Table Privada"
rt_privada_id=$(criar_route_table "$vpc_id" "AssetSirius-RT-Privada")

if [ $? -ne 0 ] || [ -z "$rt_privada_id" ]; then
    msg_erro "Falha ao criar Route Table Privada. Abortando."
    exit 1
fi

criar_rota "$rt_privada_id" "0.0.0.0/0" "nat-gateway" "$nat_gw_id"
associar_route_table "$rt_privada_id" "$subnet_privada_1_id"
associar_route_table "$rt_privada_id" "$subnet_privada_2_id"
associar_route_table "$rt_privada_id" "$subnet_rds_aux_id"
msg_sucesso "Route Table Privada configurada: $rt_privada_id"
separador
pausar 2

# ============================================================================
# ETAPA 6: PAR DE CHAVES
# ============================================================================
titulo_etapa "6" "Configuração do Par de Chaves"
separador

nome_par_chaves=$(gerenciar_par_chaves "$PASTA_PAR_CHAVES")

if [ $? -ne 0 ] || [ -z "$nome_par_chaves" ]; then
    msg_erro "Falha ao criar/selecionar o par de chaves. Abortando."
    exit 1
fi

separador
pausar 2

# ============================================================================
# ETAPA 7: CRIAR SECURITY GROUPS
# ============================================================================
titulo_etapa "7" "Criando Security Groups"
separador

# SG Frontend - HTTP(80), HTTPS(443), SSH(22) aberto ao público
msg_info ">> Security Group Frontend"
sg_frontend_id=$(criar_security_group_custom "AssetSirius-SG-Frontend" "SG para EC2 Frontend - acesso publico" "$vpc_id")
if [ $? -ne 0 ] || [ -z "$sg_frontend_id" ]; then
    msg_erro "Falha ao criar SG Frontend. Abortando."
    exit 1
fi
adicionar_regra_ingress "$sg_frontend_id" "tcp" "80" "0.0.0.0/0"
adicionar_regra_ingress "$sg_frontend_id" "tcp" "443" "0.0.0.0/0"
adicionar_regra_ingress "$sg_frontend_id" "tcp" "22" "0.0.0.0/0"
msg_sucesso "SG Frontend criado: $sg_frontend_id"
separador

# SG Backend - porta 8080 e SSH acessível apenas dentro da VPC
msg_info ">> Security Group Backend"
sg_backend_id=$(criar_security_group_custom "AssetSirius-SG-Backend" "SG para EC2 Backend - acesso interno VPC" "$vpc_id")
if [ $? -ne 0 ] || [ -z "$sg_backend_id" ]; then
    msg_erro "Falha ao criar SG Backend. Abortando."
    exit 1
fi
adicionar_regra_ingress "$sg_backend_id" "tcp" "8080" "$VPC_CIDR"
adicionar_regra_ingress "$sg_backend_id" "tcp" "22" "$VPC_CIDR"
msg_sucesso "SG Backend criado: $sg_backend_id"
separador

# SG Python - porta 5000 e SSH acessível apenas dentro da VPC
msg_info ">> Security Group Python"
sg_python_id=$(criar_security_group_custom "AssetSirius-SG-Python" "SG para EC2 Python - acesso interno VPC" "$vpc_id")
if [ $? -ne 0 ] || [ -z "$sg_python_id" ]; then
    msg_erro "Falha ao criar SG Python. Abortando."
    exit 1
fi
adicionar_regra_ingress "$sg_python_id" "tcp" "5000" "$VPC_CIDR"
adicionar_regra_ingress "$sg_python_id" "tcp" "22" "$VPC_CIDR"
msg_sucesso "SG Python criado: $sg_python_id"
separador

# SG Bedrock - portas 443, 8080 e SSH acessível apenas dentro da VPC
msg_info ">> Security Group Bedrock"
sg_bedrock_id=$(criar_security_group_custom "AssetSirius-SG-Bedrock" "SG para EC2 Bedrock - acesso interno VPC" "$vpc_id")
if [ $? -ne 0 ] || [ -z "$sg_bedrock_id" ]; then
    msg_erro "Falha ao criar SG Bedrock. Abortando."
    exit 1
fi
adicionar_regra_ingress "$sg_bedrock_id" "tcp" "443" "$VPC_CIDR"
adicionar_regra_ingress "$sg_bedrock_id" "tcp" "8080" "$VPC_CIDR"
adicionar_regra_ingress "$sg_bedrock_id" "tcp" "22" "$VPC_CIDR"
msg_sucesso "SG Bedrock criado: $sg_bedrock_id"
separador

# SG RDS - MySQL (3306) acessível apenas dentro da VPC
msg_info ">> Security Group RDS"
sg_rds_id=$(criar_security_group_custom "AssetSirius-SG-RDS" "SG para RDS MySQL - acesso interno VPC" "$vpc_id")
if [ $? -ne 0 ] || [ -z "$sg_rds_id" ]; then
    msg_erro "Falha ao criar SG RDS. Abortando."
    exit 1
fi
adicionar_regra_ingress "$sg_rds_id" "tcp" "3306" "$VPC_CIDR"
msg_sucesso "SG RDS criado: $sg_rds_id"
separador
pausar 2

# ============================================================================
# ETAPA 8: CRIAR INSTÂNCIAS EC2
# ============================================================================
titulo_etapa "8" "Criando Instâncias EC2"
separador

# EC2 Front-End (Subnet Pública - com IP público)
msg_info ">> EC2 Front-End (Subnet Pública)"
ec2_frontend_id=$(criar_instancia_infra \
    "AssetSirius-EC2-Frontend" \
    "$IMAGE_ID" \
    "$INSTANCE_TYPE" \
    "$nome_par_chaves" \
    "$subnet_publica_id" \
    "$sg_frontend_id" \
    "" \
    "true")

if [ $? -ne 0 ] || [ -z "$ec2_frontend_id" ]; then
    msg_erro "Falha ao criar EC2 Frontend. Abortando."
    exit 1
fi
separador

# EC2 Back-End (Subnet Privada 1 - sem IP público)
msg_info ">> EC2 Back-End (Subnet Privada 1)"
ec2_backend_id=$(criar_instancia_infra \
    "AssetSirius-EC2-Backend" \
    "$IMAGE_ID" \
    "$INSTANCE_TYPE" \
    "$nome_par_chaves" \
    "$subnet_privada_1_id" \
    "$sg_backend_id" \
    "" \
    "false")

if [ $? -ne 0 ] || [ -z "$ec2_backend_id" ]; then
    msg_erro "Falha ao criar EC2 Backend. Abortando."
    exit 1
fi
separador

# EC2 Python (Subnet Privada 1 - sem IP público)
msg_info ">> EC2 Python (Subnet Privada 1)"
ec2_python_id=$(criar_instancia_infra \
    "AssetSirius-EC2-Python" \
    "$IMAGE_ID" \
    "$INSTANCE_TYPE" \
    "$nome_par_chaves" \
    "$subnet_privada_1_id" \
    "$sg_python_id" \
    "" \
    "false")

if [ $? -ne 0 ] || [ -z "$ec2_python_id" ]; then
    msg_erro "Falha ao criar EC2 Python. Abortando."
    exit 1
fi
separador

# EC2 Bedrock (Subnet Privada 1 - sem IP público)
msg_info ">> EC2 Bedrock (Subnet Privada 1)"
ec2_bedrock_id=$(criar_instancia_infra \
    "AssetSirius-EC2-Bedrock" \
    "$IMAGE_ID" \
    "$INSTANCE_TYPE" \
    "$nome_par_chaves" \
    "$subnet_privada_1_id" \
    "$sg_bedrock_id" \
    "" \
    "false")

if [ $? -ne 0 ] || [ -z "$ec2_bedrock_id" ]; then
    msg_erro "Falha ao criar EC2 Bedrock. Abortando."
    exit 1
fi

msg_sucesso "Todas as instâncias EC2 criadas com sucesso!"
separador
pausar 2

# ============================================================================
# ETAPA 9: CRIAR RDS (MYSQL)
# ============================================================================
titulo_etapa "9" "Criando banco de dados RDS MySQL (Subnet Privada 2)"
separador

# Criar DB Subnet Group (exige subnets em 2 AZs diferentes)
msg_info "Criando DB Subnet Group..."
criar_db_subnet_group \
    "assetsirius-db-subnet-group" \
    "Subnet Group para RDS Asset Sirius" \
    "$subnet_privada_2_id" \
    "$subnet_rds_aux_id"

if [ $? -ne 0 ]; then
    msg_erro "Falha ao criar DB Subnet Group. Abortando."
    exit 1
fi

# Credenciais do banco de dados
msg_info "Configuração das credenciais do banco de dados:"
separador
db_usuario=$(obter_input_validado "Digite o usuário master do banco de dados:")
db_senha=$(obter_senha_validada "Digite a senha master do banco de dados (mínimo 8 caracteres):" 8)

rds_id=$(criar_rds_mysql \
    "assetsirius-rds" \
    "assetsirius" \
    "$db_usuario" \
    "$db_senha" \
    "assetsirius-db-subnet-group" \
    "$sg_rds_id" \
    "db.t3.micro")

if [ $? -ne 0 ] || [ -z "$rds_id" ]; then
    msg_erro "Falha ao criar RDS MySQL."
    msg_aviso "A infraestrutura EC2 foi criada, mas o RDS não foi provisionado."
fi

separador
pausar 2

# ============================================================================
# ETAPA 10: ENVIAR CHAVE .PEM PARA EC2 FRONTEND (VIA SCP)
# ============================================================================
titulo_etapa "10" "Enviando chave .pem para EC2 Frontend (acesso às subnets privadas)"
separador

CAMINHO_CHAVE_PEM="$PASTA_PAR_CHAVES/${nome_par_chaves}.pem"

msg_info "Obtendo IP público da EC2 Frontend..."
ip_frontend=$(obter_ip_publico_instancia "$ec2_frontend_id")

if [ -z "$ip_frontend" ]; then
    msg_aviso "IP público da EC2 Frontend não disponível ainda."
    msg_aviso "Após a instância inicializar, execute manualmente:"
    echo "  scp -i \"$CAMINHO_CHAVE_PEM\" \"$CAMINHO_CHAVE_PEM\" ubuntu@<IP_PUBLICO>:/home/ubuntu/.ssh/${nome_par_chaves}.pem" >&2
else
    msg_info "IP Público Frontend: $ip_frontend"
    aguardar_ssh_e_enviar_chave "$ip_frontend" "$CAMINHO_CHAVE_PEM" "$nome_par_chaves"
fi

separador
pausar 2

# ============================================================================
# RESUMO FINAL
# ============================================================================
echo "" >&2
echo "═══════════════════════════════════════════════════════════════════════" >&2
echo "           INFRAESTRUTURA ASSET SIRIUS CRIADA COM SUCESSO!" >&2
echo "═══════════════════════════════════════════════════════════════════════" >&2
echo "" >&2

msg_info "Recursos criados:"
echo "" >&2
echo "  VPC:                  $vpc_id ($VPC_CIDR)" >&2
echo "" >&2
echo "  Subnet Pública:       $subnet_publica_id ($SUBNET_PUBLICA_CIDR)" >&2
echo "  Subnet Privada 1:     $subnet_privada_1_id ($SUBNET_PRIVADA_1_CIDR)" >&2
echo "  Subnet Privada 2:     $subnet_privada_2_id ($SUBNET_PRIVADA_2_CIDR)" >&2
echo "  Subnet RDS Aux:       $subnet_rds_aux_id ($SUBNET_RDS_AUX_CIDR)" >&2
echo "" >&2
echo "  Internet Gateway:     $igw_id" >&2
echo "  NAT Gateway:          $nat_gw_id" >&2
echo "  Elastic IP (NAT):     $eip_alloc_id" >&2
echo "" >&2
echo "  Route Table Pública:  $rt_publica_id (0.0.0.0/0 -> IGW)" >&2
echo "  Route Table Privada:  $rt_privada_id (0.0.0.0/0 -> NAT GW)" >&2
echo "" >&2
echo "  EC2 Frontend:         $ec2_frontend_id (Subnet Pública)" >&2
echo "  EC2 Backend:          $ec2_backend_id (Subnet Privada 1)" >&2
echo "  EC2 Python:           $ec2_python_id (Subnet Privada 1)" >&2
echo "  EC2 Bedrock:          $ec2_bedrock_id (Subnet Privada 1)" >&2
echo "" >&2
echo "  RDS MySQL:            $rds_id (Subnet Privada 2)" >&2
echo "" >&2

# IP público do Frontend
ip_frontend=$(obter_ip_publico_instancia "$ec2_frontend_id")
if [ -n "$ip_frontend" ]; then
    echo "  IP Público Frontend:  $ip_frontend" >&2
    echo "" >&2
fi

echo "═══════════════════════════════════════════════════════════════════════" >&2
echo "" >&2

# Comando SSH para o Frontend
msg_info "Para acessar o EC2 Frontend via SSH:"
CAMINHO_PAR_CHAVES="$PASTA_PAR_CHAVES/${nome_par_chaves}.pem"
if [ -n "$ip_frontend" ]; then
    echo "  ssh -i \"$CAMINHO_PAR_CHAVES\" ubuntu@$ip_frontend" >&2
else
    echo "  ssh -i \"$CAMINHO_PAR_CHAVES\" ubuntu@<IP_PUBLICO>" >&2
fi
echo "" >&2

msg_info "O RDS pode levar alguns minutos para ficar disponível."
msg_info "Para verificar o endpoint do RDS:"
echo "  aws rds describe-db-instances --db-instance-identifier assetsirius-rds --query 'DBInstances[0].Endpoint.Address' --output text" >&2
echo "" >&2
echo "═══════════════════════════════════════════════════════════════════════" >&2
echo "" >&2
