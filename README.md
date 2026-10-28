# MilestonePay: milestone escrow for freelancers, paid in USDC on Arc

Freelancers in places like Bangladesh lose days and 5–10% in fees on cross-border payouts, and they often deliver work without any guarantee of payment. With MilestonePay, a client **locks USDC up front** for a job that is split into milestones. The freelancer submits each deliverable, and the client approves it, which pays the freelancer **instantly in USDC on Arc** for about $0.002 in gas. If the client goes silent after the review window, **the freelancer can claim the payment**. An optional arbiter that both sides pick can split a disputed milestone.

## How it works
| Step | Who | Function |
|---|---|---|
| Create and fund a job (USDC is pulled into escrow) | client | `createJob(freelancer, arbiter, amounts[], reviewPeriod, deadline, title)` |
| Submit a deliverable hash | freelancer | `submit(jobId, i, hash)` |
| Approve and pay | client | `approve(jobId, i)` |
| Dispute (within the review window) / reopen | client | `dispute` / `reopen` |
| Claim after the review window if the client is silent | freelancer | `claimAfterTimeout` |
| Refund the client voluntarily | freelancer | `releaseToClient` |
| Reclaim milestones never submitted, after the deadline | client | `refundUnsubmitted` |
| Split a disputed milestone (basis points to the freelancer) | arbiter | `resolve(jobId, i, bps)` |

Invariant: the contract's USDC balance always equals the sum of the unsettled milestones. This is fuzz-tested.

## Arc-specific notes
- USDC is the gas token. The contract uses **only the ERC-20 interface at `0x3600…0000` (6 decimals)** and never touches `msg.value` (18 decimals), so the two decimal systems are never mixed.
- Arc enforces the USDC blocklist. A payout to a blocklisted address reverts and the funds stay in escrow. This is covered by a test.
- Use **Arc Foundry** (`arc-forge`, `arc-cast`, `arc-anvil --network arc`). Plain anvil does not emulate Arc's native-USDC precompile, so a fork demo of `transferFrom` fails there.

| | Testnet | Mainnet |
|---|---|---|
| Chain ID | 5042002 | 5042 |
| RPC | https://rpc.testnet.arc.io | https://rpc.mainnet.arc.io |
| Explorer | https://explorer.testnet.arc.io | https://explorer.arc.io |
| USDC (ERC-20) | 0x3600000000000000000000000000000000000000 | same |

## Develop
```bash
forge test -vv            # 13 tests including fuzz (or arc-forge test)
./demo/demo-local-fork.sh # full flow on a local arc-anvil fork of Arc testnet, with throwaway keys
```

## Deploy (with your own keystore, never paste a raw key)
```bash
cast wallet import arc-deployer --interactive        # stores an encrypted key
# testnet (get free test USDC at https://faucet.circle.com)
forge script script/Deploy.s.sol --rpc-url arc_testnet --broadcast --account arc-deployer
# mainnet (REAL USDC; deploy costs about 1.65M gas × 25 gwei ≈ 0.04 USDC)
forge script script/Deploy.s.sol --rpc-url arc_mainnet --broadcast --account arc-deployer
```

## Frontend
`web/` is a static page (ethers v6, no build step). Run `cd web && python3 -m http.server 8080` and open
`http://localhost:8080/?net=testnet&c=<contract>`. It can be hosted for free on GitHub Pages, Vercel or Netlify. Switching to mainnet asks for confirmation before moving real USDC.

## Measured costs (Arc, 25 gwei)
deploy ≈ 0.041 USDC · createJob ≈ 0.007 · submit / approve / claim ≈ 0.001–0.002 each.

## Roadmap
x402 / agent-to-agent payments (AI agents hiring other agents per milestone), recurring retainers, and invoice links that a client can fund from any CCTP chain.

License: MIT
