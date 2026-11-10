import json
import boto3
import time
import re
import os
from datetime import datetime, timezone
from botocore.exceptions import ClientError

cloudformation = boto3.client('cloudformation')
s3 = boto3.client('s3')
elbv2 = boto3.client('elbv2')
lambda_client = boto3.client('lambda')

# Tempo reservado (em segundos) para o registro dos alvos do ALB e para o
# relatorio final. Usado para nao comecar uma operacao que nao cabe no tempo
# restante da Lambda (que no maximo e de 900s / 15 minutos).
RESERVA_FINAL_SEGUNDOS = 60

# Numero maximo de auto-continuacoes. Cada execucao avanca pelo menos uma
# stack, entao o limite existe apenas para evitar loop infinito em caso de
# falha persistente.
MAX_TENTATIVAS = 12

# Erros de API que valem um retry com backoff exponencial.
ERROS_THROTTLING = (
    'Throttling',
    'ThrottlingException',
    'ThrottlingRate',
    'TooManyRequestsException',
    'RequestLimitExceeded',
    'ServiceUnavailable',
    'RequestTimeout',
)


def log(nivel, mensagem, **campos):
    """
    Log de uma linha, com timestamp UTC e campos extras em formato chave=valor.
    Usa flush=True para garantir que a linha seja gravada no CloudWatch mesmo
    se a Lambda for encerrada por timeout no meio da execucao.
    """
    timestamp = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3] + 'Z'
    extras = ' '.join(f'{k}={v}' for k, v in campos.items())
    sufixo = f' | {extras}' if extras else ''
    print(f'{timestamp} [{nivel}] {mensagem}{sufixo}', flush=True)


def tempo_restante_s(context, padrao=900):
    """
    Segundos restantes de execucao da Lambda. Cai no padrao quando o contexto
    nao esta disponivel (execucao local).
    """
    if context is None:
        return padrao
    try:
        return context.get_remaining_time_in_millis() / 1000.0
    except Exception:
        return padrao


def _espera_maxima(tempo_limite_s, padrao=3600):
    """
    Converte o tempo limite disponivel (em segundos) no maximo de espera do
    polling de uma stack. Nunca fica abaixo de 30s.
    """
    if not tempo_limite_s:
        return padrao
    return max(30, min(padrao, int(tempo_limite_s)))


def _com_retry(descricao, func, tentativas=6, espera_inicial=2, **kwargs):
    """
    Executa uma chamada de API com retry exponencial quando a API responde
    throttling (Rate exceeded). O botocore ja faz alguns retries internos, mas
    ele esgota rapido e a chamada morre - aqui o retry e explicito e crescente.
    """
    espera = espera_inicial
    for tentativa in range(1, tentativas + 1):
        try:
            return func(**kwargs)
        except ClientError as e:
            codigo = e.response.get('Error', {}).get('Code', '')
            if codigo not in ERROS_THROTTLING:
                raise
            log('WARN', 'throttling na API, aguardando para tentar de novo',
                operacao=descricao, codigo=codigo, tentativa=tentativa,
                tentativas=tentativas, espera_s=espera)
            time.sleep(espera)
            espera = min(espera * 2, 60)
        except Exception as e:
            if 'Throttl' not in str(e) and 'Rate exceeded' not in str(e):
                raise
            log('WARN', 'throttling na API, aguardando para tentar de novo',
                operacao=descricao, tentativa=tentativa, erro=str(e), espera_s=espera)
            time.sleep(espera)
            espera = min(espera * 2, 60)
    raise ClientError(
        {'Error': {'Code': 'Throttling', 'Message': 'Rate exceeded apos varios retries'}},
        descricao)


