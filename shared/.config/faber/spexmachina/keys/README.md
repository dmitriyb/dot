# keys/ — gateway host-key pin only

This directory holds exactly one thing: the portitor host-key pin,
`portitor_host_key.pub`, which `orchestrator.yaml`'s `remote.host_key_file` names so boxes
connect with `StrictHostKeyChecking=yes`. **Role keys do not live here**: they live in
`~/.ssh`, and faber resolves an identity by name → fingerprint through its registry
(`faber add-key`, via `role-keys --apply`). Nothing here is committed except this README
(see `.gitignore`).

`portitor deploy`, run by `faber-stack up`, writes the pin on the first deploy from the host
key in the `<instance>-hostkey` volume, and refuses any later deploy whose gate key differs.
Rotation is explicit: `faber-stack down spexmachina --volumes` removes the host-key volume
and the pin together — and the mirror volume with them, so it refuses while a mirror branch
holds commits GitHub does not have.
