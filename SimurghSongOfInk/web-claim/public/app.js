import { BrowserProvider, Contract, parseEther } from 'https://esm.sh/ethers@6.11.1';

const log = (...a) => (document.querySelector('#log').textContent += a.join(' ') + "\n");

let provider, signer, account;
const abi = [
  "function balanceOf(address owner) view returns (uint256)",
  "function mint(address to, uint256 amount)"
];
let contractAddress = localStorage.getItem('sim_address') || "";

async function connect() {
  if (!window.ethereum) return log('No wallet');
  provider = new BrowserProvider(window.ethereum);
  await provider.send("eth_requestAccounts", []);
  signer = await provider.getSigner();
  account = await signer.getAddress();
  log('Connected:', account);
}

async function claim() {
  if (!contractAddress) return log('Set SIM address in localStorage: sim_address');
  const c = new Contract(contractAddress, abi, signer);
  try {
    const tx = await c.mint(account, parseEther('1'));
    log('Mint sent:', tx.hash);
    await tx.wait();
    const bal = await c.balanceOf(account);
    log('Balance:', bal.toString());
  } catch(e) { log('Error:', e.message); }
}

const btnConnect = document.querySelector('#connect');
const btnClaim = document.querySelector('#claim');
btnConnect.onclick = connect;
btnClaim.onclick = claim;
window.addEventListener('load', () => { btnClaim.disabled = false; });
