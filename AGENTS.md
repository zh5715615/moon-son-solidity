# Project instructions

Before deployment-related work, read `PROJECT_MEMORY.md` and
`deployments/bsc-testnet-97.json`.

Every successful contract deployment must be recorded through
`scripts/lib/record-deployment.js`. The record must include contract name,
contract address, deployment transaction hash, block number, block timestamp,
network, chain ID, deployer and constructor arguments. Keep
`DEPLOYMENTS.md` synchronized with the JSON registry.

Never commit private keys, mnemonics, RPC access tokens or other secrets.
Deployment credentials belong in the gitignored `.env` file or temporary
process environment variables.
