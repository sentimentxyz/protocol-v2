use crate::cmd::Command;
use alloy_primitives::U256;
use alloy_rpc_types::request::{TransactionInput, TransactionRequest};
use alloy_sol_macro::sol;
use alloy_sol_types::SolCall;
use anvil::{
    eth::{error::BlockchainError, EthApi},
    NodeConfig,
};
use axum::{
    extract::{Json, State},
    response::IntoResponse,
    routing::post,
    Router,
};
use std::sync::Arc;
use tokio::net::TcpListener;

sol! {
   /// Interface of the ERC20 standard as defined in [the EIP].
   ///
   /// [the EIP]: https://eips.ethereum.org/EIPS/eip-20
   #[derive(Debug, PartialEq, Eq)]
   contract ERC20 {
       mapping(address account => uint256) public balanceOf;

       constructor(string name, string symbol);

       event Transfer(address indexed from, address indexed to, uint256 value);
       event Approval(address indexed owner, address indexed spender, uint256 value);

       function totalSupply() external view returns (uint256);
       function transfer(address to, uint256 amount) external returns (bool);
       function allowance(address owner, address spender) external view returns (uint256);
       function approve(address spender, uint256 amount) external returns (bool);
       function transferFrom(address from, address to, uint256 amount) external returns (bool);
   }
}

fn node_config(port: u16, fork_url: Option<String>) -> NodeConfig {
    NodeConfig {
        port: port,
        eth_rpc_url: fork_url,
        ..Default::default()
    }
}

pub async fn start_server(
    host: String,
    port: u16,
    rpc_port: u16,
    fork_url: Option<String>,
) -> anyhow::Result<()> {
    let (api, _) = anvil::spawn(node_config(rpc_port, fork_url)).await;

    let api = Arc::new(api);

    let app = Router::new()
        .route("/command", post(handle_command))
        .with_state(api);

    let listener = TcpListener::bind(format!("{}:{}", host, port)).await?;

    println!("command server listening on {}", listener.local_addr()?);
    let _ = axum::serve(listener, app).await?;

    Ok(())
}

async fn handle_command(
    State(api): State<Arc<EthApi>>,
    Json(command): Json<Command>,
) -> Result<(), ServerError> {
    match command {
        Command::Server { .. } => {
            return Err(ServerError::str_err(
                "Unsupported command `Server`".to_string(),
            ))
        }
        Command::StartImpersonate { who } => {
            println!("impersonating {:?}", who);
            api.anvil_impersonate_account(who).await?;
        }
        Command::StopImpersonate { who } => {
            println!("stop impersonating {:?}", who);
            api.anvil_stop_impersonating_account(who).await?;
        }
        Command::TransferFrom {
            asset,
            from,
            to,
            amount,
        } => {
            println!(
                "transferring from {:?} to {:?} amount {:?}",
                from, to, amount
            );
            api.anvil_impersonate_account(from).await?;

            let call = ERC20::transferCall {
                to,
                amount: U256::from(amount),
            };

            let tx = TransactionRequest {
                to: Some(asset),
                input: TransactionInput::new(call.abi_encode().into()),
                ..Default::default()
            };

            let _ = api.send_transaction(tx).await?;

            api.anvil_stop_impersonating_account(from).await?;
        }
        Command::SetBalance { amount, who } => {
            println!("setting balance of {:?} to {:?}", who, amount);
            api.anvil_set_balance(who, amount).await?;
        }
    };

    Ok(())
}

#[derive(thiserror::Error, Debug)]
pub enum ServerError {
    #[error("An unknown error occurred while processing the request {}", .0.to_string())]
    Anyhow(#[from] anyhow::Error),

    #[error("An unknown error occurred while processing the request {}", .0)]
    String(String),

    #[error("Backend Error {}", .0)]
    BlockchainError(#[from] BlockchainError),
}

impl ServerError {
    fn str_err(e: String) -> Self {
        ServerError::String(e)
    }
}

impl IntoResponse for ServerError {
    fn into_response(self) -> axum::http::Response<axum::body::Body> {
        axum::http::Response::builder()
            .status(500)
            .body(axum::body::Body::from(self.to_string()))
            .expect("valid axum response")
    }
}
