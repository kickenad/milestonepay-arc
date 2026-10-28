// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address a) external view returns (uint256);
}

/// @title MilestonePay - milestone escrow for freelance work, paid in USDC on Arc
/// @notice A client locks USDC for a job split into milestones. The freelancer submits
///         a deliverable hash per milestone; the client approves (pays out) or disputes.
///         If the client stays silent past the review window, the freelancer can claim.
///         An optional arbiter (chosen by both at job creation) settles disputes with a split.
/// @dev Uses the USDC ERC-20 interface (6 decimals) only. Never touches msg.value, so the
///      native 18-decimal USDC balance and the ERC-20 view are never mixed (see Arc EVM differences).
contract MilestonePay {
    enum Status { None, Funded, Submitted, Disputed, Paid, Refunded, Resolved }

    struct Milestone {
        uint128 amount;       // USDC, 6 decimals
        uint64 submittedAt;   // timestamp of last submission
        Status status;
        bytes32 deliverable;  // e.g. keccak/IPFS digest of the delivered work
    }

    struct Job {
        address client;
        address freelancer;
        address arbiter;      // address(0) = no arbiter; disputes then resolved by mutual refund/approve
        uint64 reviewPeriod;  // seconds the client has to approve/dispute after a submission
        uint64 deadline;      // after this, the client may reclaim milestones never submitted
        string title;
    }

    IERC20 public immutable usdc;
    uint256 public jobCount;
    mapping(uint256 => Job) public jobs;
    mapping(uint256 => Milestone[]) internal _milestones;

    uint64 public constant MIN_REVIEW = 1 hours;
    uint64 public constant MAX_REVIEW = 30 days;
    uint256 public constant MAX_MILESTONES = 20;

    event JobCreated(uint256 indexed jobId, address indexed client, address indexed freelancer, address arbiter, uint256 total, string title);
    event MilestoneSubmitted(uint256 indexed jobId, uint256 indexed index, bytes32 deliverable);
    event MilestonePaid(uint256 indexed jobId, uint256 indexed index, address to, uint256 amount, bool byTimeout);
    event MilestoneDisputed(uint256 indexed jobId, uint256 indexed index);
    event MilestoneRefunded(uint256 indexed jobId, uint256 indexed index, uint256 amount);
    event DisputeResolved(uint256 indexed jobId, uint256 indexed index, uint256 toFreelancer, uint256 toClient);

    error BadParams();
    error NotClient();
    error NotFreelancer();
    error NotArbiter();
    error BadStatus();
    error TooEarly();
    error TooLate();
    error TransferFailed();

    uint256 private _lock = 1;
    modifier nonReentrant() {
        require(_lock == 1, "reentrancy");
        _lock = 2;
        _;
        _lock = 1;
    }

    constructor(IERC20 _usdc) {
        if (address(_usdc) == address(0)) revert BadParams();
        usdc = _usdc;
    }

    // ---------------------------------------------------------------- create

    function createJob(
        address freelancer,
        address arbiter,
        uint128[] calldata amounts,
        uint64 reviewPeriod,
        uint64 deadline,
        string calldata title
    ) external nonReentrant returns (uint256 jobId) {
        uint256 n = amounts.length;
        if (
            freelancer == address(0) || freelancer == msg.sender || arbiter == msg.sender || arbiter == freelancer
                || n == 0 || n > MAX_MILESTONES || reviewPeriod < MIN_REVIEW || reviewPeriod > MAX_REVIEW
                || deadline <= block.timestamp
        ) revert BadParams();

        jobId = ++jobCount;
        jobs[jobId] = Job(msg.sender, freelancer, arbiter, reviewPeriod, deadline, title);

        uint256 total;
        Milestone[] storage ms = _milestones[jobId];
        for (uint256 i; i < n; ++i) {
            if (amounts[i] == 0) revert BadParams();
            total += amounts[i];
            ms.push(Milestone(amounts[i], 0, Status.Funded, bytes32(0)));
        }

        _pull(msg.sender, total);
        emit JobCreated(jobId, msg.sender, freelancer, arbiter, total, title);
    }

    // ---------------------------------------------------------------- freelancer

    /// @notice Submit (or re-submit after a dispute is withdrawn) a deliverable for a milestone.
    function submit(uint256 jobId, uint256 i, bytes32 deliverable) external {
        Job storage j = jobs[jobId];
        if (msg.sender != j.freelancer) revert NotFreelancer();
        Milestone storage m = _m(jobId, i);
        if (m.status != Status.Funded) revert BadStatus();
        m.status = Status.Submitted;
        m.submittedAt = uint64(block.timestamp);
        m.deliverable = deliverable;
        emit MilestoneSubmitted(jobId, i, deliverable);
    }

    /// @notice Client silent past the review window: freelancer claims the milestone.
    function claimAfterTimeout(uint256 jobId, uint256 i) external nonReentrant {
        Job storage j = jobs[jobId];
        if (msg.sender != j.freelancer) revert NotFreelancer();
        Milestone storage m = _m(jobId, i);
        if (m.status != Status.Submitted) revert BadStatus();
        if (block.timestamp < uint256(m.submittedAt) + j.reviewPeriod) revert TooEarly();
        m.status = Status.Paid;
        _push(j.freelancer, m.amount);
        emit MilestonePaid(jobId, i, j.freelancer, m.amount, true);
    }

    /// @notice Freelancer voluntarily gives a milestone back to the client (e.g. cannot deliver).
    function releaseToClient(uint256 jobId, uint256 i) external nonReentrant {
        Job storage j = jobs[jobId];
        if (msg.sender != j.freelancer) revert NotFreelancer();
        Milestone storage m = _m(jobId, i);
        if (m.status != Status.Funded && m.status != Status.Submitted && m.status != Status.Disputed) {
            revert BadStatus();
        }
        m.status = Status.Refunded;
        _push(j.client, m.amount);
        emit MilestoneRefunded(jobId, i, m.amount);
    }

    // ---------------------------------------------------------------- client

    function approve(uint256 jobId, uint256 i) external nonReentrant {
        Job storage j = jobs[jobId];
        if (msg.sender != j.client) revert NotClient();
        Milestone storage m = _m(jobId, i);
        // Client may also approve a milestone early (Funded) or settle a dispute in the freelancer's favour.
        if (m.status != Status.Funded && m.status != Status.Submitted && m.status != Status.Disputed) {
            revert BadStatus();
        }
        m.status = Status.Paid;
        _push(j.freelancer, m.amount);
        emit MilestonePaid(jobId, i, j.freelancer, m.amount, false);
    }

    /// @notice Dispute a submission within the review window. Freezes the milestone.
    function dispute(uint256 jobId, uint256 i) external {
        Job storage j = jobs[jobId];
        if (msg.sender != j.client) revert NotClient();
        Milestone storage m = _m(jobId, i);
        if (m.status != Status.Submitted) revert BadStatus();
        if (block.timestamp >= uint256(m.submittedAt) + j.reviewPeriod) revert TooLate();
        m.status = Status.Disputed;
        emit MilestoneDisputed(jobId, i);
    }

    /// @notice Client withdraws a dispute and lets the freelancer re-submit.
    function reopen(uint256 jobId, uint256 i) external {
        Job storage j = jobs[jobId];
        if (msg.sender != j.client) revert NotClient();
        Milestone storage m = _m(jobId, i);
        if (m.status != Status.Disputed) revert BadStatus();
        m.status = Status.Funded;
    }

    /// @notice After the job deadline, the client reclaims milestones that were never submitted.
    function refundUnsubmitted(uint256 jobId, uint256 i) external nonReentrant {
        Job storage j = jobs[jobId];
        if (msg.sender != j.client) revert NotClient();
        if (block.timestamp <= j.deadline) revert TooEarly();
        Milestone storage m = _m(jobId, i);
        if (m.status != Status.Funded) revert BadStatus();
        m.status = Status.Refunded;
        _push(j.client, m.amount);
        emit MilestoneRefunded(jobId, i, m.amount);
    }

    // ---------------------------------------------------------------- arbiter

    /// @notice Arbiter splits a disputed milestone. freelancerBps out of 10_000.
    function resolve(uint256 jobId, uint256 i, uint16 freelancerBps) external nonReentrant {
        Job storage j = jobs[jobId];
        if (j.arbiter == address(0) || msg.sender != j.arbiter) revert NotArbiter();
        if (freelancerBps > 10_000) revert BadParams();
        Milestone storage m = _m(jobId, i);
        if (m.status != Status.Disputed) revert BadStatus();
        m.status = Status.Resolved;
        uint256 toF = (uint256(m.amount) * freelancerBps) / 10_000;
        uint256 toC = uint256(m.amount) - toF;
        if (toF > 0) _push(j.freelancer, toF);
        if (toC > 0) _push(j.client, toC);
        emit DisputeResolved(jobId, i, toF, toC);
    }

    // ---------------------------------------------------------------- views

    function milestoneCount(uint256 jobId) external view returns (uint256) {
        return _milestones[jobId].length;
    }

    function milestone(uint256 jobId, uint256 i) external view returns (Milestone memory) {
        return _m(jobId, i);
    }

    function milestones(uint256 jobId) external view returns (Milestone[] memory) {
        return _milestones[jobId];
    }

    // ---------------------------------------------------------------- internal

    function _m(uint256 jobId, uint256 i) internal view returns (Milestone storage) {
        Milestone[] storage ms = _milestones[jobId];
        if (i >= ms.length) revert BadParams();
        return ms[i];
    }

    function _pull(address from, uint256 amount) internal {
        uint256 before = usdc.balanceOf(address(this));
        _call(abi.encodeCall(IERC20.transferFrom, (from, address(this), amount)));
        // guard against fee-on-transfer style tokens if a different token is ever used
        if (usdc.balanceOf(address(this)) - before != amount) revert TransferFailed();
    }

    function _push(address to, uint256 amount) internal {
        _call(abi.encodeCall(IERC20.transfer, (to, amount)));
    }

    function _call(bytes memory data) internal {
        (bool ok, bytes memory ret) = address(usdc).call(data);
        if (!ok || (ret.length != 0 && !abi.decode(ret, (bool)))) revert TransferFailed();
    }
}
