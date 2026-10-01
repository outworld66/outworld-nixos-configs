{
  disko.devices.disk.storage = {
    type = "disk";
    device = "/dev/disk/by-id/nvme-KINGSTON_SNV2S2000G_50026B76861362FF";
    content = {
      type = "gpt";
      partitions.storage = {
        size = "100%";
        content = {
          type = "filesystem";
          format = "btrfs";
          mountpoint = "/mnt/storage";
          mountOptions = [
            "compress=zstd"
            "noatime"
          ];
        };
      };
    };
  };
}
