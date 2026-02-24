{
  description = "Reproducible madv kernel regression test";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";

    linux_6_17_src = {
      url = "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.17.tar.xz";
      flake = false;
    };

    qemu_10_2_0_src = {
      url = "https://download.qemu.org/qemu-10.2.0.tar.xz";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      linux_6_17_src,
      qemu_10_2_0_src,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Linux 6.17 was removed from nixpkgs (EOL upstream).
      # Define it locally by overriding the 6.12 kernel source.
      linux_6_17_0 = pkgs.linux_6_12.override {
        argsOverride = rec {
          version = "6.17";
          modDirVersion = "6.17.0";
          src = linux_6_17_src;
          ignoreConfigErrors = true;
          structuredExtraConfig = with pkgs.lib.kernel; {
            RUST = pkgs.lib.mkForce no;
          };
        };
      };
      linux_6_18_13 = pkgs.linux_6_18;
      linuxPackages_6_17_0 = pkgs.linuxPackagesFor linux_6_17_0;
      linuxPackages_6_18_13 = pkgs.linuxPackages_6_18;

      qemu_10_2_0 = pkgs.qemu_kvm.overrideAttrs (_oldAttrs: {
        version = "10.2.0";
        src = qemu_10_2_0_src;
      });
      qemu_10_2_1 = pkgs.qemu_kvm;

      inherit (self.packages.${system}) thp-madv-remove-test;

      # A function that returns a NixOS test that spawns a VM
      # run via the given QEMU package and booting the given Linux kernel,
      # then runs the thp-madv-remove-test binary inside the VM
      # to check for the presence of the regression.
      test =
        qemuPackage: linuxPackages:
        pkgs.testers.nixosTest {
          name = "thp-madv-remove-test";

          nodes.machine =
            { lib, ... }:
            {
              virtualisation.qemu.package = lib.mkForce qemuPackage;
              virtualisation.memorySize = 16 * 1024;
              virtualisation.cores = 32;
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
          linux_6_17_0
          linux_6_18_13
          qemu_10_2_0
          qemu_10_2_1
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
        test_qemu_10_2_0_kernel_6_17_0 = test qemu_10_2_0 linuxPackages_6_17_0;
        test_qemu_10_2_0_kernel_6_18_13 = test qemu_10_2_0 linuxPackages_6_18_13;
        test_qemu_10_2_1_kernel_6_17_0 = test qemu_10_2_1 linuxPackages_6_17_0;
        test_qemu_10_2_1_kernel_6_18_13 = test qemu_10_2_1 linuxPackages_6_18_13;
      };
    };
}
