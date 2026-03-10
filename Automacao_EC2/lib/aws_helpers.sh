#!/bin/bash

# ============================================================================
# IMPORTAÇÃO DE MÓDULOS AWS HELPERS
# ============================================================================
# Este arquivo centraliza a importação de todos os módulos auxiliares AWS

# Obter o diretório dos módulos
AWS_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/aws-helpers" && pwd)"

# Importar módulos específicos
source "$AWS_HELPERS_DIR/vpc.sh"
source "$AWS_HELPERS_DIR/key_pair.sh"
source "$AWS_HELPERS_DIR/security_group.sh"
source "$AWS_HELPERS_DIR/subnet.sh"
source "$AWS_HELPERS_DIR/instance.sh"
source "$AWS_HELPERS_DIR/internet_gateway.sh"
source "$AWS_HELPERS_DIR/nat_gateway.sh"
source "$AWS_HELPERS_DIR/route_table.sh"
source "$AWS_HELPERS_DIR/rds.sh"
source "$AWS_HELPERS_DIR/recursos.sh"
