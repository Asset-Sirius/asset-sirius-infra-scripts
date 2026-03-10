#!/bin/bash

# ============================================================================
# FUNÇÕES PARA GERENCIAMENTO DE RECURSOS AWS (EBS, Elastic IP, etc.)
# ============================================================================

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