def reagendar_continuacao(event, motivo):
    """
    Reagenda a propria execucao (invocacao assincrona) para continuar a
    orquestracao.

    Necessario porque a Lambda tem limite maximo de 900s e a orquestracao das
    8 stacks nao cabe nesse tempo (o RDS sozinho leva varios minutos). Cada
    execucao avanca ate onde o tempo permite e agenda a proxima.
    """
    nome = os.environ.get('AWS_LAMBDA_FUNCTION_NAME')
    tentativa = int(event.get('tentativa', 0)) + 1

    if not nome:
        log('ERROR', 'nao foi possivel reagendar: AWS_LAMBDA_FUNCTION_NAME ausente')
        return False

    if tentativa > MAX_TENTATIVAS:
        log('ERROR', 'limite de auto-continuacoes atingido, encerrando',
            tentativa=tentativa, max_tentativas=MAX_TENTATIVAS, motivo=motivo)
        return False

    payload = {k: v for k, v in event.items() if k != 'tentativa'}
    payload['tentativa'] = tentativa

    try:
        _com_retry(
            'InvokeFunction',
            lambda_client.invoke,
            FunctionName=nome,
            InvocationType='Event',
            Payload=json.dumps(payload).encode('utf-8'),
        )
        log('INFO', 'execucao reagendada para continuar a orquestracao',
            funcao=nome, tentativa=tentativa, motivo=motivo)
        return True
    except Exception as e:
        log('ERROR', 'falha ao reagendar a continuacao', funcao=nome,
            tentativa=tentativa, erro=str(e))
        return False


# Configuração das stacks CloudFormation na ordem de criação
STACKS_CONFIG = [
    {
        'name': 'asset-sirius-network',
        'template': 'network.yaml',
        'parameters': {},  # Parâmetros já definidos no template
        'depends_on': []
    },
    {
        'name': 'asset-sirius-alb',
        'template': 'alb.yaml',
        'parameters': {
            'VpcId': 'VpcId',  # Output da stack network
            'PublicSubnets': 'PublicSubnetIds'  # Output da stack network (subnets publicas)
        },
        'depends_on': ['asset-sirius-network']
    },
    {
        'name': 'asset-sirius-pipeline',
        'template': 'pipeline.yaml',
        'parameters': {},  # Parâmetros já definidos no template
        'depends_on': []
    },
    {
        'name': 'asset-sirius-security',
        'template': 'security.yaml',
        'parameters': {
            'VpcId': 'VpcId'  # Output da stack network
        },
        'depends_on': ['asset-sirius-network']
    },
    {
        'name': 'asset-sirius-storage',
        'template': 'storage.yaml',
        'parameters': {
            'PrivateSubnet2Id': 'PrivateSubnet2Id',  # Extraído de PrivateSubnetIds da network
            'PrivateSubnet3Id': 'PrivateSubnet3Id',  # Extraído de PrivateSubnetIds da network
            'RdsSecurityGroupId': 'RdsSecurityGroupId'  # Output da stack security
        },
        'depends_on': ['asset-sirius-network', 'asset-sirius-security']
    },
    {
        'name': 'asset-sirius-crawler',
        'template': 'crawler.yaml',
        'parameters': {},  # Usa defaults do template
        'depends_on': ['asset-sirius-storage']
    },
    {
        'name': 'asset-sirius-compute',
        'template': 'compute.yaml',
        'parameters': {
            'GrafanaSecurityGroupId': 'GrafanaEc2SecurityGroupId',  # Output da stack security
            'GrafanaSubnetId': 'PublicSubnetId',  # Output da stack network (subnet pública 1)
            'Frontend2SubnetId': 'PublicSubnet2Id',  # Output da stack network (subnet pública 2, outra AZ)
            'NodeJsSecurityGroupId': 'NodeJsEc2SecurityGroupId',  # Output da stack security
            'NodeJsSubnetId': 'PrivateSubnet1Id',  # Extraído de PrivateSubnetIds da network
            'KeyName': 'testeKiteria',  # Key pair para acesso SSH às EC2
            # AllocationIds providos pela stack de EIPs criada dinamicamente
            'GrafanaEipAllocationId': 'GrafanaEipAllocationId',
            'NodeEipAllocationId': 'NodeEipAllocationId',
            'Frontend2EipAllocationId': 'Frontend2EipAllocationId',
            # Outputs da stack do ALB (asset-sirius-alb)
            'TargetGroupArn': 'TargetGroupArn',
            'AlbSgId': 'AlbSgId',
            'AlbDns': 'AlbDns'  # DNS do ALB, usado pelo frontend para carregar o Grafana
        },
        'depends_on': ['asset-sirius-network', 'asset-sirius-security', 'asset-sirius-storage', 'asset-sirius-eips', 'asset-sirius-alb']
    }
]


