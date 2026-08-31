# nur-packages

**My personal [NUR](https://github.com/nix-community/NUR) repository**

## Omarchy Shell

The modules package Omarchy's bar, notifications, lock screen, and idle locking with niri support. The default configuration locks after five minutes of inactivity. It keeps the screensaver, Omarchy menu, and wallpaper disabled.

```nix
{
  imports = [ inputs.nur-merrkry.homeModules.omarchy-shell ];

  programs.omarchy-shell.enable = true;
}
```

The lock screen also needs its PAM service in the NixOS configuration:

```nix
{
  imports = [ inputs.nur-merrkry.nixosModules.omarchy-shell ];

  programs.omarchy-shell.enable = true;
}
```

Run `omarchy-system-lock` to lock immediately. Change `programs.omarchy-shell.settings.idle.lock` to adjust the idle timeout in seconds. The packaged default disables Omarchy's separate terminal screensaver.

Disable Noctalia, SwayNC, and other notification daemons before enabling the module. Only one process can own `org.freedesktop.Notifications`.
