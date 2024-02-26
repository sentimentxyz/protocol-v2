mod cmd;
mod server;
use clap::Parser;
use cmd::Cli;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    cli.run().await
}
