#!/bin/bash

# ============================================================================
# FUNÇÕES UTILITÁRIAS GERAIS
# ============================================================================

# Função para exibir o banner do Asset Sirius
exibir_banner() {
    echo " \$\$\$\$\$\$\\   \$\$\$\$\$\$\\   \$\$\$\$\$\$\\  \$\$\$\$\$\$\$\$\\ \$\$\$\$\$\$\$\$\\        \$\$\$\$\$\$\\  \$\$\$\$\$\$\\ \$\$\$\$\$\$\$\\  \$\$\$\$\$\$\\ \$\$\\   \$\$\\  \$\$\$\$\$\$\\  " >&2
    echo "\$\$  __\$\$\\ \$\$  __\$\$\\ \$\$  __\$\$\\ \$\$  _____|\\__\$\$  __|      \$\$  __\$\$\\ \\_\$\$  _|\$\$  __\$\$\\ \\_\$\$  _|\$\$ |  \$\$ |\$\$  __\$\$\\ " >&2
    echo "\$\$ /  \$\$ |\$\$ /  \\__|\$\$ /  \\__|\$\$ |         \$\$ |         \$\$ /  \\__|  \$\$ |  \$\$ |  \$\$ |  \$\$ |  \$\$ |  \$\$ |\$\$ /  \\__|" >&2
    echo "\$\$\$\$\$\$\$\$ |\\\$\$\$\$\$\$\\  \\\$\$\$\$\$\$\\  \$\$\$\$\$\\       \$\$ |         \\\$\$\$\$\$\$\\    \$\$ |  \$\$\$\$\$\$\$  |  \$\$ |  \$\$ |  \$\$ |\\\$\$\$\$\$\$\\  " >&2
    echo "\$\$  __\$\$ | \\____\$\$\\  \\____\$\$\\ \$\$  __|      \$\$ |          \\____\$\$\\   \$\$ |  \$\$  __\$\$<   \$\$ |  \$\$ |  \$\$ | \\____\$\$\\ " >&2
    echo "\$\$ |  \$\$ |\$\$\\   \$\$ |\$\$\\   \$\$ |\$\$ |         \$\$ |         \$\$\\   \$\$ |  \$\$ |  \$\$ |  \$\$ |  \$\$ |  \$\$ |  \$\$ |\$\$\\   \$\$ |" >&2
    echo "\$\$ |  \$\$ |\\\$\$\$\$\$\$  |\\\$\$\$\$\$\$  |\$\$\$\$\$\$\$\$\\    \$\$ |         \\\$\$\$\$\$\$  |\$\$\$\$\$\$\\ \$\$ |  \$\$ |\$\$\$\$\$\$\\ \\\$\$\$\$\$\$  |\\\$\$\$\$\$\$  |" >&2
    echo "\\__|  \\__| \\______/  \\______/ \\________|   \\__|          \\______/ \\______|\\__|  \\__|\\______| \\______/  \\______/ " >&2
    echo "" >&2
}

# Função para exibir mensagens de sucesso
msg_sucesso() {
    echo "[OK] $1" >&2
}

# Função para exibir mensagens de erro
msg_erro() {
    echo "[ERRO] $1" >&2
}

# Função para exibir mensagens de aviso
msg_aviso() {
    echo "[AVISO] $1" >&2
}

# Função para exibir mensagens de info
msg_info() {
    echo "[INFO] $1" >&2
}

# Função para pausar a execução
pausar() {
    local segundos=${1:-1}
    sleep "$segundos"
}

# Função para exibir separador (linha em branco)
separador() {
    echo "" >&2
}

# Função para exibir título de etapa
titulo_etapa() {
    local numero="$1"
    local titulo="$2"
    echo "Etapa $numero: $titulo" >&2
}

# Função para exibir menu principal e retornar a opção escolhida
exibir_menu_principal() {
    echo "═══════════════════════════════════════════════════════════════════════" >&2
    echo "                         MENU PRINCIPAL" >&2
    echo "═══════════════════════════════════════════════════════════════════════" >&2
    echo "" >&2
    echo "  1) Levantar toda a Infraestrutura" >&2
    echo "  2) Derrubar toda a Infraestrutura" >&2
    echo "" >&2
    echo "═══════════════════════════════════════════════════════════════════════" >&2
    echo "" >&2

    local opcao
    read -p "Escolha uma opção [1-2]: " opcao >&2
    echo "" >&2

    echo "$opcao"
}

# Função para confirmar ação destrutiva
confirmar_acao() {
    local mensagem="$1"
    
    echo "" >&2
    msg_aviso "$mensagem"
    echo "" >&2
    read -p "Digite 'CONFIRMAR' para prosseguir ou qualquer outra coisa para cancelar: " confirmacao >&2
    echo "" >&2
    
    if [ "$confirmacao" == "CONFIRMAR" ]; then
        return 0
    else
        msg_info "Operação cancelada pelo usuário."
        return 1
    fi
}
