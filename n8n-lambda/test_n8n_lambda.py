"""Teste do orquestrador com boto3 mockado (nao toca na AWS).

Executar:  python n8n-lambda/test_n8n_lambda.py
"""
import io
import json
import os
import sys
import time as time_mod
import types
from pathlib import Path
from contextlib import redirect_stdout

from botocore.exceptions import ClientError

# ---------------------------------------------------------------- mocks
class FakePaginator:
    def paginate(self, TargetGroupArn=None):
        yield {'TargetHealthDescriptions': []}


class FakeClient:
    def __init__(self, nome, cenario):
        self.nome = nome
        self.cenario = cenario
        self.registrados = []
        self.deregistrados = []
        self.invocacoes = []
        self.chamadas_describe = {}

    def create_stack(self, **kw):
        self.cenario['criadas'].append(kw['StackName'])
        if self.cenario.get('throttle_create_stack'):
            raise ClientError(
                {'Error': {'Code': 'Throttling', 'Message': 'Rate exceeded'}}, 'CreateStack')
        if kw['StackName'] in self.cenario['existentes']:
            raise ClientError(
                {'Error': {'Code': 'AlreadyExistsException', 'Message': 'already exists'}},
                'CreateStack')

    def update_stack(self, **kw):
        self.cenario['atualizadas'].append(kw['StackName'])
        if self.cenario.get('sem_mudanca'):
            raise ClientError(
                {'Error': {'Code': 'ValidationError',
                           'Message': 'No updates are to be performed.'}},
                'UpdateStack')

    def _status(self, StackName):
        seq = self.cenario.get('status_por_stack', {}).get(StackName)
        if isinstance(seq, list):
            n = self.chamadas_describe.get(StackName, 0)
            self.chamadas_describe[StackName] = n + 1
            return seq[min(n, len(seq) - 1)]
        return seq or 'CREATE_COMPLETE'

    def describe_stacks(self, StackName):
        status = self._status(StackName)
        if status == 'AUSENTE':
            raise ClientError(
                {'Error': {'Code': 'ValidationError',
                           'Message': f'Stack with id {StackName} does not exist'}},
                'DescribeStacks')
        return {'Stacks': [{
            'StackStatus': status,
            'Outputs': [{'OutputKey': k, 'OutputValue': v}
                        for k, v in self.cenario['outputs'].get(StackName, {}).items()],
        }]}

    def describe_stack_events(self, StackName):
        return {'StackEvents': []}

    def get_object(self, Bucket, Key):
        return {'Body': io.BytesIO(b'AWSTemplateFormatVersion: "2010-09-09"')}

    def get_paginator(self, nome):
        # O botocore real levanta ValueError para operacoes que nao sao
        # paginadas (describe_target_health nao e paginada no ELBv2).
        raise ValueError(f'Operation cannot be paginated: {nome}')

    def describe_target_health(self, TargetGroupArn):
        return {'TargetHealthDescriptions': [
            {'Target': {'Id': i}} for i in self.cenario.get('registrados', {}).get(TargetGroupArn, [])
        ]}

    def register_targets(self, TargetGroupArn, Targets):
        self.registrados.append((TargetGroupArn, Targets))

    def deregister_targets(self, TargetGroupArn, Targets):
        self.deregistrados.append((TargetGroupArn, Targets))

    def invoke(self, **kw):
        self.invocacoes.append(kw)
        return {'StatusCode': 202}


OUTPUTS = {
    'asset-sirius-eips': {
        'NodeEipAllocationId': 'eipalloc-node', 'NodeEipPublicIp': '1.2.3.4',
        'GrafanaEipAllocationId': 'eipalloc-graf', 'GrafanaEipPublicIp': '5.6.7.8',
        'Frontend2EipAllocationId': 'eipalloc-fe2', 'Frontend2EipPublicIp': '9.9.9.9',
    },
    'asset-sirius-network': {
        'VpcId': 'vpc-123', 'PublicSubnetId': 'subnet-p1', 'PublicSubnet2Id': 'subnet-p2',
        'PublicSubnetIds': 'subnet-p1,subnet-p2',
        'PrivateSubnetIds': 'subnet-priv1,subnet-priv2,subnet-priv3',
    },
    'asset-sirius-alb': {
        'TargetGroupArn': 'arn:tg/frontend', 'GrafanaTargetGroupArn': 'arn:tg/grafana',
        'AlbSgId': 'sg-alb', 'AlbDns': 'alb-dns.elb.amazonaws.com',
    },
    'asset-sirius-security': {
        'NodeJsEc2SecurityGroupId': 'sg-node', 'GrafanaEc2SecurityGroupId': 'sg-graf',
        'RdsSecurityGroupId': 'sg-rds',
    },
    'asset-sirius-storage': {'BucketName': 'b'},
    'asset-sirius-compute': {
        'GrafanaEc2InstanceId': 'i-grafana', 'FrontendEc2InstanceId2': 'i-frontend2',
        'FrontendEc2InstanceIds': 'i-grafana,i-frontend2',
    },
}


class FakeContext:
    def __init__(self, ms=900000):
        self.ms = ms

    def get_remaining_time_in_millis(self):
        return self.ms


