#!/bin/bash

# ============================================================================
# FUNÇÕES PARA GERENCIAMENTO DE VPC
# ============================================================================

# Função para criar VPC
criar_vpc() {
    local cidr_block="$1"
    local nome="$2"

    msg_info "Criando VPC '$nome' com CIDR $cidr_block..."
    pausar 1

    local vpc_id=$(aws ec2 create-vpc \
        --cidr-block "$cidr_block" \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$nome}]" \
        --query 'Vpc.VpcId' \
        --output text)

    if [ $? -ne 0 ] || [ -z "$vpc_id" ]; then
        msg_erro "Falha ao criar VPC"
        return 1
    fi

    # Habilitar DNS Support
    aws ec2 modify-vpc-attribute \
        --vpc-id "$vpc_id" \
        --enable-dns-support '{"Value":true}' > /dev/null 2>&1

    # Habilitar DNS Hostnames
    aws ec2 modify-vpc-attribute \
        --vpc-id "$vpc_id" \
        --enable-dns-hostnames '{"Value":true}' > /dev/null 2>&1

    msg_sucesso "VPC criada com sucesso!"
    echo "  VPC ID: $vpc_id" >&2
    echo "  CIDR: $cidr_block" >&2
    echo "" >&2

    echo "$vpc_id"
    return 0
}

# Função para obter VPC padrão
obter_vpc_padrao() {
    local vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' \
        --output text)
    
    if [ "$vpc_id" != "None" ] && [ -n "$vpc_id" ]; then
        echo "$vpc_id"
        return 0
    else
        echo "" >&2
        return 1
    fi
}

# Função para deletar VPC
deletar_vpc() {
    local vpc_id="$1"

    msg_info "Deletando VPC '$vpc_id'..."
    aws ec2 delete-vpc --vpc-id "$vpc_id" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        msg_sucesso "VPC deletada!"
        return 0
    else
        msg_erro "Falha ao deletar VPC"
        return 1
    fi
}
