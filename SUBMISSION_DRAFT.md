# DoraHacks BUIDL draft: Arc Microgrants (fill in the <…> placeholders; submit yourself)

**Name:** MilestonePay
**Tagline:** Milestone escrow for freelancers: the client locks USDC, the freelancer gets paid per milestone, instantly on Arc.

**Description:**
Millions of freelancers, many of them in Bangladesh, South Asia and Africa, are paid by overseas clients through slow and expensive rails, and often with no guarantee of payment. MilestonePay is a USDC escrow on Arc. A client funds a job split into milestones. The freelancer submits each deliverable as a hash. The client approves it and USDC lands immediately for a fraction of a cent. If the client goes silent past the review window, the freelancer can claim. An optional arbiter that both sides choose can split a disputed milestone. The contract never mixes Arc's 18-decimal native balance with the 6-decimal ERC-20 interface, handles the USDC blocklist safely (a reverted payout keeps the funds in escrow), and is covered by 13 Foundry tests including a fuzz solvency invariant.

Built in Arc Studio (contract, tests, testnet deploy, app), then deployed to Arc mainnet, where real USDC has moved through the escrow.

**Arc Studio project:** https://studio.arc.io/app/<id>
**Live app:** <https://…>
**Mainnet contract:** https://explorer.arc.io/address/<0x…>
**Mainnet USDC tx:** https://explorer.arc.io/tx/<0x…>  (createJob / approve payout)
**Repo:** https://github.com/<you>/milestonepay
**Video:** <YouTube/Loom link>
**Builder profile:** <GitHub / X>

**What's next:** agent-to-agent milestone payments (x402), recurring retainers, and invoice links fundable from any CCTP chain.
