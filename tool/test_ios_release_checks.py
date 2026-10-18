import copy
import unittest
from ios_release_checks import validate_association, validate_entitlements


class DistributionChecks(unittest.TestCase):
    def setUp(self):
        self.signed = {'aps-environment': 'production', 'com.apple.developer.associated-domains': ['applinks:coffeybean.com']}
        self.profile = {'aps-environment': 'production', 'com.apple.developer.associated-domains': ['*']}
        self.identifier = 'FIXTURE123.com.coffeytable.coffeyTableRecipes'
        self.association = {'applinks': {'details': [{'appIDs': [self.identifier], 'components': [{'/': '/CoffeyTableRecipes/share.php'}]}]}}

    def test_distribution_push_and_profile_domain_permission(self):
        validate_entitlements(self.signed, self.profile)
        self.profile['com.apple.developer.associated-domains'] = ['applinks:coffeybean.com']
        validate_entitlements(self.signed, self.profile)

    def test_development_or_missing_push_is_rejected_on_either_side(self):
        for side in ['signed', 'profile']:
            for value in ['development', None]:
                signed, profile = copy.deepcopy((self.signed, self.profile))
                (signed if side == 'signed' else profile)['aps-environment'] = value
                with self.assertRaises(ValueError):
                    validate_entitlements(signed, profile)

    def test_missing_signed_or_profile_domain_is_rejected(self):
        for side in ['signed', 'profile']:
            signed, profile = copy.deepcopy((self.signed, self.profile))
            (signed if side == 'signed' else profile)['com.apple.developer.associated-domains'] = []
            with self.assertRaises(ValueError):
                validate_entitlements(signed, profile)

    def test_hosted_identity_and_route(self):
        validate_association(self.association, self.identifier)
        with self.assertRaises(ValueError):
            validate_association(self.association, 'OTHERTEAM.com.coffeytable.coffeyTableRecipes')

    def test_wrong_or_excluded_route_is_rejected(self):
        for component in [{'/': '/other'}, {'/': '/CoffeyTableRecipes/share.php', 'exclude': True}]:
            document = copy.deepcopy(self.association)
            document['applinks']['details'][0]['components'] = [component]
            with self.assertRaises(ValueError):
                validate_association(document, self.identifier)

    def test_legacy_association(self):
        validate_association({'applinks': {'details': [{'appID': self.identifier, 'paths': ['/CoffeyTableRecipes/share.php']}]}}, self.identifier)
