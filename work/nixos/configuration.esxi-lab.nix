{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Test-lab profile for this repository.
  networking.hostName = "esxi-arm-lab";
  networking.useDHCP = true;

  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  services.openssh.enable = true;
  services.openssh.openFirewall = true;
  services.openssh.settings = {
    PasswordAuthentication = true;
    PermitRootLogin = "yes";
  };

  # Testing-only credentials. Do not reuse in production.
  users.users.root.initialPassword = "VMware123!";
  users.users.jqwang = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "VMware123!";
  };

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    curl
    expect
    git
    jq
    p7zip
    python3
    qemu
    rsync
    wget
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "25.11";
}