def rodar(cenario, contexto, event=None, sem_sleep=True):
    mod_boto3 = types.ModuleType('boto3')
    cf = FakeClient('cf', cenario)
    s3 = FakeClient('s3', cenario)
    elbv2 = FakeClient('elbv2', cenario)
    lam = FakeClient('lambda', cenario)
    mod_boto3.client = lambda nome, *a, **k: {
        'cloudformation': cf, 's3': s3, 'elbv2': elbv2, 'lambda': lam}[nome]
    sys.modules['boto3'] = mod_boto3

    os.environ['AWS_LAMBDA_FUNCTION_NAME'] = 'asset-sirius-infra'

    import importlib.util
    spec = importlib.util.spec_from_file_location(
        'n8n_lambda_mod',
        str(Path(__file__).parent / 'n8n-lambda.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)

    sleep_original = time_mod.sleep
    if sem_sleep:
        time_mod.sleep = lambda s: None
    try:
        buffer = io.StringIO()
        ev = event if event is not None else {'template_bucket': 'b', 'template_key_prefix': ''}
        with redirect_stdout(buffer):
            resp = mod.lambda_handler(ev, contexto)
    finally:
        time_mod.sleep = sleep_original
    return resp, buffer.getvalue(), elbv2, lam


def base(**extra):
    c = {'existentes': set(OUTPUTS.keys()), 'criadas': [], 'atualizadas': [],
         'outputs': {k: dict(v) for k, v in OUTPUTS.items()}, 'sem_mudanca': True}
    c.update(extra)
    return c


# ---------------------------------------------------------------- cenarios
print("=" * 72)
print("CENARIO 1: stacks existentes e sem mudanca -> registra os alvos, HTTP 200")
print("=" * 72)
resp, saida, elbv2, lam = rodar(base(), FakeContext())
assert resp['statusCode'] == 200, resp
assert len(elbv2.registrados) == 2, elbv2.registrados
assert elbv2.registrados[0][1] == [{'Id': 'i-grafana'}, {'Id': 'i-frontend2'}]
assert json.loads(resp['body'])['alb_targets_registered'] is True
assert lam.invocacoes == [], lam.invocacoes
print("OK: 2 TGs sincronizados, sem reagendamento\n")

print("=" * 72)
print("CENARIO 2: stack em CREATE_IN_PROGRESS -> apenas espera, nao envia update")
print("=" * 72)
cenario = base(status_por_stack={
    'asset-sirius-storage': ['CREATE_IN_PROGRESS', 'CREATE_IN_PROGRESS', 'CREATE_COMPLETE']})
resp, saida, elbv2, lam = rodar(cenario, FakeContext())
assert 'stack ja esta em andamento, apenas aguardando (retomada)' in saida
print("OK: nao quebrou com 'can not be updated'\n")

print("=" * 72)
print("CENARIO 3: throttling na API -> retry com backoff")
print("=" * 72)
cenario = base(throttle_create_stack=True, sem_mudanca=False,
                existentes=set(OUTPUTS.keys()) - {'asset-sirius-eips'},
                status_por_stack={'asset-sirius-eips': 'AUSENTE'})
resp, saida, elbv2, lam = rodar(cenario, FakeContext())
assert 'throttling na API' in saida, saida[-3000:]
print("OK: throttling tratado com retry\n")

print("=" * 72)
print("CENARIO 4: tempo insuficiente -> para limpo e REAGENDA a continuacao")
print("=" * 72)
resp, saida, elbv2, lam = rodar(base(), FakeContext(ms=100000))
body = json.loads(resp['body'])
assert body['interrupted'] is True, body
assert body['reagendado'] is True, body
assert len(lam.invocacoes) == 1, lam.invocacoes
inv = lam.invocacoes[0]
assert inv['InvocationType'] == 'Event', inv
assert inv['FunctionName'] == 'asset-sirius-infra', inv
payload = json.loads(inv['Payload'])
assert payload['tentativa'] == 1, payload
assert payload['template_bucket'] == 'b', payload
print("OK: reagendado via InvokeFunction Event, tentativa=1\n")

print("=" * 72)
print("CENARIO 5: compute sem outputs -> alvos nao registrados, causa apontada")
print("=" * 72)
outputs5 = {k: dict(v) for k, v in OUTPUTS.items()}
outputs5['asset-sirius-compute'] = {'GrafanaEc2InstanceId': 'i-grafana'}
cenario = base(outputs=outputs5)
resp, saida, elbv2, lam = rodar(cenario, FakeContext())
assert elbv2.registrados == [], elbv2.registrados
assert 'FrontendEc2InstanceIds ausente' in saida
print("OK: log aponta exatamente o dado que faltou\n")

print("=" * 72)
print("CENARIO 6: limite de auto-continuacoes")
print("=" * 72)
resp, saida, elbv2, lam = rodar(base(), FakeContext(ms=100000),
                                event={'template_bucket': 'b', 'tentativa': 99})
assert lam.invocacoes == [], lam.invocacoes
assert 'limite de auto-continuacoes atingido' in saida
print("OK: nao reagenda em loop infinito\n")

print("TODOS OS CENARIOS PASSARAM")
