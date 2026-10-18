"""Distribution push and universal-link checks for the actual signed iOS app."""
import json
import urllib.request

DOMAIN = 'applinks:coffeybean.com'
ROUTE = '/CoffeyTableRecipes/share.php'


def validate_entitlements(signed, provisioned):
    if signed.get('aps-environment') != 'production' or provisioned.get('aps-environment') != 'production':
        raise ValueError('Production APNs entitlement required in signed app and distribution profile')
    if DOMAIN not in signed.get('com.apple.developer.associated-domains', []):
        raise ValueError('Signed app is missing the hosted associated domain')
    allowed = provisioned.get('com.apple.developer.associated-domains', [])
    if DOMAIN not in allowed and '*' not in allowed:
        raise ValueError('Distribution profile does not permit the associated domain')


def validate_association(document, application_identifier):
    for row in document.get('applinks', {}).get('details', []):
        if application_identifier not in [row.get('appID'), *row.get('appIDs', [])]:
            continue
        if any(component.get('/') == ROUTE and not component.get('exclude', False)
               for component in row.get('components', [])) or ROUTE in row.get('paths', []) or '*' in row.get('paths', []):
            return
    raise ValueError('Hosted iOS association does not match the signed app and recipe route')


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def verify_hosted_association(application_identifier):
    opener = urllib.request.build_opener(NoRedirect)
    with opener.open('https://coffeybean.com/.well-known/apple-app-site-association', timeout=60) as response:
        if response.status != 200 or response.headers.get_content_type() != 'application/json':
            raise ValueError('iOS association requires HTTPS 200 and JSON MIME without redirects')
        validate_association(json.load(response), application_identifier)