def get_template_from_s3(bucket, key):
    """
    Recupera o template CloudFormation do S3
    """
    try:

        response = s3.get_object(Bucket=bucket, Key=key)
        template_body = response['Body'].read().decode('utf-8')
        return template_body
    except ClientError as e:
        log('ERROR', 'erro ao recuperar template do S3', bucket=bucket, key=key,
            codigo=e.response.get('Error', {}).get('Code'), erro=str(e))
        raise

def get_stack_status(stack_name):
    """
    Retorna o status atual da stack
    """
    try:
        response = cloudformation.describe_stacks(StackName=stack_name)
        if response['Stacks']:
            return response['Stacks'][0]['StackStatus']
        return None
    except ClientError as e:
        if 'does not exist' in str(e):
            return None
        raise

def aguardar_stack(stack_name, max_wait_time=3600):
    """
    Aguarda a conclusao de uma stack (CREATE ou UPDATE) com timeout.

    Retorna:
      'OK'     - a stack chegou em CREATE_COMPLETE / UPDATE_COMPLETE
      'FALHA'  - a stack entrou em *_FAILED / *_ROLLBACK
      'TIMEOUT' - o tempo de espera acabou (tipicamente por falta de tempo
                  da Lambda, nao por problema na stack)
    """
    start_time = time.time()
    poll_interval = 10  # Verifica a cada 10 segundos
    
    log('INFO', 'aguardando conclusao da stack', stack=stack_name, timeout_s=max_wait_time)
    
    ultimo_status = None
    while True:
        elapsed = time.time() - start_time
        
        # Verifica timeout
        if elapsed > max_wait_time:
            log('ERROR', 'TIMEOUT ao aguardar a stack',
                stack=stack_name, decorrido_s=int(elapsed), timeout_s=max_wait_time,
                hint='o tempo da Lambda pode ter sido insuficiente; a execucao sera reagendada')
            return 'TIMEOUT'
        
        status = get_stack_status(stack_name)
        
        # Loga apenas quando o status muda, para nao inundar o log
        if status != ultimo_status:
            log('INFO', 'status da stack', stack=stack_name, status=status, decorrido_s=int(elapsed))
            ultimo_status = status
        
        if status is None:
            pass
        elif status in ('CREATE_COMPLETE', 'UPDATE_COMPLETE'):
            log('INFO', 'stack concluida com sucesso', stack=stack_name,
                status=status, decorrido_s=int(elapsed))
            return 'OK'
        elif 'IN_PROGRESS' in status:
            pass
        elif 'FAILED' in status or 'ROLLBACK' in status:
            log('ERROR', 'stack falhou', stack=stack_name, status=status, decorrido_s=int(elapsed))
            get_stack_error_messages(stack_name)
            return 'FALHA'
        
        time.sleep(poll_interval)

def get_stack_error_messages(stack_name):
    """
    Recupera mensagens de erro da stack
    """
    try:
        response = cloudformation.describe_stack_events(StackName=stack_name)
        for event in response['StackEvents']:
            if 'StatusReason' in event and 'FAILED' in event.get('ResourceStatus', ''):
                log('ERROR', 'evento de falha na stack',
                    stack=stack_name,
                    recurso=event.get('LogicalResourceId'),
                    status=event.get('ResourceStatus'),
                    motivo=event.get('StatusReason'))
    except Exception as e:
        log('ERROR', 'nao foi possivel recuperar detalhes do erro', stack=stack_name, erro=str(e))


def get_stack_outputs(stack_name):
    """
    Recupera os outputs de uma stack criada
    Retorna um dicionário com {OutputKey: OutputValue}
    """
    try:
        response = cloudformation.describe_stacks(StackName=stack_name)
        if response['Stacks']:
            stack = response['Stacks'][0]
            outputs = {}
            
            if 'Outputs' in stack:
                for output in stack['Outputs']:
                    outputs[output['OutputKey']] = output['OutputValue']
            
            return outputs
        return {}
    except ClientError as e:
        log('ERROR', 'erro ao recuperar outputs da stack', stack=stack_name,
            codigo=e.response.get('Error', {}).get('Code'), erro=str(e))
        return {}

