# Narrow immediate-reclaim feasibility decision

29 September 2026. Production capability: **disabled; guidance only**.

The current [official npm v10 cache documentation](https://docs.npmjs.com/cli/v10/commands/npm-cache/)
describes offline integrity verification with garbage collection. The installed executable was
npm 10.9.8; the current major-version documentation labels itself 10.9.9. No npm installation,
upgrade, real cache cleanup, project configuration or network package fetch occurred.

`check.py` creates a uniquely named private `/private/tmp` directory, supplies two empty npm
configuration files and an explicit isolated cache, strips inherited npm configuration and
NODE_OPTIONS, disables scripts/audit/update checks, and uses offline mode. It seeds a tiny local
package tarball, creates one unreferenced content-addressed 4 MiB blob, and runs `npm cache verify`.
The blob is permanently removed within the disposable fixture. The referenced 202-byte package
content remains byte-for-byte identical; a sibling sentinel remains unchanged. A second verify
has no further content reduction. Exact commands/output and allocated-byte observations are in
`result.txt`; they are file-content measurements, not attributed whole-volume capacity gains.

Conclusion: supported maintenance can remove orphaned cache content, but a healthy cache may
reclaim nothing. This experiment does not justify offering the entire cache size as a benefit.
It is not backup, synchronization, external relocation or a RAM improvement.

Before enabling an adapter: explicitly approve the permanent no-Undo scope; determine the real
configured cache without exposing credentials; pin/validate supported executable versions and
configuration; refuse redirected/untrusted paths, protected descendants, unsupported caches and
active/unknown writers; constrain environment, timeout, output and shared operation gate; journal
consent/outcome; remeasure same-volume capacity; test interruption and concurrent npm processes.
A process-name check alone cannot prove that no writer exists. No production command or permission
was added by this spike. Broad `npm cache clean --force` remains out of scope.
