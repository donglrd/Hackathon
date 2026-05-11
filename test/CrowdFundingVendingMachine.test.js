const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("CrowdFundingVendingMachine", function () {
  const productURI = "ipfs://defiville-campaign-1";
  const goal = ethers.parseEther("3");
  const price = ethers.parseEther("1");
  const duration = 7 * 24 * 60 * 60;
  const supply = 5;

  async function deployMachine() {
    const [creator, supporter, other] = await ethers.getSigners();
    const Machine = await ethers.getContractFactory("CrowdFundingVendingMachine");
    const machine = await Machine.deploy();

    return { machine, creator, supporter, other };
  }

  async function createCampaign(machine) {
    const tx = await machine.createCrowdCampaign(productURI, goal, price, duration, supply);
    await tx.wait();
    return 1n;
  }

  it("creates a campaign", async function () {
    const { machine, creator } = await deployMachine();

    const tx = await machine.createCrowdCampaign(productURI, goal, price, duration, supply);

    await expect(tx)
      .to.emit(machine, "CampaignCreated")
      .withArgs(1, creator.address, goal, price, (await time.latest()) + duration, supply, productURI);

    const [campaign, state] = await machine.getCampaign(1);
    expect(campaign.creator).to.equal(creator.address);
    expect(campaign.productURI).to.equal(productURI);
    expect(campaign.goal).to.equal(goal);
    expect(campaign.price).to.equal(price);
    expect(campaign.supply).to.equal(supply);
    expect(state).to.equal(0);
  });

  it("accepts support and marks a funded campaign successful", async function () {
    const { machine, supporter, other } = await deployMachine();
    const campaignId = await createCampaign(machine);

    await expect(machine.connect(supporter).supportCampaign(campaignId, 2, { value: ethers.parseEther("2") }))
      .to.emit(machine, "CampaignSupported")
      .withArgs(campaignId, supporter.address, 2, ethers.parseEther("2"));

    await machine.connect(other).supportCampaign(campaignId, 1, { value: price });

    expect(await machine.stateOf(campaignId)).to.equal(1);
    expect(await machine.supportedQuantity(campaignId, supporter.address)).to.equal(2);
  });

  it("lets supporters redeem after the campaign succeeds", async function () {
    const { machine, supporter, other } = await deployMachine();
    const campaignId = await createCampaign(machine);

    await machine.connect(supporter).supportCampaign(campaignId, 2, { value: ethers.parseEther("2") });
    await machine.connect(other).supportCampaign(campaignId, 1, { value: price });

    await expect(machine.connect(supporter).redeemProduct(campaignId, 2))
      .to.emit(machine, "ProductRedeemed")
      .withArgs(campaignId, supporter.address, 2);

    expect(await machine.redeemedQuantity(campaignId, supporter.address)).to.equal(2);
    await expect(machine.connect(supporter).redeemProduct(campaignId, 1)).to.be.revertedWithCustomError(
      machine,
      "NothingToRedeem",
    );
  });

  it("lets the creator claim funds after success", async function () {
    const { machine, creator, supporter, other } = await deployMachine();
    const campaignId = await createCampaign(machine);

    await machine.connect(supporter).supportCampaign(campaignId, 2, { value: ethers.parseEther("2") });
    await machine.connect(other).supportCampaign(campaignId, 1, { value: price });

    await expect(machine.claimFunds(campaignId)).to.changeEtherBalances(
      [machine, creator],
      [-goal, goal],
    );

    await expect(machine.claimFunds(campaignId)).to.be.revertedWithCustomError(machine, "FundsAlreadyClaimed");
  });

  it("refunds supporters if the campaign fails", async function () {
    const { machine, supporter } = await deployMachine();
    const campaignId = await createCampaign(machine);

    await machine.connect(supporter).supportCampaign(campaignId, 1, { value: price });
    await time.increase(duration + 1);

    await expect(machine.connect(supporter).refund(campaignId)).to.changeEtherBalances(
      [machine, supporter],
      [-price, price],
    );

    expect(await machine.supportedAmount(campaignId, supporter.address)).to.equal(0);
  });

  it("refunds supporters if the creator cancels", async function () {
    const { machine, supporter } = await deployMachine();
    const campaignId = await createCampaign(machine);

    await machine.connect(supporter).supportCampaign(campaignId, 1, { value: price });
    await machine.cancelCampaign(campaignId);

    await expect(machine.connect(supporter).refund(campaignId)).to.changeEtherBalances(
      [machine, supporter],
      [-price, price],
    );
  });

  it("rejects wrong payment amounts and overselling", async function () {
    const { machine, supporter } = await deployMachine();
    const campaignId = await createCampaign(machine);

    await expect(machine.connect(supporter).supportCampaign(campaignId, 2, { value: price }))
      .to.be.revertedWithCustomError(machine, "WrongPaymentAmount");

    await expect(machine.connect(supporter).supportCampaign(campaignId, supply + 1, { value: price * BigInt(supply + 1) }))
      .to.be.revertedWithCustomError(machine, "SoldOut");
  });
});
