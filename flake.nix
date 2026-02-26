{
  description = "Reproducible madv kernel regression test";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";

    # Source of the last good Linux kernel (parent of the first bad kernel below):
    linux_6_14_last_good_4b94c18d1519_src = {
      url = "https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/snapshot/linux-4b94c18d15199658f1a86231663e97d3cc12d8de.tar.gz";
      flake = false;
    };
    # Source of the first bad Linux kernel:
    linux_6_14_first_bad_7460b470a131_src = {
      url = "https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/snapshot/linux-7460b470a131f985a70302a322617121efdd7caa.tar.gz";
      flake = false;
    };

    linux_7_0_rc1_src = {
      url = "https://git.kernel.org/torvalds/t/linux-7.0-rc1.tar.gz";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      linux_6_14_last_good_4b94c18d1519_src,
      linux_6_14_first_bad_7460b470a131_src,
      linux_7_0_rc1_src,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Build a Linux kernel from the given source directory:
      buildLinux =
        src:
        let
          makefile = builtins.readFile "${src}/Makefile";
          var =
            name:
            let
              m = builtins.match ".*\n${name} = ([^\n]*)\n.*" makefile;
            in
            if m == null then "" else builtins.head m;
          version = "${var "VERSION"}.${var "PATCHLEVEL"}.${var "SUBLEVEL"}${var "EXTRAVERSION"}";
        in
        if pkgs.lib.versionAtLeast version "7.0.0" then
          pkgs.buildLinux {
            inherit version src;
            ignoreConfigErrors = true;
          }
        else
          pkgs.linux_6_12.override {
            argsOverride = rec {
              inherit version src;
              modDirVersion = version;
              ignoreConfigErrors = true;
              structuredExtraConfig = with pkgs.lib.kernel; {
                RUST = pkgs.lib.mkForce no;
              };
            };
          };

      linux_6_14_last_good_4b94c18d1519 = buildLinux linux_6_14_last_good_4b94c18d1519_src;
      linux_6_14_first_bad_7460b470a131 = buildLinux linux_6_14_first_bad_7460b470a131_src;
      linux_7_0_rc1 = buildLinux linux_7_0_rc1_src;
      linux_HEAD = buildLinux ./linux;

      linuxPackages_6_14_last_good_4b94c18d1519 = pkgs.linuxPackagesFor linux_6_14_last_good_4b94c18d1519;
      linuxPackages_6_14_first_bad_7460b470a131 = pkgs.linuxPackagesFor linux_6_14_first_bad_7460b470a131;
      linuxPackages_7_0_rc1 = pkgs.linuxPackagesFor linux_7_0_rc1;
      linuxPackages_HEAD = pkgs.linuxPackagesFor linux_HEAD;

      inherit (self.packages.${system}) thp-madv-remove-test;

      # A function that returns a NixOS test that spawns a VM booting the given Linux kernel,
      # then waits for the system to boot and reach target multi-user.target
      # and finally runs the thp-madv-remove-test binary to check for the presence of the regression.
      test =
        linuxPackages:
        pkgs.testers.nixosTest {
          name = "thp-madv-remove-test";

          nodes.machine =
            { lib, ... }:
            {
              virtualisation.memorySize = 1024; # 1 GiB of RAM.
              virtualisation.cores = 16; # You need multiple virtual cores to trigger the regression reliably.
              boot.kernelPackages = linuxPackages;
              systemd.tmpfiles.rules = [
                "w /sys/kernel/mm/transparent_hugepage/shmem_enabled - - - - advise"
              ];
              environment.systemPackages = [ thp-madv-remove-test ];
            };

          testScript = ''
            machine.wait_for_unit("multi-user.target")
            machine.succeed("grep -q '\\[advise\\]' /sys/kernel/mm/transparent_hugepage/shmem_enabled")
            machine.succeed("systemd-run --service-type=exec --wait -u thp-madv-remove-test thp-madv-remove-test")
          '';
        };
    in
    {
      # For `nix develop` to drop us in a shell where we can develop the rust code using cargo and clippy.
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.cargo
          pkgs.clippy
          pkgs.rustc
        ];
      };

      packages.${system} = {
        inherit
          linux_6_14_last_good_4b94c18d1519
          linux_6_14_first_bad_7460b470a131
          linux_7_0_rc1
          linux_HEAD
          ;

        thp-madv-remove-test = pkgs.rustPlatform.buildRustPackage {
          pname = "thp-madv-remove-test";
          version = "0.1.0";
          src = pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = pkgs.lib.fileset.unions [
              ./main.rs
              ./Cargo.toml
              ./Cargo.lock
            ];
          };
          cargoLock.lockFile = ./Cargo.lock;
        };

        default = thp-madv-remove-test;
      };

      checks.${system} = {
        test_kernel_6_14_last_good_4b94c18d1519 = test linuxPackages_6_14_last_good_4b94c18d1519;
        test_kernel_6_14_first_bad_7460b470a131 = test linuxPackages_6_14_first_bad_7460b470a131;
        test_kernel_7_0_rc1 = test linuxPackages_7_0_rc1;
        test_kernel_HEAD = test linuxPackages_HEAD;
      };
    };
}
