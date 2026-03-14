#!/bin/bash

# ============================================================================
# SCRIPT DE DESTRUIÇÃO DA INFRAESTRUTURA COMPLETA - ASSET SIRIUS
# ============================================================================
# Descrição: Derruba toda a infraestrutura AWS do projeto Asset Sirius
# Autor: Asset Sirius Team
# ============================================================================

# Obter o diretório do script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Importar funções auxiliares
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/validacao.sh"
source "$SCRIPT_DIR/lib/aws_helpers.sh"

# ============================================================================
# INÍCIO DO SCRIPT
# ============================================================================
exibir_banner

echo "Destruição da infraestrutura completa Asset Sirius na AWS" >&2
separador

# ============================================================================
# CONFIRMAÇÃO DE SEGURANÇA
# ============================================================================
msg_aviso "ATENÇÃO: Este script irá DESTRUIR todos os recursos da infraestrutura Asset Sirius!"
echo "" >&2
echo "  Serão removidos:" >&2
echo "    - Instâncias EC2 (Frontend, Backend, Python, Bedrock)" >&2
echo "    - RDS MySQL" >&2
echo "    - NAT Gateway + Elastic IP" >&2
echo "    - Internet Gateway" >&2
echo "    - Security Groups" >&2
echo "    - Route Tables" >&2
echo "    - Subnets" >&2
echo "    - VPC" >&2
echo "" >&2

if ! confirmar_acao "Você está prestes a DESTRUIR toda a infraestrutura Asset Sirius."; then
    exit 0
fi

separador
pausar 1

# ============================================================================
# BUSCAR VPC DO PROJETO
# ============================================================================
titulo_etapa "1" "Buscando VPC do projeto"
separador

vpc_id=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=AssetSirius-VPC" \
    --query 'Vpcs[0].VpcId' \
    --output text 2>/dev/null)

if [ -z "$vpc_id" ] || [ "$vpc_id" == "None" ]; then
    msg_erro "VPC 'AssetSirius-VPC' não encontrada. Nada a destruir."
    exit 1
fi

msg_sucesso "VPC encontrada: $vpc_id"
separador
pausar 1

# ============================================================================
# ETAPA 2: ENCERRAR INSTÂNCIAS EC2
# ============================================================================
titulo_etapa "2" "Encerrando instâncias EC2"
separador

instancias=$(aws ec2 describe-instances \
    --filters "Name=vpc-id,Values=$vpc_id" "Name=instance-state-name,Values=running,stopped,pending" \
    --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0]]' \
    --output text 2>/dev/null)

if [ -n "$instancias" ] && [ "$instancias" != "None" ]; then
    echo "$instancias" | while read instance_id nome; do
        [ -z "$instance_id" ] || [ "$instance_id" == "None" ] && continue
        msg_info "Encerrando: $instance_id ($nome)"
        aws ec2 terminate-instances --instance-ids "$instance_id" > /dev/null 2>&1
    done

    # Extrair IDs para aguardar
    instance_ids=$(echo "$instancias" | awk '{print $1}' | grep -v "^$" | grep -v "None" | tr '\n' ' ')

    if [ -n "$instance_ids" ]; then
        msg_info "Aguardando instâncias serem encerradas..."
        aws ec2 wait instance-terminated --instance-ids $instance_ids 2>/dev/null
        msg_sucesso "Todas as instâncias encerradas!"
    fi
else
    msg_info "Nenhuma instância EC2 encontrada."
fi

separador
pausar 1

# ============================================================================
# ETAPA 3: DELETAR RDS
# ============================================================================
titulo_etapa "3" "Deletando RDS MySQL"
separador

rds_status=$(aws rds describe-db-instances \
    --db-instance-identifier "assetsirius-rds" \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text 2>/dev/null)

if [ -n "$rds_status" ] && [ "$rds_status" != "None" ]; then
    msg_info "RDS encontrado (status: $rds_status). Deletando..."
    deletar_rds "assetsirius-rds"

    msg_info "Aguardando RDS ser deletado (pode levar alguns minutos)..."
    aws rds wait db-instance-deleted --db-instance-identifier "assetsirius-rds" 2>/dev/null
    msg_sucesso "RDS deletado!"
else
    msg_info "Nenhum RDS 'assetsirius-rds' encontrado."
fi

separador
pausar 1

# ============================================================================
# ETAPA 4: DELETAR DB SUBNET GROUP
# ============================================================================
titulo_etapa "4" "Deletando DB Subnet Group"
separador

aws rds describe-db-subnet-groups \
    --db-subnet-group-name "assetsirius-db-subnet-group" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    deletar_db_subnet_group "assetsirius-db-subnet-group"
else
    msg_info "DB Subnet Group não encontrado."
fi

separador
pausar 1

# ============================================================================
# ETAPA 5: DELETAR NAT GATEWAY
# ============================================================================
titulo_etapa "5" "Deletando NAT Gateway"
separador

nat_gw_ids=$(aws ec2 describe-nat-gateways \
    --filter "Name=vpc-id,Values=$vpc_id" "Name=state,Values=available,pending" \
    --query 'NatGateways[*].NatGatewayId' \
    --output text 2>/dev/null)