def resolve_stack_parameters(stack_config, stack_outputs_map):
    """
    Resolve os parâmetros da stack usando os outputs das stacks anteriores
    stack_outputs_map: {stack_name: {output_key: output_value}}
    """
    resolved_parameters = {}
    stack_name = stack_config.get('name', '?')
    
    for param_key, param_value in stack_config.get('parameters', {}).items():
        origem = 'literal'
        
        # Se o valor é uma string, procura nos outputs das dependências
        if isinstance(param_value, str):
            found = False
            
            # Procura o output nas stacks que esta stack depende
            for dependency_stack in stack_config.get('depends_on', []):
                if dependency_stack in stack_outputs_map:
                    outputs = stack_outputs_map[dependency_stack]
                    
                    # Trata o caso especial do PrivateSubnetIds (que é um join)
                    if param_value.startswith('PrivateSubnet') and param_value.endswith('Id'):
                        subnet_number = int(param_value.replace('PrivateSubnet', '').replace('Id', ''))
                        
                        if 'PrivateSubnetIds' in outputs:
                            subnet_ids = outputs['PrivateSubnetIds'].split(',')
                            if subnet_number <= len(subnet_ids):
                                resolved_parameters[param_key] = subnet_ids[subnet_number - 1]
                                found = True
                                origem = f'output {dependency_stack}.PrivateSubnetIds[{subnet_number}]'
                                break
                    elif param_value in outputs:
                        resolved_parameters[param_key] = outputs[param_value]
                        found = True
                        origem = f'output {dependency_stack}.{param_value}'
                        break
            
            if not found:
                # Se não encontrou nos outputs, usa o valor literal
                # (para parâmetros como KeyName que são valores diretos, não outputs)
                resolved_parameters[param_key] = param_value
                origem = 'literal (sem correspondencia nos outputs)'
        else:
            resolved_parameters[param_key] = param_value
        
        log('INFO', 'parametro resolvido', stack=stack_name,
            parametro=param_key, valor=resolved_parameters[param_key], origem=origem)
    
    return resolved_parameters

def _registrar_outputs(stack_name, stack_outputs_map, inicio=None):
    """
    Le os outputs da stack e registra no mapa usado pelas proximas stacks.
    """
    outputs = get_stack_outputs(stack_name)
    stack_outputs_map[stack_name] = outputs
    log('INFO', 'outputs da stack', stack=stack_name,
        outputs=json.dumps(outputs, ensure_ascii=False),
        decorrido_s=int(time.time() - inicio) if inicio else None)
    return outputs


def _logar_eips(stack_name, template_file, outputs):
    """
    Log detalhado dos EIPs (apenas para a stack de EIPs).
    """
    template_lower = template_file.lower() if template_file else ''
    if not ('eip' in stack_name.lower() or 'eip' in template_lower or 'epis' in template_lower):
        return

    log('INFO', 'detalhes dos EIPs criados', stack=stack_name)
    # regex simples para detectar IPv4
    ip_regex = re.compile(r"^\d{1,3}(?:\.\d{1,3}){3}$")

    # Imprime chaves relevantes (AllocationId, PublicIp, Address, etc.)
    for k, v in outputs.items():
        try:
            is_ip = isinstance(v, str) and bool(ip_regex.match(v))
        except Exception:
            is_ip = False

        key_lower = k.lower()
        if ('allocation' in key_lower) or ('publicip' in key_lower) or ('address' in key_lower) or is_ip:
            log('INFO', 'eip', stack=stack_name, saida=k, valor=v)

    # Trate outputs que sejam listas separadas por vírgula (ex: listas de IPs/allocations)
    for k, v in outputs.items():
        if isinstance(v, str) and ',' in v:
            parts = [p.strip() for p in v.split(',') if p.strip()]
            if any(ip_regex.match(p) for p in parts) or any('eipalloc' in p.lower() for p in parts):
                log('INFO', 'eip (lista)', stack=stack_name, saida=k, valores=parts)


