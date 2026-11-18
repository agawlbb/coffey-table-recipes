import copy
import unittest
from ios_release_checks import validate_association, validate_entitlements, validate_siri_configuration


class DistributionChecks(unittest.TestCase):
    def setUp(self):
        self.signed = {'aps-environment': 'production', 'com.apple.developer.associated-domains': ['applinks:coffeybean.com']}
        self.profile = {'aps-environment': 'production', 'com.apple.developer.associated-domains': ['*']}
        self.identifier = 'FIXTURE123.com.coffeytable.coffeyTableRecipes'
        self.association = {'applinks': {'details': [{'appIDs': [self.identifier], 'components': [{'/': '/ctr/recipes/*'}]}]}}

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
        for component in [{'/': '/other'}, {'/': '/ctr/recipes/*', 'exclude': True}]:
            document = copy.deepcopy(self.association)
            document['applinks']['details'][0]['components'] = [component]
            with self.assertRaises(ValueError):
                validate_association(document, self.identifier)

    def test_legacy_association(self):
        validate_association({'applinks': {'details': [{'appID': self.identifier, 'paths': ['/ctr/recipes/*']}]}}, self.identifier)


class SiriPackageConfigurationTests(unittest.TestCase):
    def test_exported_settings_match_the_build_input(self):
        config = {'FIREBASE_IOS_APP_ID': 'fixture-app', 'FIREBASE_IOS_API_KEY': 'fixture-key',
                  'GOOGLE_IOS_CLIENT_ID': 'fixture-client', 'FIREBASE_PROJECT_ID': 'fixture-project',
                  'FIREBASE_SENDER_ID': '123'}
        validate_siri_configuration({'CTRFirebaseOptions': dict(config)}, config)

    def test_absent_incomplete_or_wrong_project_settings_are_rejected(self):
        config = {'FIREBASE_IOS_APP_ID': 'fixture-app', 'FIREBASE_IOS_API_KEY': 'fixture-key',
                  'GOOGLE_IOS_CLIENT_ID': 'fixture-client', 'FIREBASE_PROJECT_ID': 'fixture-project',
                  'FIREBASE_SENDER_ID': '123'}
        for info in [{}, {'CTRFirebaseOptions': {}},
                     {'CTRFirebaseOptions': {**config, 'FIREBASE_PROJECT_ID': 'another-project'}},
                     {'CTRFirebaseOptions': {**config, 'FIREBASE_SENDER_ID': 123}}]:
            with self.subTest(info=info):
                with self.assertRaises(ValueError):
                    validate_siri_configuration(info, config)
