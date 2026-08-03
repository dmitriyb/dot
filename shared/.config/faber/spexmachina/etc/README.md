# etc/ — passwd/group bind-mounted into the boxes

The nix-built box images ship no `/etc/passwd`; after faber-box drops to the
host uid, ssh (invoked by git for the gate clone/push) hard-fails its
`getpwuid` lookup with "No user exists for uid N". These two files are
bind-mounted read-only via each template's `run.volumes` to give the box a
minimal identity database.

**Host-specific:** the `box` entry's uid:gid must match the invoking host
user (this arch host: 1000:1000; a macOS Docker Desktop host would need 501:20).
`run.volumes` host paths are NOT declarer-relative — templates.yaml carries
them absolute, so re-point them when the project lives elsewhere.
