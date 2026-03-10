#!/bin/bash

# ============================================================================
# FUNÇÕES PARA GERENCIAMENTO DE INTERNET GATEWAY
# ============================================================================

# Função para criar Internet Gateway e anexar à VPC
criar_internet_gateway() {
    local vpc_id="$1"
    local nome="$2"

    msg_info "Criando Internet Gateway '$nome'..."
    pausar 1

    local igw_id=$(aws ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$nome}]" \
        --query 'InternetGateway.InternetGatewayId' \
        --output text)

    if [ $? -ne 0 ] || [ -z "$igw_id" ]; then
        msg_erro "Falha ao criar Internet Gateway"
        return 1
    fi

    msg_info "Anexando Internet Gateway '$igw_id' à VPC '$vpc_id'..."
    aws ec2 attach-internet-gateway \
        --internet-gateway-id "$igw_id" \
        --vpc-id "$vpc_id" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        msg_sucesso "Internet Gateway criado e anexado à VPC!"
        echo "  Internet Gateway ID: $igw_id" >&2
        echo "" >&2
        echo "$igw_id"
        return 0
    else
        msg_erro "Falha ao anexar Internet Gateway à VPC"
        return 1
    fi
}

# Função para obter Internet Gateways de uma VPC
obter_internet_gateways_vpc() {
    local vpc_id="$1"

    aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=$vpc_id" \
        --query 'InternetGateways[*].InternetGatewayId' \
        --output text 2>/dev/null
}

# Função para desanexar e deletar Internet Gateway
deletar_internet_gateway() {
    local igw_id="$1"
    local vpc_id="$2"

    msg_info "Desanexando Internet Gateway '$igw_id' da VPC..."
    aws ec2 detach-internet-gateway \
        --internet-gateway-id "$igw_id" \
        --vpc-id "$vpc_id" > /dev/null 2>&1

    msg_info "Deletando Internet Gateway '$igw_id'..."
    aws ec2 delete-internet-gateway \
        --internet-gateway-id "$igw_id" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        msg_sucesso "Internet Gateway deletado!"
        return 0
    else
        msg_erro "Falha ao deletar Internet Gateway"
        return 1
    fi
}
