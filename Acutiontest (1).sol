// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IERC721 {
    function safeTransferFrom(address from, address to, uint tokenId) external;

    function transferFrom(address, address, uint) external;
}

enum BidStatus { NotStarted, Successful, Withdrawn } 

struct AuctionDetails {
    address nft;
    uint nftId;
    address seller;
    uint endAt;
    bool started;
    bool ended;
    uint auctionDuration;
    address highestBidder;
    uint highestBid;
    bool isEnglishAuction;
    string name;
}



contract Auction {
    event Start();
    event Bid(address indexed sender, uint amount);
    event Withdraw(address indexed bidder, uint amount);
    event End(address winner, uint amount);

    IERC721 public nft;
    uint public nftId;

    address payable public seller;
    uint public endAt;
    bool public started;
    bool public ended;
    uint public auctionDuration;

    address public highestBidder;
    uint256 public highestBid;
    mapping(address => uint) public bids;

    bool public isEnglishAuction;

    string public name; 

    constructor(
        address _nft,
        uint _nftId,
        uint _startingBid,
        uint _auctionDuration,
        bool _isEnglishAuction,
        string memory _name // Add auction name as a parameter
    ) {
        nft = IERC721(_nft);
        nftId = _nftId;
        seller = payable(msg.sender);
        highestBid = _startingBid;
        auctionDuration = _auctionDuration; 
        isEnglishAuction = _isEnglishAuction;

        name = _name;
    }

   function start() external {
        require(!started, "started");
        //require(msg.sender == seller, "not seller");

        nft.transferFrom(msg.sender, address(this), nftId);
        started = true;
        endAt = block.timestamp + auctionDuration;

        emit Start();
    }

    function bid() external payable {
        require(started, "not started");
        require(block.timestamp < endAt, "ended");

        uint currentPrice;
        if (isEnglishAuction) {
            currentPrice = highestBid;
        } else {
            currentPrice = getCurrentPrice();
        }

        require(msg.value > currentPrice, "value <= current price");

        if (highestBidder != address(0)) {
            bids[highestBidder] += highestBid;
        }

        if (msg.sender != highestBidder) {
            uint previousBid = bids[msg.sender];
            bids[msg.sender] = 0;
            payable(msg.sender).transfer(previousBid);
            emit Withdraw(msg.sender, previousBid);
        }

        highestBidder = msg.sender;
        highestBid = msg.value;

        emit Bid(msg.sender, msg.value);
    }

    function placeBid() external payable {
        require(started, "not started");
        require(block.timestamp < endAt, "ended");

        uint256 currentPrice;
        if (isEnglishAuction) {
            currentPrice = highestBid;
        } else {
            currentPrice = getCurrentPrice();
        }

        require(msg.value > currentPrice, "value <= current price");

        if (highestBidder != address(0)) {
            bidStatus[highestBidder] = BidStatus.Withdrawn;
            bids[highestBidder] += highestBid;
        }

        highestBidder = msg.sender;
        highestBid = msg.value;
        bidStatus[msg.sender] = BidStatus.Successful;

        emit Bid(msg.sender, msg.value);
    }

    mapping(address => BidStatus) public bidStatus;
    function getBidStatus(address bidder) external view returns (BidStatus) {
        return bidStatus[bidder];
        }


    function withdraw() external {
        uint bal = bids[msg.sender];
        bids[msg.sender] = 0;
        payable(msg.sender).transfer(bal);

        emit Withdraw(msg.sender, bal);
    }


    function end() external {
        require(started, "not started");
        require(block.timestamp >= endAt, "not ended");
        require(!ended, "ended");

        ended = true;
        if (highestBidder != address(0)) {
            nft.safeTransferFrom(address(this), highestBidder, nftId);
            seller.transfer(highestBid);
        } else {
            nft.safeTransferFrom(address(this), seller, nftId);
        }

        emit End(highestBidder, highestBid);
    }

    function getCurrentPrice() public view returns (uint) {
        uint elapsedTime = block.timestamp - (started ? block.timestamp : endAt - auctionDuration);
        if (elapsedTime >= auctionDuration) {
            return 0;
        }
        return highestBid - highestBid * elapsedTime / auctionDuration;
    }
    

    function getAuctionDetails() public view returns (AuctionDetails memory) {
        return AuctionDetails({
            nft: address(nft),
            nftId: nftId,
            seller: seller,
            endAt: endAt,
            started: started,
            ended: ended,
            auctionDuration: auctionDuration,
            highestBidder: highestBidder,
            highestBid: highestBid,
            isEnglishAuction: isEnglishAuction,
            name: name
        });
    }



}

