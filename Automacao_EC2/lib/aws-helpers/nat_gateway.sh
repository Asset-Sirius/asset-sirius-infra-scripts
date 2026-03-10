#!/bin/bash

# ============================================================================
# FUNÇÕES PARA GERENCIAMENTO DE NAT GATEWAY
# ============================================================================

# Função para alocar Elastic IP
alocar_elastic_ip() {
    local nome="$1"

    msg_info "Alocando Elastic IP '$nome'..."
    pausar 1

    local alloc_id=$(aws ec2 allocate-address \
        --domain vpc \
        --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=$nome}]" \
        --query 'AllocationId' \
        --output text)

    if [ $? -eq 0 ] && [ -n "$alloc_id" ]; then
        msg_sucesso "Elastic IP alocado: $alloc_id"
        echo "" >&2
        echo "$alloc_id"
        return 0
    else
        msg_erro "Falha ao alocar Elastic IP"
        return 1
    fi
}

# Função para criar NAT Gateway
criar_nat_gateway() {
    local subnet_id="$1"
    local allocation_id="$2"
    local nome="$3"

    msg_info "Criando NAT Gateway '$nome' na subnet '$subnet_id'..."
    pausar 1

    local nat_gw_id=$(aws ec2 create-nat-gateway \
        --subnet-id "$subnet_id" \
        --allocation-id "$allocation_id" \
        --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=$nome}]" \
        --query 'NatGateway.NatGatewayId' \
        --output text)

    if [ $? -eq 0 ] && [ -n "$nat_gw_id" ]; then
        msg_sucesso "NAT Gateway criado: $nat_gw_id"
        echo "" >&2
        echo "$nat_gw_id"
        return 0
    else
        msg_erro "Falha ao criar NAT Gateway"
        return 1
    fi
}

# Função para aguardar NAT Gateway ficar disponível
aguardar_nat_gateway() {
    local nat_gw_id="$1"
    local max_tentativas=60
    local tentativa=0

    msg_info "Aguardando NAT Gateway '$nat_gw_id' ficar disponível..."

    while [ $tentativa -lt $max_tentativas ]; do
        local estado=$(aws ec2 describe-nat-gateways \
            --nat-gateway-ids "$nat_gw_id" \
            --query 'NatGateways[0].State' \
            --output text 2>/dev/null)

        if [ "$estado" == "available" ]; then
            msg_sucesso "NAT Gateway disponível!"
            echo "" >&2
            return 0
        elif [ "$estado" == "failed" ]; then
            msg_erro "NAT Gateway falhou ao ser criado"
            return 1
        fi

        ((tentativa++))
        sleep 5
    done

    msg_erro "Timeout aguardando NAT Gateway"
    return 1
}

# Função para obter NAT Gateways de uma VPC
obter_nat_gateways_vpc() {
    local vpc_id="$1"

    aws ec2 describe-nat-gateways \
        --filter "Name=vpc-id,Values=$vpc_id" "Name=state,Values=available" \
        --query 'NatGateways[*].NatGatewayId' \
        --output text 2>/dev/null
}

# Função para deletar NAT Gateway
deletar_nat_gateway() {
    local nat_gw_id="$1"

    msg_info "Deletando NAT Gateway '$nat_gw_id'..."
    aws ec2 delete-nat-gateway \
        --nat-gateway-id "$nat_gw_id" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        msg_sucesso "NAT Gateway deletado!"
        return 0
    else
        msg_erro "Falha ao deletar NAT Gateway"
        return 1
    fi
}
