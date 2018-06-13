pragma solidity ^0.4.19;

import './BaconBit.sol';

contract BaconUpdateable is BaconBit {

	string oUrlPre = "json(https://bittrex.com/api/v1.1/public/getticker?market=BTC-";
	string oUrlPost = ").result.Last";
	string IPFSHash = "";

	struct SymbolStruct {
		string symbol;
		bool isReal;
	}
	mapping(uint => SymbolStruct) symbols;

	function BaconUpdateable() public {
		
	}

	function updateOURL(string pre, string post) onlyOwner public returns (bool) {
	    oUrlPre = pre;
	    oUrlPost = post;
	}

	function updateIPFS(string hash) onlyOwner public returns (bool) {
		IPFSHash = hash;
	}

	function updateSymbols() onlyOwner public returns (bool) {
		symbols[0] = SymbolStruct("ETH", true);
		symbols[1] = SymbolStruct("NEO", true);
		symbols[2] = SymbolStruct("ZEC", true);
	}

	function updateFeeAmount() onlyOwner public returns (bool) {
		
	}

}