contract AuctionFactory {
    event AuctionCreated(address indexed auctionAddress, address indexed creator, address indexed nft, uint nftId, uint startingBid, bool isEnglishAuction);
    event BidPlaced(uint auctionId, address bidder, uint amount);

    mapping(address => address[]) private userBids;

    struct AuctionData {
        address auctionContract;
        address nft;
        uint256 nftId;
        address seller;
        uint256 endAt;
        bool started;
        bool ended;
        uint256 auctionDuration;
        address highestBidder;
        uint256 highestBid;
        bool isEnglishAuction;
        string name;
    }

    AuctionData[] public auctions;

    function createAuction(address _nft, uint _nftId, uint _startingBid, uint _auctionDuration, bool _isEnglishAuction, string memory _name) external {
        Auction newAuction = new Auction(_nft, _nftId, _startingBid, _auctionDuration, _isEnglishAuction, _name);
        auctions.push(AuctionData({
            auctionContract: address(newAuction),
            nft: _nft,
            nftId: _nftId,
            seller: msg.sender,
            endAt: block.timestamp + _auctionDuration,
            started: true,
            ended: false,
            auctionDuration: _auctionDuration,
            highestBidder: address(0),
            highestBid: _startingBid,
            isEnglishAuction: _isEnglishAuction,
            name: _name
        }));
    }

    function getAuctions() external view returns (AuctionData[] memory) {
        return auctions;
    }


    function getAllAuctionsDetails() external view returns (AuctionDetails[] memory) {
        AuctionDetails[] memory allAuctionsDetails = new AuctionDetails[](auctions.length);
        
        for (uint256 i = 0; i < auctions.length; i++) {
            AuctionData storage auctionData = auctions[i];
            allAuctionsDetails[i] = AuctionDetails(
                auctionData.nft,
                auctionData.nftId,
                auctionData.seller,
                auctionData.endAt,
                auctionData.started,
                auctionData.ended,
                auctionData.auctionDuration,
                auctionData.highestBidder,
                auctionData.highestBid,
                auctionData.isEnglishAuction,
                auctionData.name
            );
        }

        return allAuctionsDetails;
    }


    function placeBid(uint256 nftId) external payable {
        require(nftId < auctions.length, "Invalid auction ID");
        
        AuctionData storage auctionData = auctions[nftId];
        require(auctionData.auctionContract != address(0), "Auction not found");

       if (auctionData.highestBid > 0) {
           payable(auctionData.highestBidder).transfer(auctionData.highestBid);
        }

        // Update the highest bid and bidder
        auctionData.highestBid = msg.value;
        auctionData.highestBidder = msg.sender;

    }

    function getMyBiddedAuctions() public view returns (AuctionDetails[] memory) {
        uint auctionCount = auctions.length;
        AuctionDetails[] memory myBiddedAuctions = new AuctionDetails[](auctionCount);
        uint index = 0;
        for (uint i = 0; i < auctionCount; i++) {
            AuctionData storage auctionData = auctions[i];
            myBiddedAuctions[index] = AuctionDetails(
                auctionData.nft,
                auctionData.nftId,
                auctionData.seller,
                auctionData.endAt,
                auctionData.started,
                auctionData.ended,
                auctionData.auctionDuration,
                auctionData.highestBidder,
                auctionData.highestBid,
                auctionData.isEnglishAuction,
                auctionData.name
            );
            index++;
        }

        // Resize the array to remove empty elements (if any)
        if (index < auctionCount) {
            assembly {
                mstore(myBiddedAuctions, index)
            }
        }

        return myBiddedAuctions;
    }


}
