# Rebuilding MilestonePay inside Arc Studio (required by the grant rules)

The grant only counts projects **built in Arc Studio** (https://studio.arc.io). There are two ways to do it:

**A. Import:** push this folder to a public GitHub repo, then run
`npm i -g @circle-fin/arc-studio-cli && arc-studio login && arc-studio clone <github-url>`
(or use "import from GitHub" in the web UI). Then use the prompts below to have Studio test, deploy to testnet and wire up the app, so the Studio history shows real use across contracts, testing and app.

**B. Build from prompts** (paste them one at a time):

1. "Create a Solidity 0.8 contract MilestonePay for milestone escrow paid in Arc USDC through its ERC-20 interface at 0x3600000000000000000000000000000000000000 (6 decimals; never use msg.value). The client calls createJob(freelancer, arbiter, uint128[] amounts, reviewPeriod, deadline, title), which pulls the total via transferFrom. Each milestone has a status: Funded, Submitted, Disputed, Paid, Refunded or Resolved. The freelancer can submit(jobId,i,bytes32 deliverable), claimAfterTimeout once the reviewPeriod has passed since submission, and releaseToClient. The client can approve (pays the freelancer), dispute (within the review window only), reopen, and refundUnsubmitted (Funded milestones after the deadline). An optional arbiter can resolve(jobId,i,freelancerBps) to split the amount. Add a reentrancy guard, custom errors, events, review period between 1 hour and 30 days, at most 20 milestones."
2. "Write Foundry tests with a mock 6-decimal USDC that includes a blocklist. Cover the happy path, access control, the timeout claim, dispute then arbiter split, deadline refunds, a blocklisted payout reverting with funds kept, and a fuzz test that the escrow balance equals the unsettled milestones."
3. "Deploy to Arc testnet and build a simple web app: connect wallet, create and fund a job, view a job by ID, and role-based action buttons."
4. "Make the app network-switchable to Arc mainnet (chain 5042, https://rpc.mainnet.arc.io) with a confirmation before real USDC moves."

Studio deploys to **testnet only**. The mainnet deploy is done by you with your own wallet (see README, `--rpc-url arc_mainnet`). Then point the Studio app at the mainnet address.
