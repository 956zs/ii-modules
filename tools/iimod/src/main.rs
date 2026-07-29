mod commands;
mod doctor;
mod exit;
mod hostpatch;
mod hoststate;
mod i18n;
mod install;
mod lint;
mod manifest;
mod ops;
mod patch;
mod paths;
mod pkg;
mod probe;
mod qs;
mod recovery;
mod registry;
mod store;
mod translations;
mod update;
mod verify;

use std::path::PathBuf;

use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(
    name = "iimod",
    version,
    about = "IIMP module manager for the illogical-impulse Quickshell config"
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Extract and validate module translation catalogs
    I18n {
        #[command(subcommand)]
        command: I18nCommand,
    },
    /// Scaffold a new module payload directory
    Init {
        /// Module id (^[a-z][a-z0-9_]{1,30}$, no trailing _ or __)
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
        /// Record an update index URL for `iimod update` (https:// or file://)
        #[arg(long)]
        origin: Option<String>,
        #[arg(long, default_value_t = pkg::DEFAULT_MAX_UNPACKED)]
        max_size: u64,
    },
    /// Update modules from their recorded origin indexes
    Update {
        /// Update one module (omit to update everything with an origin)
        id: Option<String>,
        /// Required when an update is a Tier B module (it modifies stock files)
        #[arg(long)]
        allow_patches: bool,
        /// Report available updates without installing
        #[arg(long)]
        dry_run: bool,
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
        /// Embed an update index URL: installers of this package get
        /// `iimod update` support with nothing typed
        #[arg(long, conflicts_with = "no_origin")]
        origin: Option<String>,
        /// Explicitly opt out of an update origin (local/dev packaging only:
        /// `iimod update` will never cover the resulting package)
        #[arg(long, conflicts_with = "origin")]
        no_origin: bool,
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

#[derive(Subcommand)]
enum I18nCommand {
    /// Extract English translation sources
    Extract {
        #[arg(required_unless_present = "all", conflicts_with = "all")]
        source: Option<PathBuf>,
        /// Discover direct modules under the current repository
        #[arg(long)]
        all: bool,
    },
    /// Check translation dictionaries against extracted sources
    Check {
        #[arg(required_unless_present = "all", conflicts_with = "all")]
        source: Option<PathBuf>,
        /// Discover direct modules under the current repository
        #[arg(long)]
        all: bool,
        /// Required locale; repeated values replace command defaults
        #[arg(long = "locale")]
        locales: Vec<String>,
        /// Treat orphan dictionary keys as errors
        #[arg(long)]
        deny_orphans: bool,
    },
}

fn run() -> anyhow::Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Command::I18n { command } => match command {
            I18nCommand::Extract { source, all } => {
                i18n::cmd_extract(source.as_deref(), all, pkg::DEFAULT_MAX_UNPACKED)
            }
            I18nCommand::Check {
                source,
                all,
                locales,
                deny_orphans,
            } => i18n::cmd_check(
                source.as_deref(),
                all,
                &locales,
                deny_orphans,
                pkg::DEFAULT_MAX_UNPACKED,
            ),
        },
        Command::Init { id, dir } => commands::cmd_init(&id, &dir),
        Command::Validate { source, max_size } => commands::cmd_validate(&source, max_size),
        Command::Check { source, max_size } => commands::cmd_check(&source, max_size),
        Command::Install {
            source,
            allow_patches,
            reinstall,
            no_enable,
            origin,
            max_size,
        } => install::cmd_install(
            &source,
            &install::InstallOpts {
                allow_patches,
                reinstall,
                no_enable,
                max_size,
                origin,
                derived_origin: None,
            },
        ),
        Command::Update {
            id,
            allow_patches,
            dry_run,
            max_size,
        } => update::cmd_update(id.as_deref(), allow_patches, dry_run, max_size),
        Command::Uninstall { id, cascade } => commands::cmd_uninstall(&id, cascade),
        Command::Enable { id } => commands::cmd_set_state(&id, true),
        Command::Disable { id } => commands::cmd_set_state(&id, false),
        Command::List => commands::cmd_list(),
        Command::Info { id } => commands::cmd_info(&id),
        Command::Pack {
            payload,
            out,
            origin,
            no_origin,
        } => commands::cmd_pack(&payload, out, origin.as_deref(), no_origin),
        Command::Suggest { source, max_size } => commands::cmd_suggest(&source, max_size),
        Command::Verify => verify::cmd_verify(),
        Command::Repair { id } => recovery::cmd_repair(id.as_deref()),
        Command::Reapply => recovery::cmd_reapply(),
        Command::Doctor { rebuild_registry } => doctor::cmd_doctor(rebuild_registry),
    }
}

fn main() {
    // Die quietly on SIGPIPE (e.g. `iimod list | head`) like a well-behaved CLI.
    unsafe {
        libc::signal(libc::SIGPIPE, libc::SIG_DFL);
    }
    match run() {
        Ok(()) => std::process::exit(exit::OK),
        Err(e) => {
            eprintln!("error: {e}");
            std::process::exit(exit::code_of(&e));
        }
    }
}
