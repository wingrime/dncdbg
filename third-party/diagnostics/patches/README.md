# dncdbg patches for the vendored diagnostics sources

This directory contains the local modifications dncdbg applies on top of the
upstream [dotnet/diagnostics](https://github.com/dotnet/diagnostics) sources
when building `libdbgshim`. They are applied by
[`tools/update-diagnostics.sh`](../../../tools/update-diagnostics.sh) with
`git apply -p1` from the `third-party/diagnostics` root, in file-name order.

The patches were originally derived by diffing the vendored tree against the
upstream tag it was imported from. When the pinned diagnostics revision is
bumped, run the update script, fix any rejects and refresh the affected patch
file. Patches that upstream has since incorporated must be dropped.

## Patch list

| Patch | Purpose |
| --- | --- |
| `0001-src-CMakeLists-remove-SOS-tests.patch` | Build only `shared` and `dbgshim`, drop `SOS`/`tests`. |
| `0002-configurecompiler-std-ubsan-osx.patch` | C standard 17, disable UBSan `object-size`/`vptr`, macOS deployment target 13.3. |
| `0003-functions-add-executable-clr.patch` | `add_executable_clr` must not depend on the generated version file. |
| `0004-clrdefinitions-eventing-headers.patch` | Keep the dummy `eventing_headers` target (event tracing is disabled). |
| `0005-dbgshim-create-new-console.patch` | Honour `DNCDBG_CREATE_NEW_CONSOLE` on Windows (`CREATE_NEW_CONSOLE`). |
| `0006-pal-configure-macos.patch` | pthread library fallback and `pipe2` probe fix for macOS. |
| `0007-palinternal-coreservices.patch` | Silence `CoreServices` deprecation warnings on macOS 13 SDKs. |
| `0008-unixasmmacros-gnu-stack.patch` | Mark the stack non-executable for ELF targets. |

## Regenerating a patch

```sh
cd /tmp && curl -fsSL -o diag.tar.gz \
  https://codeload.github.com/dotnet/diagnostics/tar.gz/<ref>
tar -xzf diag.tar.gz
# edit the file(s) in diagnostics-<ref>/, then:
diff -u diagnostics-<ref>/<path> <modified>/<path>
```

Adjust the `---`/`+++` labels to `a/<path>` and `b/<path>` so the result can be
applied with `git apply -p1`.
