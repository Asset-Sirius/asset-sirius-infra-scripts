#!/bin/bash

# ============================================================================
# FUNÇÕES PARA GERENCIAMENTO DE VPC
# ============================================================================

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
