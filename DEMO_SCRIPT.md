# 2–3 minute video walkthrough (record with OBS or Loom)

1. **0:00 Problem (15s).** "Freelancers get paid late, lose fees, or don't get paid at all. MilestonePay locks the client's USDC up front and releases it per milestone on Arc."
2. **0:15 Arc Studio (40s).** Show the Studio project: the prompts and chat history, the contract, the tests running green in Studio, and the testnet deployment.
3. **0:55 Mainnet contract (15s).** Open explorer.arc.io/address/<contract>. Show that it is verified and the deploy tx.
4. **1:10 Live app with real USDC (60s).** Wallet A (client) creates a job with 1 + 1 USDC, confirms the approve and createJob txs, and opens the tx on explorer.arc.io. Switch to wallet B (freelancer) and submit milestone 0. Switch back to A, approve it, and show B's balance go up by 1 USDC and the payout tx hash.
5. **2:10 Safety (20s).** Show the timeout claim, disputes with an arbiter split, and the deadline refund. Mention 13 tests including a fuzz solvency test.
6. **2:30 Next (15s).** Agent-to-agent milestone payments (x402) and invoice links funded from any chain through CCTP.
