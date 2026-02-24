Minimal reproducer for a potential kernel regression where
`madvise(MADV_REMOVE)` on a 4KiB range within a huge-page-backed
`MAP_SHARED` memfd region corrupts nearby pages.

To run a VM via a specified QEMU booting a specified Linux kernel running the `thp-madv-remove-test` rust binary execute the following:

```
$ nix build .#checks.x86_64-linux.<TEST>
```

where `<TEST>` is one of the following:

|            |           QEMU-10.2.0          |          QEMU-10.2.1           |
| ---------- | ------------------------------ |------------------------------- |
| linux-6.17 | `test_qemu_10_2_0_kernel_6_17` | `test_qemu_10_2_1_kernel_6_17` |
| linux-6.18 | `test_qemu_10_2_0_kernel_6_18` | `test_qemu_10_2_1_kernel_6_18` |
