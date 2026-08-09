{
  zramSwap = {
    enable = true;
    # Bound the compressed swap capacity instead of sizing it equal to all RAM.
    # zstd trades a little CPU time for better compression under pressure.
    algorithm = "zstd";
    memoryPercent = 50;
    priority = 100;
  };
}
