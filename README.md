# plugdata-testing

A lightweight CI harness that builds [plugdata](https://github.com/plugdata-team/plugdata)
from source with its end-to-end test suite enabled, under **AddressSanitizer**,
across four platform configurations, and reports any failures.

This repo contains **only** the GitHub Actions workflow — it does not vendor
plugdata as a submodule. The workflow clones plugdata fresh on each run.

## What it does

The [`plugdata tests`](.github/workflows/test.yml) workflow, for each of:

| Job          | Runner             | Notes                          |
|--------------|--------------------|--------------------------------|
| Linux-x64    | `ubuntu-24.04`     | OpenGL via X11 (headless xvfb) |
| Linux-arm64  | `ubuntu-24.04-arm` | GLES implementation            |
| macOS        | `macos-latest`     | Apple silicon                  |
| Windows      | `windows-2022`     | clang-cl (for ASAN support)    |

does the following:

1. **Clones** the chosen plugdata branch (`develop` by default) with its
   submodules (`--recurse-submodules --shallow-submodules`).
2. **Configures & builds** the standalone target with
   `-DENABLE_TESTING=1 -DENABLE_ASAN=1` (ccache-accelerated).
3. **Runs** the standalone. When built with `ENABLE_TESTING`, plugdata runs its
   whole unit/integration suite at startup and quits when finished.
4. **Checks the result** ([`scripts/run-and-check.sh`](scripts/run-and-check.sh)):
   the job fails if a sanitizer reports an error, if the JUCE `UnitTestRunner`
   prints a failure, or if the run hangs/crashes. The full output is uploaded as
   a `test-output-<job>` artifact.
