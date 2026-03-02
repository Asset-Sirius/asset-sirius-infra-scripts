#!/bin/bash

# ============================================================================
# FUNÇÕES PARA GERENCIAMENTO DE RECURSOS AWS (EBS, Elastic IP, etc.)
# ============================================================================

# Função para obter Elastic IP associado a uma instância
obter_elastic_ip_instancia() {
    local instance_id="$1"
    
    aws ec2 describe-addresses \
        --filters "Name=instance-id,Values=$instance_id" \
        --query 'Addresses[*].[PublicIp,AllocationId]' \
        --output text 2>/dev/null
}

# Função para desassociar e liberar Elastic IP
liberar_elastic_ip() {
    local allocation_id="$1"
    
    msg_info "Liberando Elastic IP (Allocation ID: $allocation_id)..."
    
    aws ec2 release-address --allocation-id "$allocation_id" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        msg_sucesso "Elastic IP liberado com sucesso!"
        echo "" >&2
        return 0
    else
        msg_erro "Falha ao liberar Elastic IP"
        echo "" >&2
        return 1
    fi
}

# Função para obter volumes EBS associados a uma instância
obter_volumes_instancia() {
    local instance_id="$1"
    
    aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].BlockDeviceMappings[*].[DeviceName,Ebs.VolumeId,Ebs.DeleteOnTermination]' \
        --output text 2>/dev/null
}

# Função para deletar volume EBS
deletar_volume_ebs() {
    local volume_id="$1"
    
    msg_info "Aguardando volume ficar disponível para exclusão..."
    
    # Aguardar volume ficar disponível
    local max_tentativas=30
    local tentativa=0
    
    while [ $tentativa -lt $max_tentativas ]; do
        local estado=$(aws ec2 describe-volumes \
            --volume-ids "$volume_id" \
            --query 'Volumes[0].State' \
            --output text 2>/dev/null)
        
        if [ "$estado" == "available" ]; then
            break
        fi
        
        ((tentativa++))
        sleep 2
    done
    
    msg_info "Deletando volume EBS $volume_id..."
    
    aws ec2 delete-volume --volume-id "$volume_id" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        msg_sucesso "Volume EBS deletado com sucesso!"
        echo "" >&2
        return 0
    else
        msg_erro "Falha ao deletar volume EBS"
        echo "" >&2
        return 1
    fi
}

# Função para listar snapshots de volumes
obter_snapshots() {
    aws ec2 describe-snapshots \
        --owner-ids self \
        --query 'Snapshots[*].[SnapshotId,VolumeSize,StartTime,Description]' \
        --output text 2>/dev/null
}

# Função para deletar snapshot
deletar_snapshot() {
    local snapshot_id="$1"
    
    msg_info "Deletando snapshot $snapshot_id..."
    
    aws ec2 delete-snapshot --snapshot-id "$snapshot_id" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        msg_sucesso "Snapshot deletado com sucesso!"
        echo "" >&2
        return 0
    else
        msg_erro "Falha ao deletar snapshot"
        echo "" >&2
        return 1
    fi
}

# Função para obter snapshots de volumes específicos
obter_snapshots_volumes() {
    local volume_ids="$1"
    
    if [ -z "$volume_ids" ]; then
        return 1
    fi
    
    aws ec2 describe-snapshots \
        --owner-ids self \
        --filters "Name=volume-id,Values=$volume_ids" \
        --query 'Snapshots[*].[SnapshotId,VolumeId,StartTime,Description]' \
        --output text 2>/dev/null
}

