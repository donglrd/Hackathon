// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

/// @title CrowdFunding Vending Machine
/// @notice Lets creators open presale-style campaigns, accept ETH support, and let supporters redeem products after success.
contract CrowdFundingVendingMachine {
    enum CampaignState {
        Active,
        Successful,
        Failed,
        Cancelled
    }

    struct Campaign {
        address creator;
        string productURI;
        uint256 goal;
        uint256 price;
        uint256 deadline;
        uint256 supply;
        uint256 sold;
        uint256 pledged;
        bool fundsClaimed;
        bool cancelled;
    }

    uint256 public campaignCount;

    mapping(uint256 campaignId => Campaign) private campaigns;
    mapping(uint256 campaignId => mapping(address supporter => uint256 quantity)) public supportedQuantity;
    mapping(uint256 campaignId => mapping(address supporter => uint256 amount)) public supportedAmount;
    mapping(uint256 campaignId => mapping(address supporter => uint256 quantity)) public redeemedQuantity;

    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed creator,
        uint256 goal,
        uint256 price,
        uint256 deadline,
        uint256 supply,
        string productURI
    );
    event CampaignSupported(uint256 indexed campaignId, address indexed supporter, uint256 quantity, uint256 amount);
    event ProductRedeemed(uint256 indexed campaignId, address indexed supporter, uint256 quantity);
    event FundsClaimed(uint256 indexed campaignId, address indexed creator, uint256 amount);
    event Refunded(uint256 indexed campaignId, address indexed supporter, uint256 amount);
    event CampaignCancelled(uint256 indexed campaignId);

    error InvalidGoal();
    error InvalidPrice();
    error InvalidDeadline();
    error InvalidSupply();
    error CampaignNotFound();
    error NotCreator();
    error CampaignNotActive();
    error CampaignNotSuccessful();
    error CampaignNotFailed();
    error SoldOut();
    error WrongPaymentAmount();
    error NothingToRedeem();
    error NothingToRefund();
    error FundsAlreadyClaimed();
    error TransferFailed();

    function createCrowdCampaign(
        string calldata productURI,
        uint256 goal,
        uint256 price,
        uint256 duration,
        uint256 supply
    ) external returns (uint256 campaignId) {
        if (goal == 0) revert InvalidGoal();
        if (price == 0) revert InvalidPrice();
        if (duration == 0) revert InvalidDeadline();
        if (supply == 0) revert InvalidSupply();

        campaignId = ++campaignCount;
        uint256 deadline = block.timestamp + duration;

        campaigns[campaignId] = Campaign({
            creator: msg.sender,
            productURI: productURI,
            goal: goal,
            price: price,
            deadline: deadline,
            supply: supply,
            sold: 0,
            pledged: 0,
            fundsClaimed: false,
            cancelled: false
        });

        emit CampaignCreated(campaignId, msg.sender, goal, price, deadline, supply, productURI);
    }

    function supportCampaign(uint256 campaignId, uint256 quantity) external payable {
        Campaign storage campaign = _campaign(campaignId);
        if (_state(campaign) != CampaignState.Active) revert CampaignNotActive();
        if (quantity == 0) revert InvalidSupply();
        if (campaign.sold + quantity > campaign.supply) revert SoldOut();

        uint256 expectedPayment = campaign.price * quantity;
        if (msg.value != expectedPayment) revert WrongPaymentAmount();

        campaign.sold += quantity;
        campaign.pledged += msg.value;
        supportedQuantity[campaignId][msg.sender] += quantity;
        supportedAmount[campaignId][msg.sender] += msg.value;

        emit CampaignSupported(campaignId, msg.sender, quantity, msg.value);
    }

    function redeemProduct(uint256 campaignId, uint256 quantity) external {
        Campaign storage campaign = _campaign(campaignId);
        if (_state(campaign) != CampaignState.Successful) revert CampaignNotSuccessful();

        uint256 available = supportedQuantity[campaignId][msg.sender] - redeemedQuantity[campaignId][msg.sender];
        if (quantity == 0 || quantity > available) revert NothingToRedeem();

        redeemedQuantity[campaignId][msg.sender] += quantity;

        emit ProductRedeemed(campaignId, msg.sender, quantity);
    }

    function claimFunds(uint256 campaignId) external {
        Campaign storage campaign = _campaign(campaignId);
        if (msg.sender != campaign.creator) revert NotCreator();
        if (_state(campaign) != CampaignState.Successful) revert CampaignNotSuccessful();
        if (campaign.fundsClaimed) revert FundsAlreadyClaimed();

        campaign.fundsClaimed = true;
        uint256 amount = campaign.pledged;

        (bool ok,) = campaign.creator.call{ value: amount }("");
        if (!ok) revert TransferFailed();

        emit FundsClaimed(campaignId, campaign.creator, amount);
    }

    function refund(uint256 campaignId) external {
        Campaign storage campaign = _campaign(campaignId);
        if (_state(campaign) != CampaignState.Failed && _state(campaign) != CampaignState.Cancelled) {
            revert CampaignNotFailed();
        }

        uint256 amount = supportedAmount[campaignId][msg.sender];
        if (amount == 0) revert NothingToRefund();

        supportedAmount[campaignId][msg.sender] = 0;
        supportedQuantity[campaignId][msg.sender] = 0;

        (bool ok,) = msg.sender.call{ value: amount }("");
        if (!ok) revert TransferFailed();

        emit Refunded(campaignId, msg.sender, amount);
    }

    function cancelCampaign(uint256 campaignId) external {
        Campaign storage campaign = _campaign(campaignId);
        if (msg.sender != campaign.creator) revert NotCreator();
        if (_state(campaign) != CampaignState.Active) revert CampaignNotActive();

        campaign.cancelled = true;

        emit CampaignCancelled(campaignId);
    }

    function getCampaign(uint256 campaignId) external view returns (Campaign memory campaign, CampaignState state) {
        Campaign storage storedCampaign = _campaign(campaignId);
        campaign = storedCampaign;
        state = _state(storedCampaign);
    }

    function stateOf(uint256 campaignId) external view returns (CampaignState) {
        return _state(_campaign(campaignId));
    }

    function _campaign(uint256 campaignId) private view returns (Campaign storage campaign) {
        campaign = campaigns[campaignId];
        if (campaign.creator == address(0)) revert CampaignNotFound();
    }

    function _state(Campaign storage campaign) private view returns (CampaignState) {
        if (campaign.cancelled) return CampaignState.Cancelled;
        if (campaign.pledged >= campaign.goal) return CampaignState.Successful;
        if (block.timestamp >= campaign.deadline) return CampaignState.Failed;
        return CampaignState.Active;
    }
}
