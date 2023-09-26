// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "../node_modules/openzeppelin-solidity/contracts/token/ERC721/ERC721.sol";
import "../node_modules/openzeppelin-solidity/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "../node_modules/openzeppelin-solidity/contracts/access/Ownable.sol";

// import "./Magnesium.sol";


/*===================================================
    ERC1155 Interface to get balance.
=====================================================*/

interface IMercury {
    function balanceOf(address account, uint256 id)
    external
    view
    returns (uint256);
}


/*===================================================
    ERC20 Interface to send reward.
=====================================================*/

interface IMagnesium {
    function sendMagnesium(address _to, uint256 _amount) external;
}


/*===================================================
    AncientDevice contract
=====================================================*/

contract AncientDevice is ERC721, Ownable, ERC721Enumerable {
    uint256 constant SECINDAY = 3600 * 24;

    uint256 public DEVICE_PRICE = 0 ether;
    uint256 public RESERVED_FOR_DEV = 5;
    uint256 public DEV_COUNT = 0;

    uint256 public constant MAX_DEVICES = 1347;
    uint256 public constant BASE_RATE = 10 ether;

    // yields 10 MAGNESIUM per day
    bool public isLive = true;
    bool public deviceClaiming = true;

    // Mon Jul 07 2025 17:00:00 GMT-0400 (Eastern Daylight Time)
    uint256 constant END = 1751922000;

    // user information
    struct UserInfo {
        uint256 rewards;
        uint256 lastUpdate;
        uint256 userBalance;
        bool    admins;
    }

    mapping(address => UserInfo) userInfos;

    // mercury information
    mapping(uint256 => bool) claimedOnMercury;

    // magnesium token 
    IMagnesium public magnesiumToken;
    IMercury public mercuryToken;

    // Ancient Device Claiming
    struct User {
        address owner;
        uint256 amountOfTokens;
        bool claimed;
    }

    mapping(address => User) mappingToUser;

    address[] public MercuryAddresses;

    constructor(address _magnesium, address _mercury)
    ERC721("Ancient Devices", "ANCIENT")
    {
        mercuryToken = IMercury(_mercury);
        magnesiumToken = IMagnesium(_magnesium);
        admins[msg.sender] = true;
    }

    function addMercuryAddresses(
        address owner,
        uint256 amountOfTokens,
        bool claimed
    ) internal {
        require(admins[msg.sender], "You are not admin");

        mappingToUser[owner].owner = owner;
        mappingToUser[owner].amountOfTokens = amountOfTokens;
        mappingToUser[owner].claimed = claimed;
        MercuryAddresses.push(owner);
    }

    function claimAncientDevices(
        uint256 numberOfTokens,
        uint256 amountOfTokens,
        uint256 claimedMercuryAlready
    ) external {
        require(deviceClaiming, "Ancient Device claiming is disabled.");
        require(isLive, "Can not claim Devices before the planets align...");
        require(
            totalSupply().add(numberOfTokens) <= MAX_DEVICES,
            "Claim would exceed max supply of Devices"
        );

        address _user = msg.sender;
        uint256 amountToClaim = 0;

        if (
            getMercuryTokenBalance(_user) > 0 && !claimedMercuryAlready[_user]
        ) {
            amountToClaim = amountOfTokens;
            claimedMercuryAlready[_user] = true;
        }

        if (amountToClaim > 0) {
            for (uint256 i = 0; i < amountToClaim; i++) {
                uint256 mintIndex = totalSupply();
                if (totalSupply() < MAX_DEVICES) {
                    _safeMint(msg.sender, mintIndex + RESERVED_FOR_DEV);
                }
            }

            updateRewardOnMint(msg.sender, numberOfTokens);
            userBalance[msg.sender] += numberOfTokens;
        }
    }

    function checkClaimedOnMercury(uint256 _address)
    external
    view
    returns (bool)
    {
        return claimedOnMercury[_address];
    }

    function getTotalClaimable(address _user) external view returns (uint256) {
        uint256 time = min(block.timestamp, END);
        uint256 pending = (userBalance[_user] *
        BASE_RATE *
        (time - lastUpdate[_user])) / SECINDAY;
        return rewards[_user] + pending;
    }

    function updateReward(address _from, address _to) private {
        uint256 time = min(block.timestamp, END);
        uint256 timerFrom = lastUpdate[_from];

        if (timerFrom > 0)
            rewards[_from] +=
            (userBalance[_from] * BASE_RATE * (time - timerFrom)) /
            SECINDAY;
        if (timerFrom != END) lastUpdate[_from] = time;
        if (_to != address(0)) {
            uint256 timerTo = lastUpdate[_to];
            if (timerTo > 0)
                rewards[_to] +=
                (userBalance[_to] * BASE_RATE * (time - timerTo)) /
                SECINDAY;
            if (timerTo != END) lastUpdate[_to] = time;
        }
    }

    function getReward() external {
        address _user = msg.sender;
        updateReward(_user, address(0));
        uint256 reward = rewards[_user];
        if (rewards[_user] > 0) {
            rewards[_user] = 0;
            magnesiumtoken.sendMagnesium(_user, reward);
        }
    }

    function sendMagnesium(address _to, uint256 _amount) external {
        require(
            canSendMagnesium[msg.sender],
            "Sorry, but you can't send that."
        );
        _mint(_to, _amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override {
        updateReward(from, to);
        userBalance[from]--;
        userBalance[to]++;
        ERC721.transferFrom(from, to, tokenId);
    }

    function updateRewardOnMint(address _user, uint256 _amount) private {
        uint256 time = min(block.timestamp, END);
        uint256 timerUser = lastUpdate[_user];
        if (timerUser > 0)
            rewards[_user] =
            rewards[_user] +
            (userBalance[_user] * BASE_RATE * (time - timerUser)) /
            SECINDAY +
            _amount;
        else rewards[_user] = rewards[_user] + _amount;
        lastUpdate[_user] = time;
    }

    function reserveForDev(uint256 _amount, address _to) external {
        require(admins[msg.sender], "You are not admin");
        require(
            DEV_COUNT + _amount <= RESERVED_FOR_DEV,
            "Can not mint more than 5 tokens for the dev"
        );

        updateRewardOnMint(_to, _amount);
        userBalance[_to] += _amount;

        for (uint256 i = 0; i < _amount; i++) {
            _safeMint(_to, DEV_COUNT);
            DEV_COUNT++;
        }
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function setTokenURI(string memory tokenURI) external {
        require(admins[msg.sender], "You are not admin");
        tokenURI(tokenURI);
    }

    function updateNFTPrice(uint256 _price) external {
        require(admins[msg.sender], "You are not admin");
        DEVICE_PRICE = _price;
    }

    function goLive() external {
        require(admins[msg.sender], "You are not admin");
        isLive = true;
    }

    function stopLive() external {
        require(admins[msg.sender], "You are not admin");
        isLive = false;
    }

    function setEndTime(uint256 _end) external {
        require(admins[msg.sender], "You are not admin");
        END = _end;
    }

    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        msg.sender.transfer(balance);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public override {
        updateReward(from, to);
        userBalance[from]--;
        userBalance[to]++;
        ERC721.safeTransferFrom(from, to, tokenId, _data);
    }

    function addAddressAsAdmin(address _newAdmin) external onlyOwner {
        admins[_newAdmin] = true;
    }

    function getMercuryTokenBalance(address account)
    internal
    view
    returns (uint256)
    {
        uint256 balance;
        return balance = mercuryToken.balanceOf(account, IMercuryId);
    }
}
