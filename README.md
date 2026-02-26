# Kernel Regression
Minimal reproducer for a kernel regression where `madvise(MADV_REMOVE)` on a 4KiB range
within a huge-page-backed `MAP_SHARED` memfd region corrupts nearby pages.

The test runs a VM booting the specified kernel,
then waits for the system to boot and reach target `multi-user.target`,
then runs the Rust binary `thp-madv-remove-test` which creates a memfd and forks.
The child maps the file, fills all pages with known patterns, applies `MADV_HUGEPAGE`,
and then continuously verifies non-punched pages.


# Results
The regression first happened on kernel 6.14 on
[7460b470a131](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=7460b470a131f985a70302a322617121efdd7caa)
and can be reproduced with:

```
$ nix build .#checks.x86_64-linux.test_kernel_6_14_first_bad_7460b470a131 -L
```

Log: [`test_kernel_6_14_first_bad_7460b470a131.log`](./test_kernel_6_14_first_bad_7460b470a131.log)

The test succeeded on its parent commit and can be reproduced with:

```
$ nix build .#checks.x86_64-linux.test_kernel_6_14_last_good_4b94c18d1519 -L
```

Log: [`test_kernel_6_14_last_good_4b94c18d1519.log`](./test_kernel_6_14_last_good_4b94c18d1519.log)

The regression is still present on kernel 7.0-rc1 and can be reproduced with:

```
$ nix build .#checks.x86_64-linux.test_kernel_7_0_rc1 -L
```

Log: [`test_kernel_7_0_rc1.log`](./test_kernel_7_0_rc1.log)

To test the kernel in the git submodule under `./linux` use:

```
nix build git+file:.?submodules=1#checks.x86_64-linux.test_kernel_HEAD -L
```
