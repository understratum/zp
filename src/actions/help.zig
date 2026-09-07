const std = @import("std");

pub const HELP_TEXT =
    \\zp - A minimal, source-based package manager
    \\
    \\Usage: zp [OPTIONS] [PACKAGE...]
    \\
    \\Options:
    \\  init          Initialize /var/zp and generate gen.sh
    \\  sync          Sync recipe trees and regenerate the database
    \\  search <pkg>  Search for a package in the database
    \\  add <pkg>     Download, build, and install a package from source
    \\  remove <pkg>  Remove an installed package
    \\  help          Show this help message and exit
    \\  version       Show version information and exit
    \\  update        Update system packages with current mirrors
    \\  list          Print your installed pkgs
    \\
    \\
    \\Examples:
    \\  sudo zp init                # Initialize the package manager
    \\  sudo zp sync                # Sync recipe trees (Void + Crux + KISS)
    \\  sudo zp search htop         # Search for htop
    \\  sudo zp add htop            # Build & install htop from source
    \\  sudo zp remove htop         # Remove htop
    \\  sudo zp update htop         # Upgrade htop on new version
    \\  sudo zp update              # Upgrade your system
    \\  sudo zp list                # Print your installed pkgs
    \\
    \\For more information, visit: https://github.com/understrata/zp/
;

pub fn help() void {
    std.debug.print("{s}\n", .{HELP_TEXT});
}