def sincronizar_stack(stack_config, template_bucket, template_key_prefix, stack_outputs_map, tempo_limite_s=None):
    """
    Sincroniza uma stack com o template desejado.

    - stack inexistente -> create
    - stack em andamento   -> apenas aguarda. Essencial na retomada: chamar
                               update_stack em uma stack em CREATE_IN_PROGRESS
                               falha com "can not be updated".
    - stack existente      -> update (ou nada a fazer)

    Retorna 'OK', 'FALHA' ou 'TIMEOUT'.
    """
    stack_name = stack_config['name']
    template_file = stack_config['template']
    inicio = time.time()
    espera_max = _espera_maxima(tempo_limite_s)

    status_atual = get_stack_status(stack_name)
    log('INFO', 'sincronizando stack', stack=stack_name, template=template_file,
        status_atual=status_atual or 'AUSENTE')

    # 1) Stack ja em andamento: nao reenvia o template, apenas espera.
    if status_atual and 'IN_PROGRESS' in status_atual:
        log('INFO', 'stack ja esta em andamento, apenas aguardando (retomada)',
            stack=stack_name, status=status_atual)
        resultado = aguardar_stack(stack_name, max_wait_time=espera_max)
        if resultado == 'OK':
            outputs = _registrar_outputs(stack_name, stack_outputs_map, inicio)
            _logar_eips(stack_name, template_file, outputs)
        return resultado

    # 2) Carrega o template do S3
    if template_key_prefix:
        template_key = f"{template_key_prefix}/{template_file}"
    else:
        template_key = template_file
    template_body = get_template_from_s3(template_bucket, template_key)

    # 3) Resolve os parâmetros usando outputs das stacks anteriores
    resolved_parameters = resolve_stack_parameters(stack_config, stack_outputs_map)
    cf_parameters = [
        {'ParameterKey': key, 'ParameterValue': value}
        for key, value in resolved_parameters.items()
    ]

    if cf_parameters:
        params_str = ', '.join([f"{p['ParameterKey']}={p['ParameterValue']}" for p in cf_parameters])
        log('INFO', 'parametros enviados ao CloudFormation', stack=stack_name, parametros=params_str)
    else:
        log('INFO', 'sem parametros (usando defaults do template)', stack=stack_name)

    # 4) Cria ou atualiza a stack
    try:
        if status_atual is None:
            log('INFO', 'criando stack', stack=stack_name)
            try:
                _com_retry('CreateStack', cloudformation.create_stack,
                    StackName=stack_name,
                    TemplateBody=template_body,
                    Parameters=cf_parameters,
                    Capabilities=['CAPABILITY_IAM', 'CAPABILITY_NAMED_IAM'],
                    TimeoutInMinutes=30,
                    Tags=[
                        {'Key': 'Project', 'Value': 'asset-sirius'},
                        {'Key': 'ManagedBy', 'Value': 'Lambda'}
                    ])
            except ClientError as e:
                if e.response.get('Error', {}).get('Code') != 'AlreadyExistsException':
                    raise
                log('WARN', 'stack ja existe (criada entre o describe e o create), atualizando',
                    stack=stack_name)
                return _atualizar_stack(stack_name, template_body, cf_parameters,
                                        stack_outputs_map, espera_max, inicio, template_file)
        else:
            log('INFO', 'atualizando stack', stack=stack_name, status_atual=status_atual)
            return _atualizar_stack(stack_name, template_body, cf_parameters,
                                    stack_outputs_map, espera_max, inicio, template_file)
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code')
        log('ERROR', 'erro ao sincronizar a stack', stack=stack_name,
            codigo=error_code, erro=str(e), decorrido_s=int(time.time() - inicio))
        return 'FALHA'


def _atualizar_stack(stack_name, template_body, cf_parameters, stack_outputs_map,
                     espera_max, inicio, template_file):
    """
    Atualiza uma stack existente e aguarda o resultado.
    """
    try:
        _com_retry('UpdateStack', cloudformation.update_stack,
            StackName=stack_name,
            TemplateBody=template_body,
            Parameters=cf_parameters,
            Capabilities=['CAPABILITY_IAM', 'CAPABILITY_NAMED_IAM'])
    except ClientError as e:
        mensagem = str(e)
        codigo = e.response.get('Error', {}).get('Code')

        if 'No updates are to be performed' in mensagem:
            log('INFO', 'stack ja esta atualizada, nenhuma mudanca necessaria', stack=stack_name)
            outputs = _registrar_outputs(stack_name, stack_outputs_map, inicio)
            _logar_eips(stack_name, template_file, outputs)
            return 'OK'

        # A stack pode ter mudado de estado entre o describe e o update
        # (ex.: entrou em CREATE_IN_PROGRESS). Nesse caso, so espera.
        if 'state and can not be updated' in mensagem:
            log('WARN', 'stack nao pode ser atualizada no estado atual, apenas aguardando',
                stack=stack_name, erro=mensagem)
            resultado = aguardar_stack(stack_name, max_wait_time=espera_max)
            if resultado == 'OK':
                outputs = _registrar_outputs(stack_name, stack_outputs_map, inicio)
                _logar_eips(stack_name, template_file, outputs)
            return resultado

        log('ERROR', 'erro ao atualizar stack', stack=stack_name, codigo=codigo,
            erro=mensagem, decorrido_s=int(time.time() - inicio))
        return 'FALHA'

    log('INFO', 'stack em atualizacao', stack=stack_name)
    resultado = aguardar_stack(stack_name, max_wait_time=espera_max)
    if resultado == 'OK':
        outputs = _registrar_outputs(stack_name, stack_outputs_map, inicio)
        _logar_eips(stack_name, template_file, outputs)
    return resultado


