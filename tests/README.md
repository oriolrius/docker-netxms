# Tests

Release validation for the NetXMS images. Plain bash: every check is a `docker build`
/ `docker run` / `docker exec` call, so the suites run on a bare machine (or a bare
`ubuntu-latest` runner) with nothing to install beyond Docker itself.

```bash
tests/run.sh                              # build matrix + runtime, on locally built images
tests/run.sh --suite build                # NETXMS_VERSION pinning only
tests/run.sh --suite runtime              # server/agent functional checks only
tests/run.sh --suite published --tag v1.1.0   # what is actually in the registry
```

| Environment variable | Effect |
| --- | --- |
| `IMAGE_PREFIX` | Registry prefix for `--suite published` (default `ghcr.io/oriolrius/docker-netxms`) |
| `KEEP_ARTIFACTS=1` | Leave test containers, networks and images behind for inspection |
| `TEST_CODENAME` | Ubuntu suite queried on packages.netxms.org (default `noble`) |

## Suites

**`build.sh`** — the version pin does what it says. Builds both Dockerfiles at the
pinned version, at the previous release, at a release whose Debian revision is not
`-1`, at `latest`, and at a version that does not exist (which must fail). For each
build it asserts the installed version of every `netxms-*` package and that they are
all `apt-mark hold`ed. The previous/revision versions are discovered from
packages.netxms.org, so the matrix stays meaningful as NetXMS releases move on.

**`runtime.sh <server-image> <agent-image> [version]`** — the images actually work.
Starts a server and an agent on a throwaway network and checks that the server
initialises its SQLite database and listens on 4701/4703, that the agent renders
`nxagentd.conf` from `MASTER_SERVERS` / `DEBUG_LEVEL` / `PROXY_AGENT` / `PROXY_SNMP`
(and from its defaults when they are unset), and that the server can read
`Agent.Version`, `System.Uptime` and `Agent.LocalDatabase.Status` off the agent over
NXCP. Also runs both healthcheck commands from `compose.yaml`.

**`published.sh <tag> [prefix]`** — the release is real. Pulls the published server
and agent images for a tag, asserts they contain the version the Dockerfiles in the
current checkout pin (so run it from a checkout of that tag), that the packages are
held, that the images are `linux/amd64` on the expected Ubuntu suite, compares the
tag digest against `:latest`, and then runs the runtime suite against them.

## Why these checks exist

They are regression tests for real defects, not coverage for its own sake:

- **`netxmsd -v` exits 1** while printing the version, so a `netxmsd -v && \` step
  fails the server build. `build.sh` asserts both that the image builds and that
  `netxmsd -v` still exits non-zero, so nobody "simplifies" the grep away.
- **`netxms-agent` and `netxms-server` depend on `netxms-base` and
  `netxms-dbdrv-sqlite3` with a strict `=` version.** Pinning only the top-level
  package works while the pin happens to be the newest release and breaks with
  `held broken packages` the day a newer one ships — i.e. exactly when the pin
  matters. The "previous release" build covers this.
- **Not every NetXMS release ships as `-1`** (e.g. `6.2.0-2`), so `NETXMS_VERSION`
  accepts an explicit Debian revision.
- **`netxmsd` exits when stdin closes**, so the server container needs a TTY
  (`tty: true` in `compose.yaml`); `runtime.sh` starts it with `-t` for that reason.
