#!/usr/bin/env bash
# End-to-end demo of MilestonePay against a LOCAL fork of Arc testnet (real Arc USDC contract code).
# No real money moves: local arc-anvil fork + throwaway keys only.
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.foundry/bin:$PATH"
# Arc Foundry (arc-anvil/arc-cast/arc-forge) emulates Arc's native-USDC precompile; plain anvil does not.
cast(){ arc-cast "$@"; }; forge(){ arc-forge "$@"; }
cd "$(dirname "$0")/.."
PORT=${PORT:-8547}
RPC=http://127.0.0.1:$PORT
USDC=0x3600000000000000000000000000000000000000

if ! cast chain-id --rpc-url $RPC >/dev/null 2>&1; then
  ARC_ANVIL=${ARC_ANVIL:-$HOME/.local/bin/arc-anvil}
  "$ARC_ANVIL" --network arc --fork-url https://rpc.testnet.arc.io --port $PORT --silent &
  sleep 6
fi

# Fresh throwaway keys generated per run (local fork only; never printed, never funded on a real chain).
# Note: Arc's blocklist rejects anvil's well-known default accounts, so we don't use them.
newkey(){ cast wallet new --json | python3 -c "import json,sys;d=json.load(sys.stdin)[0];print(d['address'],d['private_key'])"; }
read CLIENT CLIENT_PK < <(newkey); read FREEL FREEL_PK < <(newkey); read DEPLOYER DEPLOYER_PK < <(newkey)
GAS="--gas-price 25gwei"

# On Arc the native balance IS USDC (18 dp); the ERC-20 view at 0x36.. shows 6 dp.
for a in $CLIENT $FREEL $DEPLOYER; do
  cast rpc anvil_setBalance $a 0x8AC7230489E80000 --rpc-url $RPC >/dev/null   # 10 USDC
done
bal(){ cast call $USDC "balanceOf(address)(uint256)" $1 --rpc-url $RPC | awk '{print $1}'; }
echo "client USDC (6dp): $(bal $CLIENT)   freelancer: $(bal $FREEL)"

PAY=$(forge create src/MilestonePay.sol:MilestonePay --rpc-url $RPC --private-key $DEPLOYER_PK $GAS \
      --broadcast --constructor-args $USDC 2>&1 | awk '/Deployed to/{print $3}')
[ -n "$PAY" ] || { echo "deploy failed"; exit 1; }
echo "MilestonePay: $PAY"

DEADLINE=$(( $(date +%s) + 7*86400 ))
echo "1) client approves 3 USDC and creates a 2-milestone job (1 + 2 USDC)"
cast send $USDC "approve(address,uint256)" $PAY 3000000 --private-key $CLIENT_PK --rpc-url $RPC $GAS >/dev/null
cast send $PAY "createJob(address,address,uint128[],uint64,uint64,string)" $FREEL 0x0000000000000000000000000000000000000000 \
  "[1000000,2000000]" 3600 $DEADLINE "Logo + landing page" --private-key $CLIENT_PK --rpc-url $RPC $GAS >/dev/null
echo "   escrow holds: $(bal $PAY)"

echo "2) freelancer submits milestone 0"
cast send $PAY "submit(uint256,uint256,bytes32)" 1 0 $(cast keccak "ipfs://logo-v1") --private-key $FREEL_PK --rpc-url $RPC $GAS >/dev/null
echo "3) client approves milestone 0 -> 1 USDC to freelancer"
cast send $PAY "approve(uint256,uint256)" 1 0 --private-key $CLIENT_PK --rpc-url $RPC $GAS >/dev/null
echo "   freelancer: $(bal $FREEL)   escrow: $(bal $PAY)"

echo "4) freelancer submits milestone 1, client goes silent, 1h review window passes"
cast send $PAY "submit(uint256,uint256,bytes32)" 1 1 $(cast keccak "ipfs://landing-v1") --private-key $FREEL_PK --rpc-url $RPC $GAS >/dev/null
cast rpc evm_increaseTime 3601 --rpc-url $RPC >/dev/null; cast rpc evm_mine --rpc-url $RPC >/dev/null
cast send $PAY "claimAfterTimeout(uint256,uint256)" 1 1 --private-key $FREEL_PK --rpc-url $RPC $GAS >/dev/null
echo "   freelancer: $(bal $FREEL)   escrow: $(bal $PAY)"
echo "Done. Escrow should be 0 and freelancer +3 USDC (minus gas, paid in USDC)."