def get_registered_target_ids(target_group_arn):
    """
    Retorna o conjunto de IDs de alvo atualmente registrados no Target Group.

    Atencao: describe_target_health NAO e uma operacao paginada na API do
    ELBv2 (usar get_paginator com ela levanta "Operation cannot be
    paginated"). A resposta traz todos os alvos de uma vez.
    """
    target_ids = set()

    try:
        response = elbv2.describe_target_health(TargetGroupArn=target_group_arn)
        for target in response.get('TargetHealthDescriptions', []):
            target_id = target.get('Target', {}).get('Id')
            if target_id:
                target_ids.add(target_id)
        log('INFO', 'alvos atualmente registrados', target_group=target_group_arn, alvos=sorted(target_ids))
    except ClientError as e:
        log('ERROR', 'erro ao consultar os alvos do Target Group',
            target_group=target_group_arn, codigo=e.response.get('Error', {}).get('Code'), erro=str(e))
    except Exception as e:
        # Nunca deixa a excecao escapar: perder a listagem dos alvos impede
        # deregistrar os obsoletos, mas ainda e melhor registrar os desejados.
        log('ERROR', 'erro inesperado ao consultar os alvos do Target Group',
            target_group=target_group_arn, erro=str(e))

    return target_ids


def sync_target_group(target_group_arn, desired_instance_ids):
    """
    Deixa o Target Group com exatamente os alvos desejados:
    registra os que faltam e remove os obsoletos (instancia recriada pelo
    CloudFormation, por exemplo).

    Sem Port informado: o alvo passa a escutar na porta do proprio Target Group.
    """
    desired = [i for i in desired_instance_ids if i]

    if not target_group_arn or not desired:
        log('ERROR', 'target group sem alvos para registrar',
            target_group=target_group_arn, desejados=desired,
            motivo='target_group_arn vazio' if not target_group_arn else 'lista de alvos desejados vazia')
        return False

    try:
        registered = get_registered_target_ids(target_group_arn)
        stale = [i for i in registered if i not in desired]

        if stale:
            _com_retry('DeregisterTargets', elbv2.deregister_targets,
                TargetGroupArn=target_group_arn,
                Targets=[{'Id': i} for i in stale])
            log('INFO', 'alvos obsoletos removidos', target_group=target_group_arn, alvos=sorted(stale))

        _com_retry('RegisterTargets', elbv2.register_targets,
            TargetGroupArn=target_group_arn,
            Targets=[{'Id': i} for i in desired])
        log('INFO', 'alvos registrados no Target Group', target_group=target_group_arn, alvos=desired)
        return True
    except ClientError as e:
        log('ERROR', 'erro ao sincronizar os alvos do Target Group',
            target_group=target_group_arn, codigo=e.response.get('Error', {}).get('Code'),
            erro=str(e), alvos=desired,
            hint='verifique as permissoes elasticloadbalancing:RegisterTargets/DeregisterTargets da role da Lambda')
        return False


