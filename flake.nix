{
  description = "Reproducible madv kernel regression test";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";

    linux_6_17_src = {
      url = "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.17.tar.xz";
      flake = false;
    };

    linux_7_rc1_src = {
      url = "https://git.kernel.org/torvalds/t/linux-7.0-rc1.tar.gz";
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
      linux_7_rc1_src,
      qemu_10_2_0_src,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      linux_6_12_74 = pkgs.linux_6_12;
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
      linux_6_19_3 = pkgs.linux_6_19;

      linux_7_0_0_rc1 = pkgs.buildLinux {
        version = "7.0-rc1";
        modDirVersion = "7.0.0-rc1";
        src = linux_7_rc1_src;
        ignoreConfigErrors = true;
      };

      linux_HEAD_Makefile = builtins.readFile ./linux/Makefile;
      var =
        name:
        let
          m = builtins.match ".*\n${name} = ([^\n]*)\n.*" linux_HEAD_Makefile;
        in
        if m == null then "" else builtins.head m;

      # linux_HEAD = pkgs.buildLinux {
      #   version = "${var "VERSION"}.${var "PATCHLEVEL"}.${var "SUBLEVEL"}${var "EXTRAVERSION"}";
      #   src = ./linux;
      #   ignoreConfigErrors = true;
      # };

      linux_HEAD = pkgs.linux_6_12.override {
        argsOverride = rec {
          version = "${var "VERSION"}.${var "PATCHLEVEL"}.${var "SUBLEVEL"}${var "EXTRAVERSION"}";
          modDirVersion = version;
          src = ./linux;
          ignoreConfigErrors = true;
          structuredExtraConfig = with pkgs.lib.kernel; {
            RUST = pkgs.lib.mkForce no;
          };
        };
      };


      linuxPackages_6_12_74 = pkgs.linuxKernel.packages.linux_6_12;
      linuxPackages_6_17_0 = pkgs.linuxPackagesFor linux_6_17_0;
      linuxPackages_6_18_13 = pkgs.linuxKernel.packages.linux_6_18;
      linuxPackages_6_19_3 = pkgs.linuxKernel.packages.linux_6_19;
      linuxPackages_7_0_0_rc1 = pkgs.linuxPackagesFor linux_7_0_0_rc1;
      linuxPackages_HEAD = pkgs.linuxPackagesFor linux_HEAD;

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
          linux_6_12_74
          linux_6_17_0
          linux_6_18_13
          linux_6_19_3
          linux_7_0_0_rc1
          linux_HEAD
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
        test_qemu_10_2_0_kernel_6_12_74 = test qemu_10_2_0 linuxPackages_6_12_74;
        test_qemu_10_2_0_kernel_6_17_0 = test qemu_10_2_0 linuxPackages_6_17_0;
        test_qemu_10_2_0_kernel_6_18_13 = test qemu_10_2_0 linuxPackages_6_18_13;
        test_qemu_10_2_0_kernel_6_19_3 = test qemu_10_2_0 linuxPackages_6_19_3;

        test_qemu_10_2_1_kernel_6_12_74 = test qemu_10_2_1 linuxPackages_6_12_74;
        test_qemu_10_2_1_kernel_6_17_0 = test qemu_10_2_1 linuxPackages_6_17_0;
        test_qemu_10_2_1_kernel_6_18_13 = test qemu_10_2_1 linuxPackages_6_18_13;
        test_qemu_10_2_1_kernel_6_19_3 = test qemu_10_2_1 linuxPackages_6_19_3;
        test_qemu_10_2_1_kernel_7_0_0_rc1 = test qemu_10_2_1 linuxPackages_7_0_0_rc1;
        test_qemu_10_2_1_kernel_HEAD = test qemu_10_2_1 linuxPackages_HEAD;
      };
    };
}
