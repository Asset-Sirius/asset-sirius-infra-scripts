import json
import boto3
import time
from botocore.exceptions import ClientError

cloudformation = boto3.client('cloudformation')
s3 = boto3.client('s3')

# Configuração das stacks CloudFormation na ordem de criação
STACKS_CONFIG = [
    {
        'name': 'asset-sirius-network',
        'template': 'network.yaml',
        'parameters': {},  # Parâmetros já definidos no template
        'depends_on': []
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
        'name': 'asset-sirius-compute',
        'template': 'compute.yaml',
        'parameters': {
            'GrafanaSecurityGroupId': 'GrafanaEc2SecurityGroupId',  # Output da stack security
            'GrafanaSubnetId': 'PublicSubnetId',  # Output da stack network (subnet pública 1)
            'NodeJsSecurityGroupId': 'NodeJsEc2SecurityGroupId',  # Output da stack security
            'NodeJsSubnetId': 'PrivateSubnet1Id',  # Extraído de PrivateSubnetIds da network
            'KeyName': 'testeKiteria'  # Key pair para acesso SSH às EC2
        },
        'depends_on': ['asset-sirius-network', 'asset-sirius-security', 'asset-sirius-storage']
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
        print(f"Erro ao recuperar template {key} do S3: {str(e)}")
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

def wait_stack_creation(stack_name, max_wait_time=3600):
    """
    Aguarda a criação completa da stack com timeout
    Retorna True se sucesso, False se falha
    """
    start_time = time.time()
    poll_interval = 10  # Verifica a cada 10 segundos
    
    print(f"Aguardando conclusão da stack: {stack_name}")
    
    while True:
        elapsed = time.time() - start_time
        
        # Verifica timeout
        if elapsed > max_wait_time:
            print(f"TIMEOUT: Stack {stack_name} excedeu {max_wait_time} segundos")
            return False
        
        status = get_stack_status(stack_name)
        
        if status is None:
            print(f"Stack {stack_name} ainda não foi criada...")
        elif status == 'CREATE_COMPLETE':
            print(f"✓ Stack {stack_name} criada com sucesso!")
            return True
        elif status == 'CREATE_IN_PROGRESS':
            print(f"  {stack_name} em criação... ({int(elapsed)}s)")
        elif 'FAILED' in status or 'ROLLBACK' in status:
            print(f"✗ Stack {stack_name} falhou com status: {status}")
            get_stack_error_messages(stack_name)
            return False
        elif status == 'UPDATE_COMPLETE':
            print(f"✓ Stack {stack_name} já existe e está atualizada!")
            return True
        
        time.sleep(poll_interval)

def get_stack_error_messages(stack_name):
    """
    Recupera mensagens de erro da stack
    """
    try:
        response = cloudformation.describe_stack_events(StackName=stack_name)
        events = response['StackEvents']
        
        for event in events:
            if 'StatusReason' in event and 'FAILED' in event.get('ResourceStatus', ''):
                print(f"  Erro: {event.get('StatusReason', 'Desconhecido')}")
    except Exception as e:
        print(f"Não foi possível recuperar detalhes do erro: {str(e)}")

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
        print(f"Erro ao recuperar outputs da stack {stack_name}: {str(e)}")
        return {}

def resolve_stack_parameters(stack_config, stack_outputs_map):
    """
    Resolve os parâmetros da stack usando os outputs das stacks anteriores
    stack_outputs_map: {stack_name: {output_key: output_value}}
    """
    resolved_parameters = {}
    
    for param_key, param_value in stack_config.get('parameters', {}).items():
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
                                break
                    elif param_value in outputs:
                        resolved_parameters[param_key] = outputs[param_value]
                        found = True
                        break
            
            if not found:
                # Se não encontrou nos outputs, usa o valor literal
                # (para parâmetros como KeyName que são valores diretos, não outputs)
                resolved_parameters[param_key] = param_value
        else:
            resolved_parameters[param_key] = param_value
    
    return resolved_parameters

def create_stack(stack_config, template_bucket, template_key_prefix, stack_outputs_map):
    """
    Cria uma stack CloudFormation
    stack_outputs_map: {stack_name: {output_key: output_value}} - outputs das stacks anteriores
    """
    stack_name = stack_config['name']
    template_file = stack_config['template']
    
    print(f"\n{'='*60}")
    print(f"Iniciando criação da stack: {stack_name}")
    print(f"Template: {template_file}")
    print(f"{'='*60}")
    
    try:
        # Recupera o template do S3
        if template_key_prefix:
            template_key = f"{template_key_prefix}/{template_file}"
        else:
            template_key = template_file
        template_body = get_template_from_s3(template_bucket, template_key)
        
        # Resolve os parâmetros usando outputs das stacks anteriores
        resolved_parameters = resolve_stack_parameters(stack_config, stack_outputs_map)
        
        # Formata os parâmetros para CloudFormation
        cf_parameters = [
            {'ParameterKey': key, 'ParameterValue': value}
            for key, value in resolved_parameters.items()
        ]
        
        if cf_parameters:
            params_str = ', '.join([f"{p['ParameterKey']}={p['ParameterValue']}" for p in cf_parameters])
            print(f"Parâmetros: {params_str}")
        else:
            print("Sem parâmetros (usando defaults do template)")
        
        # Cria a stack
        cloudformation.create_stack(
            StackName=stack_name,
            TemplateBody=template_body,
            Parameters=cf_parameters,
            Capabilities=['CAPABILITY_IAM', 'CAPABILITY_NAMED_IAM'],
            TimeoutInMinutes=30,
            Tags=[
                {'Key': 'Project', 'Value': 'asset-sirius'},
                {'Key': 'ManagedBy', 'Value': 'Lambda'}
            ]
        )
        
        print(f"Stack {stack_name} iniciada!")
        
        # Aguarda a conclusão
        success = wait_stack_creation(stack_name)
        
        if success:
            # Recupera os outputs para uso nas próximas stacks
            outputs = get_stack_outputs(stack_name)
            stack_outputs_map[stack_name] = outputs
            print(f"Outputs da stack {stack_name}: {outputs}")
        
        return success
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        
        if error_code == 'AlreadyExistsException':
            print(f"Stack {stack_name} já existe. Tentando atualizar...")
            return update_stack(stack_name, template_body, cf_parameters, stack_outputs_map)
        else:
            print(f"Erro ao criar stack {stack_name}: {str(e)}")
            return False

def update_stack(stack_name, template_body, parameters, stack_outputs_map):
    """
    Atualiza uma stack existente
    """
    try:
        cloudformation.update_stack(
            StackName=stack_name,
            TemplateBody=template_body,
            Parameters=parameters,
            Capabilities=['CAPABILITY_IAM', 'CAPABILITY_NAMED_IAM']
        )
        
        print(f"Stack {stack_name} em atualização!")
        success = wait_stack_update(stack_name)
        
        if success:
            # Recupera os outputs para uso nas próximas stacks
            outputs = get_stack_outputs(stack_name)
            stack_outputs_map[stack_name] = outputs
        
        return success
        
    except ClientError as e:
        if 'No updates are to be performed' in str(e):
            print(f"Stack {stack_name} já está atualizada, nenhuma mudança necessária")
            # Ainda assim, recupera os outputs
            outputs = get_stack_outputs(stack_name)
            stack_outputs_map[stack_name] = outputs
            return True
        else:
            print(f"Erro ao atualizar stack {stack_name}: {str(e)}")
            return False

def wait_stack_update(stack_name, max_wait_time=3600):
    """
    Aguarda a atualização completa da stack
    """
    start_time = time.time()
    poll_interval = 10
    
    print(f"Aguardando conclusão da atualização: {stack_name}")
    
    while True:
        elapsed = time.time() - start_time
        
        if elapsed > max_wait_time:
            print(f"TIMEOUT: Stack {stack_name} excedeu {max_wait_time} segundos")
            return False
        
        status = get_stack_status(stack_name)
        
        if status == 'UPDATE_COMPLETE':
            print(f"✓ Stack {stack_name} atualizada com sucesso!")
            return True
        elif status == 'UPDATE_IN_PROGRESS':
            print(f"  {stack_name} em atualização... ({int(elapsed)}s)")
        elif 'FAILED' in status or 'ROLLBACK' in status:
            print(f"✗ Stack {stack_name} falhou com status: {status}")
            get_stack_error_messages(stack_name)
            return False
        
        time.sleep(poll_interval)

def lambda_handler(event, context):
    """
    Manipulador principal do Lambda
    Orquestra a criação de todas as stacks na ordem correta
    """
    
    # Recupera configurações de variáveis de ambiente
    template_bucket = event.get('template_bucket') or 'asset-sirius-infra'
    template_key_prefix = event.get('template_key_prefix') or ''
    
    print("="*60)
    print("INICIANDO ORQUESTRAÇÃO DE STACKS CLOUDFORMATION")
    print("="*60)
    print(f"Bucket S3: {template_bucket}")
    print(f"Prefixo: {template_key_prefix}")
    print()
    
    results = {
        'successful': [],
        'failed': [],
        'timestamp': int(time.time())
    }
    
    # Mapa para armazenar outputs das stacks para uso nas dependências
    stack_outputs_map = {}
    
    try:
        # Cria cada stack na ordem correta
        for stack_config in STACKS_CONFIG:
            stack_name = stack_config['name']
            
            success = create_stack(stack_config, template_bucket, template_key_prefix, stack_outputs_map)
            
            if success:
                results['successful'].append(stack_name)
            else:
                results['failed'].append(stack_name)
                print(f"\n✗ FALHA: Stack {stack_name} não foi criada com sucesso")
                print("Parando orquestração de stacks")
                break
        
        # Relatório final
        print("\n" + "="*60)
        print("RESUMO DA ORQUESTRAÇÃO")
        print("="*60)
        print(f"Stacks criadas com sucesso: {len(results['successful'])}")
        for stack in results['successful']:
            print(f"  ✓ {stack}")
        
        if results['failed']:
            print(f"\nStacks que falharam: {len(results['failed'])}")
            for stack in results['failed']:
                print(f"  ✗ {stack}")
        
        return {
            'statusCode': 200 if not results['failed'] else 500,
            'body': json.dumps(results, indent=2)
        }
        
    except Exception as e:
        print(f"\nERRO CRÍTICO: {str(e)}")
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