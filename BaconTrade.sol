pragma solidity ^0.4.19;

import "./oraclizeLib.sol";
import "./BaconUpdateable.sol";

contract BaconTrade is BaconUpdateable{

	//  events
	event tradeOpenInitiated(
		uint tradeId,
		address indexed trader, 
		string symbol,
		bool isLong
	);

	event tradeOpenComplete(
		uint tradeId, 
		address indexed trader, 
		string symbol, 
		bool isLong, 
		uint entryPrice, 
		uint entryTime
	);
	
	event tradeCloseInitiated(
		uint tradeId, 
		address indexed trader
	);
	
	event tradeCloseComplete(
		uint tradeId, 
		address indexed trader, 
		string symbol, 
		bool isLong, 
		uint entryPrice, 
		uint entryTime, 
		uint exitPrice, 
		uint exitTime
	);
	
	event oracleizeQuery(
		uint tradeId, 
		string symbol
	);
	
	event oracleizeResponse(
		uint tradeId,
		string symbol,
		uint response
	);
	
	// store users by address
	struct UserStruct {
		uint[] openTrades;
		uint[] closedTrades;
		uint winners;
		uint totalPct;
		bool isReal;
	}
	mapping(address => UserStruct) public users;

	// store trade info 
	struct TradeStruct {
		uint tradeId;
		uint symbolId;
		bool isLong;
		uint entryPrice;
		uint entryTime;
		uint exitPrice;
		uint exitTime;
		bool isReal;
	}
	TradeStruct[] trades;

	// map the oraclize query ids to uint 'pointers' so we can have a reference to a specific trade
	struct QueryToIndexStruct {
		address userAddress;
		uint tradeId;
		uint userOpenTradeId;
		bool isReal;
	}
	mapping(bytes32 => QueryToIndexStruct) queryToIndex;

	function BaconTrade() public {
		oraclizeLib.oraclize_setProof(oraclizeLib.proofType_TLSNotary() | oraclizeLib.proofStorage_IPFS());

		updateSymbols();
		updateFeeAmount();
	}

	function () public payable {}

	function openTrade(uint symbolIndex, bool isLong) public payable returns (uint) {

		// ensure we received enough funds in order to pay for oracleize transactions x2
		require(msg.value >= 0.03 ether);

		// ensure trader is submitting an acceptable symbol
		require(symbols[symbolIndex].isReal);

		// get the new tradeId
		uint tradeId = trades.length;

		// add the trade
		trades.push(TradeStruct({
			tradeId: tradeId,
			symbolId: symbolIndex,
			isLong: isLong,
			entryPrice: 0,
			entryTime: 0,
			exitPrice: 0,
			exitTime: 0,
			isReal: true
		}));
		
		// store a reference to the trade by the account address
		users[msg.sender].openTrades.push(tradeId);

		// use oraclize to update the price and entry time
		bool success = updatePrice(tradeId);

		if (success) {
			// fire the event
			tradeOpenInitiated(
				tradeId,
				msg.sender,
				symbols[symbolIndex].symbol,
				isLong
			);
		}

		return tradeId;
	}

	function updatePrice(uint tradeId) internal returns (bool success) {
		
		// ensure this is being done by the proper account and that it is an open trade
		var (hasTrade, userOpenTradeId) = userHasOpenTrade(msg.sender, tradeId);
		if (!hasTrade) {
			return false;
		}

		// check that this account can pay the oraclize fee
        if (oraclizeLib.oraclize_getPrice("URL") > address(msg.sender).balance) {
        	return false;

        // query oraclize for the appropriate crypto price
        } else {
            oracleizeQuery(tradeId, symbols[trades[tradeId].symbolId].symbol);
            
            // construct the url using the appropriate ticker symbol
            // query the service and retain the queryId for internal mapping on __callback
			bytes32 queryId = oraclizeLib.oraclize_query("URL", strConcat(oUrlPre, symbols[trades[tradeId].symbolId].symbol, oUrlPost));
        
            queryToIndex[queryId].userAddress = msg.sender;
            queryToIndex[queryId].tradeId = tradeId;
            queryToIndex[queryId].userOpenTradeId = userOpenTradeId;
            queryToIndex[queryId].isReal = true;

            return true;
        }
    }

    function __callback(bytes32 myid, string _result, bytes proof) public {
    	
    	// the update must be from the oraclize service
    	//require(msg.sender == oraclize_cbAddress());
    	require(msg.sender == oraclizeLib.oraclize_cbAddress());

    	// this must be a valid query id
    	require(queryToIndex[myid].isReal);

    	uint result = parseInt(_result, 8);

    	oracleizeResponse(queryToIndex[myid].tradeId, symbols[trades[queryToIndex[myid].tradeId].symbolId].symbol, result);

    	TradeStruct trade = trades[queryToIndex[myid].tradeId];

        // update trade
        if (trade.entryPrice==0) {
        	trade.entryPrice = result;
        	trade.entryTime = block.timestamp;

        	tradeOpenComplete(
        		queryToIndex[myid].tradeId,
        		queryToIndex[myid].userAddress,
        		symbols[trade.symbolId].symbol,
        		trade.isLong,
        		trade.entryPrice,
        		trade.entryTime
        	);

        } else {
        	trade.exitPrice = result;
        	trade.exitTime = block.timestamp;

        	// move this trade to closedTrades
        	users[queryToIndex[myid].userAddress].closedTrades.push(queryToIndex[myid].tradeId);

        	// remove from this user's open trades
        	if (queryToIndex[myid].userOpenTradeId >= users[queryToIndex[myid].userAddress].openTrades.length) return;
	        for (uint i = queryToIndex[myid].userOpenTradeId; i<users[queryToIndex[myid].userAddress].openTrades.length-1; i++){
	            users[queryToIndex[myid].userAddress].openTrades[i] = users[queryToIndex[myid].userAddress].openTrades[i+1];
	        }
	        users[queryToIndex[myid].userAddress].openTrades.length--;

        	//delete users[queryToIndex[myid].userAddress].openTrades[queryToIndex[myid].userOpenTradeId];

        	tradeCloseComplete(
        		queryToIndex[myid].tradeId,
        		queryToIndex[myid].userAddress,
        		symbols[trade.symbolId].symbol,
        		trade.isLong,
        		trade.entryPrice,
        		trade.entryTime,
        		trade.exitPrice,
        		trade.exitTime
        	);

        	//calculateRewards(trade, queryToIndex[myid].userAddress);
        	
        }

        // remove the reference from query to trade tradeId
        delete queryToIndex[myid];
        
    }

    function calculateRewards(TradeStruct trade, address trader) internal returns (bool success) {
    	// add to the total totalPct tally for this user (to be used with closedTrades.length to determine avg pct win/loss)
    	uint pct = trade.exitPrice - trade.entryPrice / trade.entryPrice * 100;
    	users[trader].totalPct += pct;

    	if (pct>0) {
        	// add to the winning trades total tally for this user
    		users[trader].winners += 1;

    		// mint rewards
    		rewardTrader(trader, REWARD_AMOUNT * pct / 100, trade.tradeId);
    	}
    }

    function closeTrade(uint tradeId) public {

    	// ensure this trade has the entry data populated already, or we risk a re-entrancy exploit
    	require(trades[tradeId].entryPrice != 0);

    	// use oraclize to update the exit price and exit time
		bool success = updatePrice(tradeId);

		if (success) {
			// fire the event
			tradeCloseInitiated(
				tradeId,
				msg.sender
			);
		}

	}

	function userHasOpenTrade(address account, uint tradeId) internal view returns (bool hasTrade, uint userOpenTradeId) {
		for (uint i = 0; i < users[account].openTrades.length; i++) {
			if (users[account].openTrades[i]==tradeId) {
				return (true, i);
			}
		}
		return (false, 0);
	}

	function getTrade(uint tradeId) external view returns (uint _tradeId, string symbol, bool isLong, uint entryPrice, uint entryTime, uint exitPrice, uint exitTime) {
		require(trades[tradeId].isReal);
    	return (tradeId, symbols[trades[tradeId].symbolId].symbol, trades[tradeId].isLong, trades[tradeId].entryPrice, trades[tradeId].entryTime, trades[tradeId].exitPrice, trades[tradeId].exitTime);
	}

	function getOpenTrades() external view returns (uint[] tradeIds) {
		return users[msg.sender].openTrades;
	}

	function getClosedTrades() external view returns (uint[] tradeIds) {
		return users[msg.sender].closedTrades;
	}

	function strCompare(string _a, string _b) public pure returns (int) {
        bytes memory a = bytes(_a);
        bytes memory b = bytes(_b);
        uint minLength = a.length;
        if (b.length < minLength) minLength = b.length;
        for (uint i = 0; i < minLength; i ++)
            if (a[i] < b[i])
                return -1;
            else if (a[i] > b[i])
                return 1;
        if (a.length < b.length)
            return -1;
        else if (a.length > b.length)
            return 1;
        else
            return 0;
    }

    function parseInt(string _a, uint _b) internal pure returns (uint) {
		bytes memory bresult = bytes(_a);
		uint mint = 0;
		bool decimals = false;
		for (uint i = 0; i < bresult.length; i++) {
			if ((bresult[i] >= 48) && (bresult[i] <= 57)) {
				if (decimals) {
					if (_b == 0) break;
						else _b--;
				}
				mint *= 10;
				mint += uint(bresult[i]) - 48;
			} else if (bresult[i] == 46) decimals = true;
		}
		return mint;
	}

	function strConcat(string _a, string _b, string _c, string _d, string _e) internal returns (string){
	    bytes memory _ba = bytes(_a);
	    bytes memory _bb = bytes(_b);
	    bytes memory _bc = bytes(_c);
	    bytes memory _bd = bytes(_d);
	    bytes memory _be = bytes(_e);
	    string memory abcde = new string(_ba.length + _bb.length + _bc.length + _bd.length + _be.length);
	    bytes memory babcde = bytes(abcde);
	    uint k = 0;
	    for (uint i = 0; i < _ba.length; i++) babcde[k++] = _ba[i];
	    for (i = 0; i < _bb.length; i++) babcde[k++] = _bb[i];
	    for (i = 0; i < _bc.length; i++) babcde[k++] = _bc[i];
	    for (i = 0; i < _bd.length; i++) babcde[k++] = _bd[i];
	    for (i = 0; i < _be.length; i++) babcde[k++] = _be[i];
	    return string(babcde);
	}

	function strConcat(string _a, string _b, string _c, string _d) internal returns (string) {
	    return strConcat(_a, _b, _c, _d, "");
	}

	function strConcat(string _a, string _b, string _c) internal returns (string) {
	    return strConcat(_a, _b, _c, "", "");
	}

	function strConcat(string _a, string _b) internal returns (string) {
	    return strConcat(_a, _b, "", "", "");
	}
}