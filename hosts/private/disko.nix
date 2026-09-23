{
  disko.devices.disk.system = {
    type = "disk";
    device = "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "btrfs";
            mountpoint = "/";
            mountOptions = [
              "compress=zstd"
              "noatime"
            ];
          };
        };
      };
    };
  };

  disko.devices.disk.data = {
    type = "disk";
    device = "/dev/sda";
    content = {
      type = "gpt";
      partitions.data = {
        size = "100%";
        content = {
          type = "filesystem";
          format = "btrfs";
          mountpoint = "/srv";
          mountOptions = [
            "compress=zstd"
            "noatime"
          ];
        };
      };
    };
  };
}
