pragma solidity ^0.4.19;

import './StandardToken.sol';
import './Ownable.sol';

contract BaconBit is StandardToken, Ownable {

	event rewardsDistributed(
		address indexed to,
		uint256 amount,
		uint tradeId
	);

	string public name = "BaconBit";
	string public symbol = "XBB";
	uint8 public decimals = 18;
	uint public INITIAL_SUPPLY = 0;
	uint public REWARD_AMOUNT = 1000;

	function BaconBit() public {
		totalSupply_ = INITIAL_SUPPLY;
		balances[msg.sender] = INITIAL_SUPPLY;
	}

	function rewardTrader(address _trader, uint256 _amount, uint _tradeId) internal returns (bool) {
	    totalSupply_ = totalSupply_.add(_amount);
	    balances[_trader] = balances[_trader].add(_amount);
	    rewardsDistributed(_trader, _amount, _tradeId);
	    Transfer(address(0), _trader, _amount);
	    return true;
	}

}

