# PlatLab

[![CI](https://github.com/Colisian/platlab/actions/workflows/ci.yml/badge.svg)](https://github.com/Colisian/platlab/actions/workflows/ci.yml)

Fault-injection labs for practicing Linux troubleshooting and Puppet on **RHEL-family (Rocky/Alma/RHEL)** and **Ubuntu** VMs.

> ⚠️ **Spoilers:** reading the scripts tells you how each lab is broken. Run them, don't read them, until you've finished a lab.

---

## Quick start

On a fresh lab VM (snapshot it first):

```bash
curl -fsSL https://raw.githubusercontent.com/Colisian/platlab/main/install.sh | sudo bash
cd /opt/platlab
```

This downloads every script to `/opt/platlab`. Then for any lab:

```bash
sudo bash a1.sh baseline   # set up the healthy service
# take a VM snapshot here
sudo bash a1.sh inject     # break it and print the "ticket"
sudo bash a1.sh check      # grade your fix (PASS/FAIL lines)
sudo bash a1.sh reset      # clean up
```

Update to the latest version later by re-running the same `curl` line.

### Pin a version

`main` always has the newest labs. To install a fixed release that won't change, pass a tag:

```bash
curl -fsSL https://raw.githubusercontent.com/Colisian/platlab/v1.0/install.sh | sudo BRANCH=v1.0 bash
```

Releases are listed on the [Releases page](https://github.com/Colisian/platlab/releases).

---

## Scripts

Each script links to its lab README: what it does, how to run it, requirements, and a collapsed spoiler section.

| Script | Verbs | What it practices |
|---|---|---|
| [`a1.sh`](labs/a1/README.md) | baseline, inject, check, reset | Nginx outage with stacked faults |
| [`a2.sh`](labs/a2/README.md) | inject, check, reset | Latent `/etc/fstab` boot failure |
| [`a3.sh`](labs/a3/README.md) | baseline, inject, check, reset | Disk bytes vs. inodes, deleted-but-open files |
| [`a4.sh`](labs/a4/README.md) | baseline, inject, check, reset | Memory pressure, cgroup OOM loop |
| [`a5.sh`](labs/a5/README.md) | baseline, inject, check, reset | Name resolution, bind address, firewall path |
| [`a6.sh`](labs/a6/README.md) | baseline, inject, try, check, reset | SSH key login failures |
| [`mock.sh`](labs/mock/README.md) | start, grade, reveal, reset | Two random faults, blind capstone |
| [`ci-check.sh`](labs/ci-check/README.md) | `<repo-dir>` | Puppet static checks (parser, epp, YAML, lint) |
| [`puppet-idempotence-check.sh`](labs/puppet-idempotence-check/README.md) | `<puppet apply args>` | Apply twice; fail if run 2 changes anything |

---

## Running a single script without the installer

Works for `a1`–`a6` (not `mock.sh`, which needs the others beside it):

```bash
curl -fsSL https://raw.githubusercontent.com/Colisian/platlab/main/scripts/a3.sh | sudo bash -s -- baseline
```

`bash -s -- baseline` means "read the script from stdin and pass `baseline` as its first argument."

---

## Security note

Piping `curl` into `sudo bash` runs whatever the URL returns as root. That's fine for throwaway lab VMs pulling from your own repo, but don't do it on production hosts. Safer habit for anything that matters:

```bash
curl -fsSLO https://raw.githubusercontent.com/Colisian/platlab/main/install.sh
less install.sh        # read it
sudo bash install.sh
```

---

## Contributing and CI

Every push and pull request runs [GitHub Actions](.github/workflows/ci.yml):

- **ShellCheck**: lints every script (warnings and errors fail the build)
- **Bash syntax**: `bash -n` on every script
- **Repo consistency**: [`ci/check-repo.sh`](ci/check-repo.sh) confirms each script in `scripts/` is listed in `install.sh` and has a `labs/<id>/README.md`

To add a lab: add `scripts/<id>.sh`, add `<id>.sh` to `SCRIPTS=(...)` in `install.sh`, and write `labs/<id>/README.md`. Run `bash ci/check-repo.sh` locally before pushing.

---

## License

[MIT](LICENSE)