if [ -n "$nat_gw_ids" ] && [ "$nat_gw_ids" != "None" ]; then
    for nat_gw_id in $nat_gw_ids; do
        deletar_nat_gateway "$nat_gw_id"
    done

    # Aguardar NAT Gateways serem deletados
    msg_info "Aguardando NAT Gateways serem deletados..."
    for nat_gw_id in $nat_gw_ids; do
        local_tentativas=0
        while [ $local_tentativas -lt 60 ]; do
            estado=$(aws ec2 describe-nat-gateways \
                --nat-gateway-ids "$nat_gw_id" \
                --query 'NatGateways[0].State' \
                --output text 2>/dev/null)
            if [ "$estado" == "deleted" ] || [ -z "$estado" ]; then
                break
            fi
            ((local_tentativas++))
            sleep 5
        done
    done
    msg_sucesso "NAT Gateways deletados!"
else
    msg_info "Nenhum NAT Gateway encontrado."
fi

separador
pausar 1

# ============================================================================
# ETAPA 6: LIBERAR ELASTIC IPs
# ============================================================================
titulo_etapa "6" "Liberando Elastic IPs"
separador

eip_allocs=$(aws ec2 describe-addresses \
    --filters "Name=tag:Name,Values=AssetSirius-NAT-EIP" \
    --query 'Addresses[*].AllocationId' \
    --output text 2>/dev/null)

if [ -n "$eip_allocs" ] && [ "$eip_allocs" != "None" ]; then
    for alloc_id in $eip_allocs; do
        liberar_elastic_ip "$alloc_id"
    done
else
    msg_info "Nenhum Elastic IP encontrado."
fi

separador
pausar 1

# ============================================================================
# ETAPA 7: DELETAR INTERNET GATEWAY
# ============================================================================
titulo_etapa "7" "Deletando Internet Gateway"
separador

igw_ids=$(obter_internet_gateways_vpc "$vpc_id")

if [ -n "$igw_ids" ] && [ "$igw_ids" != "None" ]; then
    for igw_id in $igw_ids; do
        deletar_internet_gateway "$igw_id" "$vpc_id"
    done
else
    msg_info "Nenhum Internet Gateway encontrado."
fi

separador
pausar 1

# ============================================================================
# ETAPA 8: DELETAR SECURITY GROUPS (exceto o default)
# ============================================================================
titulo_etapa "8" "Deletando Security Groups"
separador

sg_ids=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$vpc_id" \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
    --output text 2>/dev/null)

if [ -n "$sg_ids" ] && [ "$sg_ids" != "None" ]; then
    for sg_id in $sg_ids; do
        deletar_security_group "$sg_id"
    done
else
    msg_info "Nenhum Security Group customizado encontrado."
fi

separador
pausar 1

# ============================================================================
# ETAPA 9: DELETAR ROUTE TABLES (exceto a principal)
# ============================================================================
titulo_etapa "9" "Deletando Route Tables"
separador

# Obter a Route Table principal da VPC
main_rt_id=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$vpc_id" "Name=association.main,Values=true" \
    --query 'RouteTables[0].RouteTableId' \
    --output text 2>/dev/null)

rt_ids=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$vpc_id" \
    --query 'RouteTables[*].RouteTableId' \
    --output text 2>/dev/null)

if [ -n "$rt_ids" ] && [ "$rt_ids" != "None" ]; then
    for rt_id in $rt_ids; do
        # Não deletar a Route Table principal
        if [ "$rt_id" == "$main_rt_id" ]; then
            continue
        fi

        # Desassociar antes de deletar
        assoc_ids=$(aws ec2 describe-route-tables \
            --route-table-ids "$rt_id" \
            --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' \
            --output text 2>/dev/null)

        for assoc_id in $assoc_ids; do
            [ "$assoc_id" == "None" ] && continue
            msg_info "Desassociando Route Table $rt_id ($assoc_id)..."
            aws ec2 disassociate-route-table --association-id "$assoc_id" > /dev/null 2>&1
        done

        deletar_route_table "$rt_id"
    done
else
    msg_info "Nenhuma Route Table customizada encontrada."
fi

separador
pausar 1

# ============================================================================
# ETAPA 10: DELETAR SUBNETS
# ============================================================================
titulo_etapa "10" "Deletando Subnets"
separador

subnet_ids=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$vpc_id" \
    --query 'Subnets[*].SubnetId' \
    --output text 2>/dev/null)

if [ -n "$subnet_ids" ] && [ "$subnet_ids" != "None" ]; then
    for subnet_id in $subnet_ids; do
        deletar_subnet "$subnet_id"
    done
else
    msg_info "Nenhuma Subnet encontrada."
fi

separador
pausar 1

# ============================================================================
# ETAPA 11: DELETAR VPC
# ============================================================================
titulo_etapa "11" "Deletando VPC"
separador

deletar_vpc "$vpc_id"

separador
pausar 1

# ============================================================================
# RESUMO FINAL
# ============================================================================
echo "" >&2
echo "═══════════════════════════════════════════════════════════════════════" >&2
echo "          INFRAESTRUTURA ASSET SIRIUS DESTRUÍDA COM SUCESSO!" >&2
echo "═══════════════════════════════════════════════════════════════════════" >&2
echo "" >&2
msg_info "Todos os recursos foram removidos."
echo "" >&2
echo "═══════════════════════════════════════════════════════════════════════" >&2
echo "" >&2
