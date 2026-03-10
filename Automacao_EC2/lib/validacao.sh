#!/bin/bash

# ============================================================================
# FUNÇÕES DE VALIDAÇÃO E INPUT
# ============================================================================

# Função para validar confirmação y/n
validar_confirmacao() {
    local mensagem="$1"
    local resposta
    
    read -p "$mensagem (y/n): " resposta >&2
    echo "" >&2
    
    if [[ "$resposta" == "y" || "$resposta" == "Y" ]]; then
        return 0  # true
    else
        return 1  # false
    fi
}

# Função para obter input com validação
obter_input_validado() {
    local prompt="$1"
    local valor
    
    while true; do
        echo "$prompt" >&2
        read valor
        echo "" >&2
        
        if [ -n "$valor" ]; then
            echo "Valor escolhido: $valor" >&2
            if validar_confirmacao "Confirma esse valor?"; then
                echo "$valor"
                return 0
            else
                echo "Ok, vamos tentar novamente..." >&2
                echo "" >&2
            fi
        else
            echo "[ERRO] Valor não pode ser vazio!" >&2
            echo "" >&2
        fi
    done
}


