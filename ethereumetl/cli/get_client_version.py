import click
import json

from ethereumetl.json_rpc_requests import generate_client_version_json_rpc
from ethereumetl.providers.auto import get_provider_from_uri

@click.command(context_settings=dict(help_option_names=['-h', '--help']))
@click.option('-p', '--provider-uri', default='https://mainnet.infura.io', show_default=True, type=str,
              help='The URI of the web3 provider e.g. '
                   'file://$HOME/Library/Ethereum/geth.ipc or https://mainnet.infura.io')
def get_client_version(provider_uri):
    web3_provider = get_provider_from_uri(provider_uri, batch=False)
    response = web3_provider.make_request(json.dumps(generate_client_version_json_rpc()))
    print(response)
