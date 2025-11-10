let provider, signer, vault, oracle, userAddress;

async function init() {
  const config = await fetch("./config.json").then(r => r.json());
  provider = new ethers.providers.JsonRpcProvider(config.rpcUrl);

  vault = new ethers.Contract(
    config.vaultAddress,
    await fetch(config.vaultABI).then(r => r.json()),
    provider
  );

  oracle = new ethers.Contract(
    config.oracleAddress,
    await fetch(config.oracleABI).then(r => r.json()),
    provider
  );

  document.getElementById("connectWallet").onclick = connectWallet;
  refreshUI();
}

async function connectWallet() {
  if (!window.ethereum) return alert("Install MetaMask!");
  await ethereum.request({ method: "eth_requestAccounts" });
  provider = new ethers.providers.Web3Provider(window.ethereum);
  signer = provider.getSigner();
  userAddress = await signer.getAddress();
  document.getElementById("walletAddress").textContent =
    userAddress.slice(0, 6) + "..." + userAddress.slice(-4);
  refreshUI();
}

async function refreshUI() {
  try {
    const [price, ts] = await oracle.peekPriceView();
    const healthy = await oracle.isHealthy();
    const tsDate = new Date(ts.toNumber() * 1000).toLocaleTimeString();

    document.getElementById("oraclePrice").textContent = (price / 1e18).toFixed(4) + " USD";
    document.getElementById("oracleHealth").textContent = healthy ? "✅ Healthy" : "⚠️ Stale";
    document.getElementById("oracleTimestamp").textContent = tsDate;

    if (!userAddress) return;
    const data = await vault.vaultInfo(userAddress);

    const collateral = data.collateral / 1e18;
    const debt = data.debt / 1e18;
    const ratio = data.ratio / 1;
    const mintable = data.mintable / 1e18;

    document.getElementById("collateral").textContent = collateral.toFixed(3);
    document.getElementById("debt").textContent = debt.toFixed(2);
    document.getElementById("mintable").textContent = mintable.toFixed(2);

    const ratioEl = document.getElementById("ratioText");
    const bar = document.getElementById("ratioBarFill");
    let color = "#00ffb3";
    if (ratio < 130) color = "#ff4d4d";
    else if (ratio < 150) color = "#ffd966";

    ratioEl.style.color = color;
    ratioEl.textContent = ratio.toFixed(1);
    bar.style.background = color;
    bar.style.width = Math.min(ratio, 200) + "%";
  } catch (e) {
    console.error(e);
  }
}

document.getElementById("depositBtn").onclick = async () => {
  if (!signer) return alert("Connect wallet first");
  const amt = prompt("Enter amount of PLS to deposit:");
  if (!amt) return;
  const tx = await vault.connect(signer).depositAndAutoMintPLS({
    value: ethers.utils.parseEther(amt)
  });
  await tx.wait();
  refreshUI();
};

document.getElementById("repayBtn").onclick = async () => {
  if (!signer) return alert("Connect wallet first");
  const amt = prompt("Enter amount of pSunDAI to repay:");
  if (!amt) return;
  const decimals = ethers.utils.parseUnits(amt, 18);
  const tx = await vault.connect(signer).repayAndAutoWithdraw(decimals);
  await tx.wait();
  refreshUI();
};

setInterval(refreshUI, 15000);
window.onload = init;
