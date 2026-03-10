#!/bin/bash

# ============================================================================
# FUNÇÕES PARA GERENCIAMENTO DE TABELAS DE ROTEAMENTO
# ============================================================================

# Função para criar Route Table
criar_route_table() {
    local vpc_id="$1"
    local nome="$2"

    msg_info "Criando Route Table '$nome'..."
    pausar 1

    local rt_id=$(aws ec2 create-route-table \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$nome}]" \
        --query 'RouteTable.RouteTableId' \
        --output text)

    if [ $? -eq 0 ] && [ -n "$rt_id" ]; then
        msg_sucesso "Route Table criada: $rt_id"
        echo "" >&2
        echo "$rt_id"
        return 0
    else
        msg_erro "Falha ao criar Route Table"
        return 1
    fi
}

# Função para criar rota em uma Route Table
# target_type: "gateway" para IGW, "nat-gateway" para NAT GW
criar_rota() {
    local rt_id="$1"
    local destination_cidr="$2"
    local target_type="$3"
    local target_id="$4"

    msg_info "Adicionando rota $destination_cidr -> $target_id na Route Table '$rt_id'..."

    local cmd="aws ec2 create-route --route-table-id $rt_id --destination-cidr-block $destination_cidr"

    case "$target_type" in
        "gateway")
            cmd="$cmd --gateway-id $target_id"
            ;;
        "nat-gateway")
            cmd="$cmd --nat-gateway-id $target_id"
            ;;
        *)
            msg_erro "Tipo de destino desconhecido: $target_type"
            return 1
            ;;
    esac

    eval $cmd > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        msg_sucesso "Rota adicionada com sucesso!"
        echo "" >&2
        return 0
    else
        msg_erro "Falha ao adicionar rota"
        return 1
    fi
}

# Função para associar Route Table a uma Subnet
associar_route_table() {
    local rt_id="$1"
    local subnet_id="$2"

    msg_info "Associando Route Table '$rt_id' à Subnet '$subnet_id'..."

    local assoc_id=$(aws ec2 associate-route-table \
        --route-table-id "$rt_id" \
        --subnet-id "$subnet_id" \
        --query 'AssociationId' \
        --output text)

    if [ $? -eq 0 ] && [ -n "$assoc_id" ]; then
        msg_sucesso "Route Table associada! (Association: $assoc_id)"
        echo "" >&2
        return 0
    else
        msg_erro "Falha ao associar Route Table"
        return 1
    fi
}

# Função para deletar Route Table
deletar_route_table() {
    local rt_id="$1"

    msg_info "Deletando Route Table '$rt_id'..."
    aws ec2 delete-route-table \
        --route-table-id "$rt_id" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        msg_sucesso "Route Table deletada!"
        return 0
    else
        msg_erro "Falha ao deletar Route Table"
        return 1
    fi
}