def register_alb_targets(stack_outputs_map):
    """
    Registra as instancias do frontend como alvos do Target Group do ALB.

    O CloudFormation nao possui recurso para registrar um alvo que vive em
    outra stack (o Target Group fica na stack asset-sirius-alb e as instancias na
    stack asset-sirius-compute), entao o registro e feito aqui, no fim do
    ciclo de deploy, usando os outputs das duas stacks.

    - Target Group do frontend (porta 80): todas as instancias que servem o
      frontend, para o ALB distribuir a carga entre elas.
    - Target Group do Grafana (porta 3000): somente a instancia que roda o
      Grafana, para que os dashboards nao divirjam entre instancias.
    """
    alb_outputs = stack_outputs_map.get('asset-sirius-alb', {})
    compute_outputs = stack_outputs_map.get('asset-sirius-compute', {})

    frontend_target_group = alb_outputs.get('TargetGroupArn')
    grafana_target_group = alb_outputs.get('GrafanaTargetGroupArn')

    frontend_instances = [
        i for i in compute_outputs.get('FrontendEc2InstanceIds', '').split(',') if i
    ]
    grafana_instances = [compute_outputs.get('GrafanaEc2InstanceId')]

    log('INFO', 'registro dos alvos do ALB',
        tg_frontend=frontend_target_group, tg_grafana=grafana_target_group,
        instancias_frontend=frontend_instances, instancias_grafana=grafana_instances)

    if not frontend_target_group or not frontend_instances:
        # Log explicito de QUAL dado faltou: era exatamente o que impedia o
        # registro de acontecer (e o ALB ficava respondendo 503 sem alvo).
        if not frontend_target_group:
            log('ERROR', 'TargetGroupArn do frontend ausente nos outputs da stack asset-sirius-alb',
                outputs_disponiveis=sorted(alb_outputs.keys()))
        if not frontend_instances:
            log('ERROR', 'FrontendEc2InstanceIds ausente nos outputs da stack asset-sirius-compute',
                outputs_disponiveis=sorted(compute_outputs.keys()))
        log('ERROR', 'nao foi possivel registrar os alvos no Target Group do ALB',
            hint='o ALB vai responder 503 (sem alvos) ate o registro ser refeito')
        return False

    success = sync_target_group(frontend_target_group, frontend_instances)

    if grafana_target_group and grafana_instances[0]:
        sync_target_group(grafana_target_group, grafana_instances)
    else:
        log('WARN', 'GrafanaTargetGroupArn ou GrafanaEc2InstanceId ausente',
            hint='o Grafana nao foi registrado no Target Group')

    if success:
        log('INFO', 'registro dos alvos do ALB concluido com sucesso')
    else:
        log('ERROR', 'registro dos alvos do ALB falhou')

    return success

