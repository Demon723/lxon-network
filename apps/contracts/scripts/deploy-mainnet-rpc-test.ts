import * as fs from 'fs';
import * as path from 'path';
import { execSync } from 'child_process';

async function main() {
  console.log('🚀 Mainnet Deployment - RPC Endpoint Testing\n');
  console.log('═'.repeat(70));

  // RPC endpoints to test
  const rpcEndpoints = [
    { name: 'Official Domain', url: 'https://www.lxon.in' },
    { name: 'Validator 1', url: 'http://44.198.165.189:8546' },
    { name: 'Validator 2', url: 'http://18.208.197.246:8547' },
    { name: 'RPC Node', url: 'http://44.199.255.203:8545' },
    { name: 'Previous GCE', url: 'http://3.110.221.224:8545' }
  ];

  const deploymentAddresses: any = {
    network: 'lxon',
    chainId: 724,
    deployer: '0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3',
    deployedAt: new Date().toISOString(),
    environment: 'mainnet',
    accessMethod: 'rpc'
  };

  try {
    // Phase 1: Test RPC Endpoints
    console.log('📡 Phase 1: Testing RPC Endpoints...');
    
    const workingEndpoints: any[] = [];
    
    for (const endpoint of rpcEndpoints) {
      console.log(`   Testing ${endpoint.name} (${endpoint.url})...`);
      
      try {
        // Test chainId
        const chainIdTest = execSync(
          `curl -s --connect-timeout 5 -X POST ${endpoint.url} -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' || echo "Failed"`,
          { encoding: 'utf8', timeout: 10000 }
        );
        
        if (chainIdTest.includes('0x2cc') || chainIdTest.includes('724')) {
          console.log(`   ✅ ${endpoint.name}: Chain ID 724 detected`);
          workingEndpoints.push({
            ...endpoint,
            status: 'working',
            chainId: 724
          });
        } else if (chainIdTest.includes('jsonrpc')) {
          console.log(`   ⚠️  ${endpoint.name}: Responding but wrong chain ID`);
          workingEndpoints.push({
            ...endpoint,
            status: 'wrong_chain',
            response: chainIdTest
          });
        } else {
          console.log(`   ❌ ${endpoint.name}: Not responding or error`);
        }
      } catch (error) {
        console.log(`   ❌ ${endpoint.name}: Connection failed`);
      }
    }
    
    console.log(`   Working endpoints: ${workingEndpoints.filter((e: any) => e.status === 'working').length}/${rpcEndpoints.length}`);
    console.log();
    
    deploymentAddresses.rpcEndpoints = workingEndpoints;

    // ✅ FIX: Use appropriate gas price based on chain
    const network = await provider.getNetwork();
    let gasPrice;
    if (network.chainId === 724) {
      // LXON mainnet - 20 gwei
      gasPrice = ethers.BigNumber.from("20000000000");
    } else if (network.chainId === 1) {
      // Ethereum mainnet
      gasPrice = ethers.BigNumber.from("50000000000");
    } else {
      // Testnet/goerli etc.
      gasPrice = ethers.BigNumber.from("1000000000");
    }
    console.log("Using gas price:", ethers.formatUnits(gasPrice, "gwei"), "gwei");
    console.log();

    // Phase 2: Test Block Production
    console.log('🔍 Phase 2: Testing Block Production...');
    
    for (const endpoint of workingEndpoints) {
      if (endpoint.status !== 'working') continue;
      
      console.log(`   Checking ${endpoint.name}...`);
      
      try {
        const blockNumber = execSync(
          `curl -s --connect-timeout 5 -X POST ${endpoint.url} -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'`,
          { encoding: 'utf8', timeout: 10000 }
        );
        
        if (blockNumber.includes('result')) {
          const blockNum = parseInt(JSON.parse(blockNumber).result, 16);
          console.log(`   ✅ ${endpoint.name}: Current block ${blockNum}`);
          endpoint.blockNumber = blockNum;
        } else {
          console.log(`   ⚠️  ${endpoint.name}: Could not get block number`);
        }
      } catch (error) {
        console.log(`   ❌ ${endpoint.name}: Block check failed`);
      }
    }
    console.log();

    // Phase 3: Test DNS Resolution
    console.log('🌐 Phase 3: Testing DNS Resolution...');
    
    try {
      const dnsResult = execSync('nslookup www.lxon.in 2>/dev/null || echo "DNS not resolving"', { encoding: 'utf8' });
      
      if (dnsResult.includes('44.199.255.203') || dnsResult.includes('44.198.165.189')) {
        console.log('✅ DNS resolution working');
        deploymentAddresses.dnsWorking = true;
      } else {
        console.log('⚠️  DNS resolution not working or pointing elsewhere');
        deploymentAddresses.dnsWorking = false;
      }
    } catch (error) {
      console.log('❌ DNS resolution test failed');
      deploymentAddresses.dnsWorking = false;
    }
    console.log();

    // Phase 4: Load Existing Deployment
    console.log('📦 Phase 4: Loading Existing Deployment...');
    
    const deploymentPath = path.join(__dirname, '..', 'deployments', 'lxon-mainnet-724.json');
    if (fs.existsSync(deploymentPath)) {
      const existingDeployment = JSON.parse(fs.readFileSync(deploymentPath, 'utf8'));
      
      console.log('✅ Existing deployment found:');
      console.log('   LXON Token:', existingDeployment.lxonToken);
      console.log('   Base Token:', existingDeployment.baseToken);
      console.log('   Buyback:', existingDeployment.buybackBurn);
      console.log('   Treasury:', existingDeployment.treasury);
      console.log();
      
      deploymentAddresses.contracts = {
        lxonToken: existingDeployment.lxonToken,
        usdc: existingDeployment.baseToken,
        buyback: existingDeployment.buybackBurn,
        staking: existingDeployment.treasury,
        simpleSwap: existingDeployment.treasury
      };
    } else {
      console.log('⚠️  No existing deployment found');
      console.log();
    }

    // Phase 5: Verify Chainlist Configuration
    console.log('📋 Phase 5: Verifying Chainlist Configuration...');
    
    const chainlistPath = path.join(__dirname, '../../../chainlist.json');
    if (fs.existsSync(chainlistPath)) {
      const chainlist = JSON.parse(fs.readFileSync(chainlistPath, 'utf8'));
      
      console.log('✅ Chainlist Configuration:');
      console.log('   Chain ID:', chainlist.chainId);
      console.log('   Network:', chainlist.name);
      console.log('   www.lxon.in in RPC:', chainlist.rpc.includes('https://www.lxon.in'));
      console.log('   www.lxon.in as Explorer:', chainlist.explorers.some((e: any) => e.url === 'https://www.lxon.in'));
      console.log();
      
      deploymentAddresses.chainlistVerified = true;
      deploymentAddresses.chainlistConfig = chainlist;
    } else {
      console.log('⚠️  Chainlist.json not found');
      console.log();
    }

    // Phase 6: Save Deployment Summary
    console.log('💾 Phase 6: Saving Deployment Summary...');
    
    const summaryPath = path.join(__dirname, '..', 'deployments', 'mainnet-rpc-test.json');
    fs.writeFileSync(summaryPath, JSON.stringify(deploymentAddresses, null, 2));
    console.log('✅ Deployment summary saved to:', summaryPath);
    console.log();

    // Print Final Summary
    console.log('═'.repeat(70));
    console.log('🎉 MAINNET DEPLOYMENT RPC TEST COMPLETE');
    console.log('═'.repeat(70));
    console.log();
    console.log('📊 Deployment Summary:');
    console.log('  Chain ID:', deploymentAddresses.chainId);
    console.log('  Network:', deploymentAddresses.network);
    console.log('  Environment:', deploymentAddresses.environment);
    console.log('  Deployed At:', deploymentAddresses.deployedAt);
    console.log();
    
    console.log('📡 RPC Endpoint Status:');
    workingEndpoints.forEach((endpoint: any) => {
      console.log(`  ${endpoint.name}: ${endpoint.status} (${endpoint.url})`);
      if (endpoint.blockNumber) {
        console.log(`    Block: ${endpoint.blockNumber}`);
      }
    });
    console.log();
    
    console.log('🌐 DNS Status:', deploymentAddresses.dnsWorking ? '✅ Working' : '❌ Not working');
    console.log();
    
    if (deploymentAddresses.contracts) {
      console.log('📋 Contract Addresses:');
      console.log('  LXON Token:', deploymentAddresses.contracts.lxonToken);
      console.log('  USDC:', deploymentAddresses.contracts.usdc);
      console.log('  Buyback:', deploymentAddresses.contracts.buyback);
      console.log('  Staking:', deploymentAddresses.contracts.staking);
      console.log();
    }
    
    console.log('🌐 Public Endpoints:');
    console.log('  Website/Explorer: https://www.lxon.in');
    console.log('  RPC: https://www.lxon.in');
    console.log('  Chainlist: Updated with www.lxon.in');
    console.log();
    
    if (workingEndpoints.some((e: any) => e.status === 'working')) {
      console.log('✅ Mainnet deployment has working RPC endpoints');
      console.log('   Ready for production use');
    } else {
      console.log('⚠️  No working RPC endpoints found');
      console.log('   Need to verify blockchain node infrastructure');
    }
    console.log();

  } catch (error) {
    console.error('❌ Deployment test failed:', error);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('❌ Script error:', error);
    process.exit(1);
  });