# The hub: Vitrin's local control API

`vitrin hub` lets another program on the Mac run Vitrin for someone who isn't at it. Remote Code uses it to bring
Vitrin to the phone. It needs neither Vitrin for Mac nor a terminal: Remote Code starts it, and it stops with Remote
Code (`--attached`).

The hub listens on 127.0.0.1 only. While it runs, `~/Library/Application Support/Vitrin/control.json` (mode 0600;
`VITRIN_APP_SUPPORT` names another folder) holds `{ version, port, token, pid, vitrin }`. Every request sends
`Authorization: Bearer <token>`.

The hub shares its files with Vitrin for Mac: `projects.json` for the project list and `credentials.json` plus `keys/`
for the App Store Connect key. A project opened by both the hub and the Mac app has two Studios on one folder, so start
a job in only one of them at a time.

| Request | What it does |
|---|---|
| `GET /v1/status` | `{ api, version, tools, connection }`. `connection.state` is `vitrinKey`, `ascLogin`, `none` or `missingCLI` |
| `GET /v1/events` | Server-sent events: `studio` (`{ project, event, data }`, the Studio's own events, `data` as text), `projects` (the list changed, here or in Vitrin for Mac), `connection`, `ping` |
| `GET /v1/projects` | `[{ id, path, name, exists, initialized, bundleId?, running }]` |
| `POST /v1/projects` | `{ path }` adds a folder (an absolute path that exists); adding one twice returns the first |
| `DELETE /v1/projects/<id>` | Removes it from the list and stops its Studio. The folder stays |
| `POST /v1/projects/<id>/open` | Starts its Studio; `{ hello }` is the `hello` event a new listener would get |
| `* /v1/projects/<id>/studio/<path>` | The project's Studio: its pages, `/api/…` and `/files/…`, with the session token added. `Range` passes through |
| `POST /v1/asc` | `{ args, write?, timeout? }` runs `asc`, read-only unless `write` is true. `{ code, stdout, stderr }`; larger output comes as `part: { id, length }` |
| `GET /v1/asc/part/<id>?offset=` | `{ text }`, the next piece of large output |
| `GET`/`POST`/`DELETE /v1/asc/key` | Reads the ids, stores `{ keyId, issuerId, p8 }` (or `p8Path`, a `.p8` on this Mac), forgets the key |
| `POST /v1/ads/keypair` | `{ publicKey, privateKey }`: the Apple Ads key pair, made once. `privateKey` is its path |
| `POST /v1/asc/web` | `{ args, password? }` starts an `asc web` run that may ask for a two-factor code |
| `GET /v1/asc/web` | `{ running, needsCode, result? }` |
| `POST /v1/asc/web/code` | `{ code }` answers the two-factor question |
| `POST /v1/tools/install` | `{ tool }` installs `claude`, `asc` or `ffmpeg` |

Bump `HUB_API` in `packages/cli/src/hub/server.ts` when a change breaks a client. An idle Studio stops after 30 minutes,
unless a job or a Claude run is going.
