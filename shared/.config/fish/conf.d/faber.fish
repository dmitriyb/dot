# faber host environment.
#
# FABER_GIT_EMAIL: committer email for every faber box. Must be a verified
# email on the GitHub account that owns the role signing keys — GitHub shows
# a commit as Verified only when the committer email resolves to that account.
# It has to be host env: the FABER_ namespace is engine-owned, so a template's
# own env block may not carry it (faber validate rejects it).
set -gx FABER_GIT_EMAIL dvbozhko@gmail.com
