#!/bin/bash

# ============================================================================
# FUNÇÕES PARA GERENCIAMENTO DE RDS (RELATIONAL DATABASE SERVICE)
# ============================================================================

# Função para criar DB Subnet Group
criar_db_subnet_group() {
    local nome="$1"
    local descricao="$2"
    local subnet_id_1="$3"
    local subnet_id_2="$4"

    msg_info "Criando DB Subnet Group '$nome'..."
    pausar 1

    aws ec2 describe-subnets --subnet-ids "$subnet_id_1" "$subnet_id_2" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        msg_erro "Uma ou mais subnets não foram encontradas"
        return 1
    fi

    aws rds create-db-subnet-group \
        --db-subnet-group-name "$nome" \
        --db-subnet-group-description "$descricao" \
        --subnet-ids "$subnet_id_1" "$subnet_id_2" \
        --tags "Key=Name,Value=$nome" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        msg_sucesso "DB Subnet Group criado: $nome"
        echo "" >&2
        return 0
    else
        msg_erro "Falha ao criar DB Subnet Group"
        return 1
    fi
}

# Função para criar instância RDS MySQL
criar_rds_mysql() {
    local db_identifier="$1"
    local db_name="$2"
    local master_user="$3"
    local master_password="$4"
    local subnet_group="$5"
    local sg_id="$6"
    local instance_class="${7:-db.t3.micro}"

    msg_info "Criando instância RDS MySQL '$db_identifier'..."
    msg_info "Isso pode levar alguns minutos..."
    pausar 1

    local rds_endpoint=$(aws rds create-db-instance \
        --db-instance-identifier "$db_identifier" \
        --db-name "$db_name" \
        --engine mysql \
        --engine-version "8.0" \
        --db-instance-class "$instance_class" \
        --allocated-storage 20 \
        --master-username "$master_user" \
        --master-user-password "$master_password" \
        --db-subnet-group-name "$subnet_group" \
        --vpc-security-group-ids "$sg_id" \
        --no-publicly-accessible \
        --storage-type gp3 \
        --backup-retention-period 7 \
        --tags "Key=Name,Value=$db_identifier" \
        --query 'DBInstance.DBInstanceIdentifier' \
        --output text 2>&1)

    if [ $? -eq 0 ]; then
        msg_sucesso "RDS MySQL criado com sucesso!"
        echo "  DB Identifier: $db_identifier" >&2
        echo "  Engine: MySQL 8.0" >&2
        echo "  Classe: $instance_class" >&2
        echo "  Storage: 20 GB (gp3)" >&2
        echo "" >&2
        msg_info "O RDS pode levar alguns minutos para ficar disponível."
        echo "" >&2
        echo "$db_identifier"
        return 0
    else
        msg_erro "Falha ao criar RDS MySQL"
        echo "  Detalhe: $rds_endpoint" >&2
        echo "" >&2
        return 1
    fi
}

# Função para aguardar RDS ficar disponível
aguardar_rds_disponivel() {
    local db_identifier="$1"
    local max_tentativas=120
    local tentativa=0

    msg_info "Aguardando RDS '$db_identifier' ficar disponível..."

    while [ $tentativa -lt $max_tentativas ]; do
        local estado=$(aws rds describe-db-instances \
            --db-instance-identifier "$db_identifier" \
            --query 'DBInstances[0].DBInstanceStatus' \
            --output text 2>/dev/null)

        if [ "$estado" == "available" ]; then
            msg_sucesso "RDS disponível!"
            echo "" >&2
            return 0
        fi

        ((tentativa++))
        sleep 10
    done

    msg_aviso "Timeout aguardando RDS. Verifique o status manualmente."
    return 1
}

# Função para obter endpoint do RDS
obter_endpoint_rds() {
    local db_identifier="$1"

    aws rds describe-db-instances \
        --db-instance-identifier "$db_identifier" \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text 2>/dev/null
}

# Função para deletar instância RDS
deletar_rds() {
    local db_identifier="$1"

    msg_info "Deletando RDS '$db_identifier'..."

    aws rds delete-db-instance \
        --db-instance-identifier "$db_identifier" \
        --skip-final-snapshot \
        --delete-automated-backups > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        msg_sucesso "RDS marcado para exclusão!"
        return 0
    else
        msg_erro "Falha ao deletar RDS"
        return 1
    fi
}

# Função para deletar DB Subnet Group
deletar_db_subnet_group() {
    local nome="$1"

    msg_info "Deletando DB Subnet Group '$nome'..."

    aws rds delete-db-subnet-group \
        --db-subnet-group-name "$nome" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        msg_sucesso "DB Subnet Group deletado!"
        return 0
    else
        msg_erro "Falha ao deletar DB Subnet Group"
        return 1
    fi
}
