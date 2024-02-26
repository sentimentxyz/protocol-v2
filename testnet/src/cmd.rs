use crate::server::start_server;
use alloy_primitives::{Address, U256};
use anyhow::Context;
use clap::{Parser, Subcommand};
use serde::{Deserialize, Serialize};

#[derive(Parser, Debug)]
pub struct Cli {
    #[clap(subcommand)]
    subcmd: Command,

    /// Tbe host of the Server instance
    #[clap(long, default_value = "127.0.0.1")]
    host: String,

    /// The port of the Server instance
    #[clap(long, default_value = "3013")]
    port: u16,
}

impl Cli {
    pub async fn run(self) -> anyhow::Result<()> {
        self.subcmd.execute(self.host, self.port).await
    }
}

#[derive(Subcommand, Debug, Serialize, Deserialize)]
pub enum Command {
    /// Start an anvil server instance, as well as the http server to accept client commands
    Server {
        fork_url: Option<String>,

        /// The port to start the rpc server on
        #[clap(default_value = "8080")]
        rpc_port: u16,
    },
    /// Impersonate an account, sending amount from the address to the recipient
    TransferFrom {
        /// The asset to transfer
        asset: Address,
        /// The sender of the transfer
        from: Address,
        /// The recipient of the transfer
        to: Address,
        /// The amount to transfer accounting for the token decimals
        amount: U256,
    },
    /// Impersonate all subsequent calls
    StartImpersonate {
        /// The address to impersonate
        who: Address,
    },
    /// Stop impersonating calls
    StopImpersonate {
        /// The address to stop impersonating
        who: Address,
    },
    /// Set the balance of an account
    SetBalance {
        /// The address to set the balance of
        who: Address,
        /// The asset to set the balance of in wei
        amount: U256,
    },
}

impl Command {
    pub async fn execute(self, host: String, port: u16) -> anyhow::Result<()> {
        match &self {
            Command::Server { rpc_port, fork_url } => {
                println!("starting command server");
                println!("command server port: {:?}", port);
                println!("starting forked anvil server");
                println!("anvil rpc port: {:?}", rpc_port);
                println!("with fork url: {:?}", fork_url);

                start_server(host, port, rpc_port.clone(), fork_url.clone()).await?;
            }
            transfer @ Command::TransferFrom {
                asset,
                from,
                to,
                amount,
            } => {
                println!(
                    "transferring {:?} from {:?} to {:?} amount {:?}",
                    asset, from, to, amount
                );
                run_request(host, port, transfer).await?;
            }
            start @ Command::StartImpersonate { who } => {
                println!("impersonating {:?}", who);
                run_request(host, port, start).await?;
            }
            stop @ Command::StopImpersonate { who } => {
                println!("stop impersonating {:?}", who);
                run_request(host, port, stop).await?;
            }
            set_balance @ Command::SetBalance { amount, who } => {
                println!("setting balance of {:?} to {}", who, amount);
                run_request(host, port, set_balance).await?;
            }
        };

        Ok(())
    }
}

async fn run_request<T: Serialize>(host: String, port: u16, command: T) -> anyhow::Result<()> {
    reqwest::Client::new()
        .post(&format!("http://{}:{}/command", host, port))
        .json(&command)
        .send()
        .await
        .context("Failed to connect to server")?
        .error_for_status()?;

    Ok(())
}
