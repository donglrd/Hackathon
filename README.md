# Defiville Hackathon

This repository contains a Solidity entry for issue #7: a simple crowdfunding vending machine.

## What is included

- `CrowdFundingVendingMachine.sol`
- Hardhat tests for campaign creation, support, redemption, creator claims, refunds, cancellation, and basic validation

## Main functions

- `createCrowdCampaign()` creates a presale campaign with a goal, price, deadline, supply, and product URI.
- `supportCampaign()` lets supporters buy one or more product slots with ETH.
- `redeemProduct()` lets supporters redeem their reserved product quantity after the campaign succeeds.

The contract also includes `claimFunds()`, `refund()`, and `cancelCampaign()` so the main flows are complete enough to test.

## Run tests

```bash
npm install
npm test
```
