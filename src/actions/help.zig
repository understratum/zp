const std = @import("std");

pub const HELP_TEXT =
    \\zp - A minimal, source-based package manager
    \\
    \\Usage: zp [OPTIONS] [PACKAGE...]
    \\
    \\Options:
    \\  sync          Sync recipe trees and regenerate the database
    \\  search <pkg>  Search for a package in the database
    \\  add <pkg>     Download, build, and install a package from source
    \\  remove <pkg>  Remove an installed package
    \\  help          Show this help message and exit
    \\  version       Show version information and exit
    \\  update        Update system packages with current mirrors
    \\  list          Print your installed pkgs
    \\  info <pkg>    Print info about package
    \\  clean         Clear cache (tar files)
    \\  -c <file>     Use another configuration
    \\                without /etc/zp/config.zon
    \\
    \\
    \\Examples:
    \\  sudo zp sync           # Sync recipe trees (Void)
    \\  zp search htop         # Search for htop
    \\  zp add htop            # Build & install htop from source
    \\  sudo zp remove htop    # Remove htop
    \\  zp update htop         # Upgrade htop on new version
    \\  zp update              # Upgrade your system
    \\  zp list                # Print your installed pkgs
    \\  zp info htop           # Print about htop
    \\  zp clean               # Clear cache
    \\  zp -c /etc/myconf.zon  # Use another configuration
    \\
    \\For more information, visit: https://github.com/understratum/zp/
;

pub fn help() void {
    std.debug.print("{s}\n", .{HELP_TEXT});
}
