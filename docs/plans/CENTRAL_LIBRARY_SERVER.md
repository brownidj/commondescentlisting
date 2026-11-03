# Central library server — initial implementation

Authorised 4 November 2026. Build portable read-only service and a Flutter server
connection setting. Prepare on this Mac; publish only completed, validated fixed
editions. Export one relocatable library with catalogue, compressed audio, baseline,
alignment and categorized index. Preserve GUID/edition/audio identities. Bind to
loopback by default; explicit LAN bind, read token, allowlisted paths, GET/HEAD,
byte ranges, bounded metadata and no job/edit/upload endpoints. No credentials or
absolute source paths in exported catalogue. Use zsh launch/export commands and
Python stdlib; document private-LAN prototype versus hardened/public deployment.

Client: configurable address/read token in Settings, persist connection, restore
at startup, catalogue import, read-only remote transcript/index/audio, local worker
editions retain priority. Keep offline bundle/saved catalogue when server unavailable.
Remote edits and calibration writes disabled; no shared editing or offline audio
cache in this increment. Publish selected edition atomically; migrating means copy
library + launcher and change configured address, not copying a Python venv.

Acceptance: portable path/identity/export invariants, range/auth/traversal tests,
client parsing/settings errors, category/edition preservation. Supply tests; follow
manual test/build/launch policy (earlier index-test approval does not authorise a
new live server/native launch). Syntax/format/static payload inspection allowed.
Document remaining live Mac/iPhone/LAN acceptance. No Git mutations or paid calls.

Implemented: portable export and separate loopback/LAN read-only server, private
read-token helper, seven completed episode editions exported, configurable app
connection/persistence/startup restore/catalogue import, immutable streamed audio
and aligned transcript/index loading, remote transcript edit/Nudge disabled, local
worker priority retained. Shared entity evidence is combined before registry merge.
Server checks exported hashes at startup; no model/preparation dependency on target.
Zsh/embedded Python syntax, Dart formatting, plist parsing and exported hashes
checked. Supplied server/client/evidence-merge tests; no tests, analyzer, live server,
build or app/LAN launch executed. See outputs/library-server/README.md. Initial
implementation complete; automated/native/LAN acceptance pending. No Git mutations.