# Função para listar todos os snapshots do usuário
listar_snapshots_usuario() {
    echo "" >&2
    echo "═══════════════════════════════════════════════════════════════════════════════" >&2
    echo "                         SNAPSHOTS DISPONÍVEIS" >&2
    echo "═══════════════════════════════════════════════════════════════════════════════" >&2
    echo "" >&2
    
    local snapshots=$(aws ec2 describe-snapshots \
        --owner-ids self \
        --query 'Snapshots[*].[SnapshotId,VolumeId,VolumeSize,StartTime]' \
        --output text 2>/dev/null)
    
    if [ -z "$snapshots" ]; then
        msg_info "Nenhum snapshot encontrado."
        echo "" >&2
        return 1
    fi
    
    echo "$snapshots" | awk 'BEGIN {
        printf "%-4s %-25s %-20s %-10s %-30s\n", "Nº", "SNAPSHOT ID", "VOLUME ID", "TAMANHO", "DATA" | "cat >&2"
        printf "%-4s %-25s %-20s %-10s %-30s\n", "----", "-------------------------", "--------------------", "----------", "------------------------------" | "cat >&2"
    }
    {
        printf "%-4d %-25s %-20s %-10s %-30s\n", NR, $1, $2, $3" GB", $4 | "cat >&2"
    }'
    
    echo "" >&2
    echo "═══════════════════════════════════════════════════════════════════════════════" >&2
    echo "" >&2
    
    return 0
}

# Função para obter recursos associados à instância
obter_recursos_associados() {
    local instance_id="$1"
    
    echo "" >&2
    echo "═══════════════════════════════════════════════════════════════════════════════" >&2
    echo "                    RECURSOS ASSOCIADOS À INSTÂNCIA" >&2
    echo "═══════════════════════════════════════════════════════════════════════════════" >&2
    echo "" >&2
    
    # Obter informações da instância
    local info=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0]' \
        --output json 2>/dev/null)
    
    if [ -z "$info" ]; then
        msg_erro "Não foi possível obter informações da instância."
        return 1
    fi
    
    # Elastic IP
    local elastic_ip=$(echo "$info" | grep -oP '"PublicIpAddress":\s*"\K[^"]+' 2>/dev/null)
    if [ -n "$elastic_ip" ] && [ "$elastic_ip" != "null" ]; then
        echo "  ✓ Elastic IP: $elastic_ip" >&2
    fi
    
    # Volumes EBS
    local volumes=$(obter_volumes_instancia "$instance_id")
    if [ -n "$volumes" ]; then
        echo "  ✓ Volumes EBS:" >&2
        echo "$volumes" | while read device volume_id delete_on_termination; do
            echo "    - $device: $volume_id (DeleteOnTermination: $delete_on_termination)" >&2
        done
    fi
    
    # Security Group
    local sg_id=$(echo "$info" | grep -oP '"GroupId":\s*"\K[^"]+' | head -1 2>/dev/null)
    if [ -n "$sg_id" ]; then
        echo "  ✓ Security Group: $sg_id" >&2
    fi
    
    # Key Pair
    local key_name=$(echo "$info" | grep -oP '"KeyName":\s*"\K[^"]+' 2>/dev/null)
    if [ -n "$key_name" ]; then
        echo "  ✓ Key Pair: $key_name" >&2
    fi
    
    # Subnet
    local subnet_id=$(echo "$info" | grep -oP '"SubnetId":\s*"\K[^"]+' 2>/dev/null)
    if [ -n "$subnet_id" ]; then
        echo "  ✓ Subnet: $subnet_id" >&2
    fi
    
    # VPC
    local vpc_id=$(echo "$info" | grep -oP '"VpcId":\s*"\K[^"]+' 2>/dev/null)
    if [ -n "$vpc_id" ]; then
        echo "  ✓ VPC: $vpc_id" >&2
        
        # Verificar recursos adicionais da VPC
        local nat_gateways=$(obter_nat_gateways_vpc "$vpc_id" | wc -l)
        if [ "$nat_gateways" -gt 0 ]; then
            echo "    • NAT Gateways: $nat_gateways" >&2
        fi
        
        local igws=$(obter_internet_gateways_vpc "$vpc_id" | wc -w)
        if [ "$igws" -gt 0 ]; then
            echo "    • Internet Gateways: $igws" >&2
        fi
    fi
    
    # Snapshots relacionados aos volumes
    if [ -n "$volumes" ]; then
        local volume_ids=$(echo "$volumes" | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
        local snapshots=$(obter_snapshots_volumes "$volume_ids" | wc -l)
        if [ "$snapshots" -gt 0 ]; then
            echo "  ✓ Snapshots: $snapshots" >&2
        fi
    fi
    
    echo "" >&2
    echo "═══════════════════════════════════════════════════════════════════════════════" >&2
    echo "" >&2
}
