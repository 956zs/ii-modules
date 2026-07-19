mod commands;
mod exit;
mod hostpatch;
mod lint;
mod manifest;
mod paths;
mod patch;
mod pkg;
mod probe;
mod qs;
mod registry;
mod store;
mod translations;

use std::path::PathBuf;

use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "iimod", version, about = "IIMP module manager for the illogical-impulse Quickshell config")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Scaffold a new module payload directory
    Init {
        /// Module id (^[a-z][a-z0-9-]{1,30}$)
        id: String,
        /// Parent directory to create the payload in
        #[arg(long, default_value = ".")]
        dir: PathBuf,
    },
    /// Validate a payload dir or .iimod package (manifest, layout, lint)
    Validate {
        source: PathBuf,
        #[arg(long, default_value_t = pkg::DEFAULT_MAX_UNPACKED)]
        max_size: u64,
    },
    /// Compatibility check against this machine (probes, deps, anchors); no changes
    Check {
        source: PathBuf,
        #[arg(long, default_value_t = pkg::DEFAULT_MAX_UNPACKED)]
        max_size: u64,
    },
    /// Install (or upgrade) a module from a payload dir or .iimod package
    Install {
        source: PathBuf,
        /// Required for Tier B modules (they modify stock files)
        #[arg(long)]
        allow_patches: bool,
        /// Reinstall even if the same version is already installed
        #[arg(long)]
        reinstall: bool,
        /// Install disabled (enable later via settings or `iimod enable`)
        #[arg(long)]
        no_enable: bool,
        #[arg(long, default_value_t = pkg::DEFAULT_MAX_UNPACKED)]
        max_size: u64,
    },
    /// Remove a module (refuses if others depend on it; see --cascade)
    Uninstall {
        id: String,
        /// Also remove all dependent modules (listed before removal)
        #[arg(long)]
        cascade: bool,
    },
    /// Enable a module (auto-enables its installed dependencies)
    Enable { id: String },
    /// Disable a module (auto-disables its dependents)
    Disable { id: String },
    /// List installed modules and their states
    List,
    /// Show full registry record for one module
    Info { id: String },
    /// Package a payload directory into <id>-<version>.iimod
    Pack {
        payload: PathBuf,
        #[arg(long)]
        out: Option<PathBuf>,
    },
    /// Analyze a payload and suggest compat.probes + capabilities for its manifest
    Suggest {
        source: PathBuf,
        #[arg(long, default_value_t = pkg::DEFAULT_MAX_UNPACKED)]
        max_size: u64,
    },
    /// Check integrity of everything installed (states + remediation)
    Verify,
    /// Restore module files from the store and recompose all patches
    Repair {
        /// Repair one module's files (omit to recompose patches/host only)
        id: Option<String>,
    },
    /// Re-install host + all modules after a dots-hyprland update
    Reapply,
    /// Environment and state sanity report
    Doctor {
        /// Rebuild a lost/corrupt registry from the store (modules land disabled)
        #[arg(long)]
        rebuild_registry: bool,
    },
}

fn run() -> anyhow::Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Command::Init { id, dir } => commands::cmd_init(&id, &dir),
        Command::Validate { source, max_size } => commands::cmd_validate(&source, max_size),
        Command::Check { source, max_size } => commands::cmd_check(&source, max_size),
        Command::Install { source, allow_patches, reinstall, no_enable, max_size } => {
            commands::cmd_install(
                &source,
                &commands::InstallOpts { allow_patches, reinstall, no_enable, max_size },
            )
        }
        Command::Uninstall { id, cascade } => commands::cmd_uninstall(&id, cascade),
        Command::Enable { id } => commands::cmd_set_state(&id, true),
        Command::Disable { id } => commands::cmd_set_state(&id, false),
        Command::List => commands::cmd_list(),
        Command::Info { id } => commands::cmd_info(&id),
        Command::Pack { payload, out } => commands::cmd_pack(&payload, out),
        Command::Suggest { source, max_size } => commands::cmd_suggest(&source, max_size),
        Command::Verify => commands::cmd_verify(),
        Command::Repair { id } => commands::cmd_repair(id.as_deref()),
        Command::Reapply => commands::cmd_reapply(),
        Command::Doctor { rebuild_registry } => commands::cmd_doctor(rebuild_registry),
    }
}

fn main() {
    match run() {
        Ok(()) => std::process::exit(exit::OK),
        Err(e) => {
            eprintln!("error: {e}");
            std::process::exit(exit::code_of(&e));
        }
    }
}