def lambda_handler(event, context):
    """
    Manipulador principal do Lambda
    Orquestra a criação de todas as stacks na ordem correta.

    A orquestração completa não cabe no limite de 900s da Lambda (o RDS da
    stack de storage leva vários minutos sozinho). Por isso a execução avança
    até onde o tempo permite e **reagenda a si mesma** (invocação assíncrona)
    para continuar a partir dali.
    """
    
    inicio = time.time()
    
    # Recupera configurações de variáveis de ambiente
    template_bucket = event.get('template_bucket') or 'asset-sirius-infra'
    template_key_prefix = event.get('template_key_prefix') or ''
    tentativa = int(event.get('tentativa', 0))
    
    log('INFO', 'INICIANDO ORCHESTRACAO DE STACKS CLOUDFORMATION',
        bucket=template_bucket, prefix=template_key_prefix, tentativa=tentativa,
        tempo_restante_s=int(tempo_restante_s(context)))
    
    results = {
        'successful': [],
        'failed': [],
        'interrupted': False,
        'reagendado': False,
        'tentativa': tentativa,
        'timestamp': int(time.time())
    }
    
    # Mapa para armazenar outputs das stacks para uso nas dependências
    stack_outputs_map = {}
    
    # True quando o fim da execucao foi por falta de tempo (e nao por falha):
    # nesse caso a execucao deve ser reagendada para continuar.
    deve_continuar = False
    
    try:
        # Cria cada stack na ordem correta
        # Primeiro, criar a stack de EIPs definida em script_cloudformation/eips.yaml
        log('INFO', 'iniciando a stack de EIPs (asset-sirius-eips) usando template eips.yaml')
        eips_config = {
            'name': 'asset-sirius-eips',
            'template': 'eips.yaml',
            'parameters': {},
            'depends_on': []
        }
        eips_resultado = sincronizar_stack(
            eips_config, template_bucket, template_key_prefix, stack_outputs_map,
            tempo_limite_s=max(60, int(tempo_restante_s(context) - RESERVA_FINAL_SEGUNDOS))
        )
        if eips_resultado == 'OK':
            results['successful'].append(eips_config['name'])
        elif eips_resultado == 'TIMEOUT':
            deve_continuar = True
            log('WARN', 'tempo insuficiente para concluir a stack de EIPs')
        else:
            log('ERROR', 'FALHA: nao foi possivel criar a stack de EIPs. Parando orquestracao')
            results['failed'].append(eips_config['name'])
            return {
                'statusCode': 500,
                'body': json.dumps({'error': 'Falha ao criar stack de EIPs'})
            }
        
        for stack_config in STACKS_CONFIG:
            stack_name = stack_config['name']
            
            # Guarda de tempo: a Lambda tem no maximo 900s. Se nao sobra tempo
            # para comecar a proxima stack, para de forma limpa (em vez de ser
            # morta no meio da operacao) e reagenda a continuacao.
            restante = tempo_restante_s(context)
            if restante < RESERVA_FINAL_SEGUNDOS + 60:
                log('WARN', 'tempo da Lambda insuficiente para iniciar a proxima stack',
                    stack=stack_name, tempo_restante_s=int(restante))
                deve_continuar = True
                break
            
            resultado = sincronizar_stack(
                stack_config, template_bucket, template_key_prefix, stack_outputs_map,
                tempo_limite_s=max(60, int(restante - RESERVA_FINAL_SEGUNDOS))
            )
            
            if resultado == 'OK':
                results['successful'].append(stack_name)
            elif resultado == 'TIMEOUT':
                # Tempo esgotado (nao e falha da stack): a stack continua na
                # AWS e a proxima execucao apenas espera ela terminar.
                log('WARN', 'tempo esgotado ao aguardar a stack; ela segue em execucao na AWS',
                    stack=stack_name)
                deve_continuar = True
                break
            else:
                results['failed'].append(stack_name)
                log('ERROR', 'FALHA: stack nao foi criada/atualizada com sucesso', stack=stack_name)
                log('ERROR', 'parando a orquestracao de stacks')
                break
        
        # Fecha o ciclo do ALB: registra as instancias do frontend como alvos do
        # Target Group (nao existe recurso CFN para isso).
        # Fica DEPOIS do laco (e nao dentro dele) para que o registro aconteca
        # mesmo que uma stack intermediaria tenha falhado, desde que a stack de
        # compute esteja em um estado utilizavel.
        if 'asset-sirius-compute' in stack_outputs_map:
            if register_alb_targets(stack_outputs_map):
                results['alb_targets_registered'] = True
            else:
                results['alb_targets_registered'] = False
                results['failed'].append('Registro dos alvos do ALB')
                log('ERROR', 'FALHA: os alvos do ALB nao foram registrados',
                    hint='o ALB respondera 503 (no healthy targets) ate o registro ser refeito')
        else:
            results['alb_targets_registered'] = False
            log('WARN', 'a stack asset-sirius-compute ainda nao produziu outputs: '
                        'o registro dos alvos do ALB ficou para a proxima execucao')
            deve_continuar = True
        
        # Reagenda a propria execucao se ainda houver trabalho a fazer.
        if deve_continuar:
            results['interrupted'] = True
            results['reagendado'] = reagendar_continuacao(event, 'tempo da Lambda insuficiente')
        
        # Relatório final
        log('INFO', 'RESUMO DA ORCHESTRACAO',
            sucesso=len(results['successful']), falhas=len(results['failed']),
            interrompido=results['interrupted'], reagendado=results['reagendado'],
            tentativa=tentativa, decorrido_s=int(time.time() - inicio))
        for stack in results['successful']:
            log('INFO', 'stack ok', stack=stack)
        for stack in results['failed']:
            log('ERROR', 'stack com falha', stack=stack)
        
        return {
            'statusCode': 200 if not results['failed'] else 500,
            'body': json.dumps(results, indent=2)
        }
        
    except Exception as e:
        log('ERROR', 'ERRO CRITICO na orquestracao', erro=str(e),
            decorrido_s=int(time.time() - inicio))
        results['failed'].append('Erro crítico na orquestração')
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'results': results
            }, indent=2)
        }



if __name__ == "__main__":
    # Para testes locais
    event = {
        'template_bucket': 'asset-sirius-bucket-templates',
        'template_key_prefix': ''
    }
    context = {}
    response = lambda_handler(event, context)
    print("\n" + json.dumps(response, indent=2))
