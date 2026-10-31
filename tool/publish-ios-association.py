"""Verify the VPS association against the actual signing team; never deploy hosting."""
import os
import re
from ios_release_checks import verify_hosted_association


def main():
    team = os.environ['IOS_TEAM_ID']
    if not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise ValueError('Invalid signing team')
    verify_hosted_association(team + '.com.coffeytable.coffeyTableRecipes')
    print('Verified VPS iOS association against the signing identity')


if __name__ == '__main__':
    main()
