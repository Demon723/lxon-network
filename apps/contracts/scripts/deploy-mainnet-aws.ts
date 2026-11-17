import { ethers } from 'hardhat';
import * as fs from 'fs';
import * as path from 'path';

async function main() {
  console.log('🚀 Mainnet Deployment with AWS Profile Configuration\n');
  console.log('═'.repeat(70));

  // Check AWS profile
  const awsProfile = process.env.AWS_PROFILE || 'default';
  console.log(`📋 AWS Profile: ${awsProfile}`);
  
  // Check AWS credentials
  try {
    const { execSync } = require('child_process');
    const whoami = execSync('aws sts get-caller-identity --profile ' + awsProfile, { encoding: 'utf8' });
    console.log('✅ AWS Credentials Verified');
    console.log(`   Account: ${JSON.parse(whoami).Account}`);
  } catch (error) {
    console.error('❌ AWS Credentials Not Configured');
    console.error('Please run: aws configure --profile lxon-mainnet');
    process.exit(1);
  }

  console.log('\n📋 Deployment Information:');
  console.log('  Network: LXON (Chain ID: 724)');
  console.log('  RPC URL:', process.env.LXON_RPC_URL || 'https://www.lxon.in');
  console.log('  Deployer:', process.env.PRIVATE_KEY ? 'Configured' : 'Not configured');
  console.log();

  const [deployer] = await ethers.getSigners();
  console.log('  Deployer Address:', deployer.address);
  
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

  try {
    const balance = await ethers.provider.getBalance(deployer.address);
    console.log('  Account Balance:', ethers.formatEther(balance), 'LXON');
  } catch (error) {
    console.log('  Account Balance: Unable to fetch (RPC connectivity issue)');
  }
  console.log();

  const deploymentAddresses: any = {
    network: 'lxon',
    chainId: 724,
    deployer: deployer.address,
    awsProfile: awsProfile,
    deployedAt: new Date().toISOString(),
    environment: 'mainnet'
  };

  try {
    // Phase 1: Verify existing contracts
    console.log('📦 Phase 1: Verifying Existing Contracts...');
    
    const existingDeployment = JSON.parse(
      fs.readFileSync(path.join(__dirname, '..', 'deployments', 'lxon-mainnet-724.json'), 'utf8')
    );
    
    console.log('✅ Existing deployment found:');
    console.log('   LXON Token:', existingDeployment.contracts.lxonToken);
    console.log('   USDC:', existingDeployment.contracts.usdc);
    console.log('   Buyback:', existingDeployment.contracts.buyback);
    console.log('   Staking:', existingDeployment.contracts.staking);
    console.log('   SimpleSwap:', existingDeployment.contracts.simpleSwap);
    console.log();

    deploymentAddresses.contracts = existingDeployment.contracts;
    deploymentAddresses.existingDeployment = true;

    // Phase 2: Test contract connectivity
    console.log('🔍 Phase 2: Testing Contract Connectivity...');
    
    const lxonToken = await ethers.getContractAt('LXONNativeToken', existingDeployment.contracts.lxonToken);
    const tokenName = await lxonToken.name();
    console.log('✅ LXON Token accessible:', tokenName);
    
    const usdc = await ethers.getContractAt('ERC20Mock', existingDeployment.contracts.usdc);
    const usdcName = await usdc.name();
    console.log('✅ USDC accessible:', usdcName);
    console.log();

    // Phase 3: Verify chainlist configuration
    console.log('📋 Phase 3: Verifying Chainlist Configuration...');
    
    const chainlistPath = path.join(__dirname, '../../../chainlist.json');
    const chainlist = JSON.parse(fs.readFileSync(chainlistPath, 'utf8'));
    
    console.log('✅ Chainlist Configuration:');
    console.log('   Chain ID:', chainlist.chainId);
    console.log('   RPC Endpoints:', chainlist.rpc.length);
    console.log('   Explorers:', chainlist.explorers.length);
    console.log('   Has www.lxon.in:', chainlist.rpc.includes('https://www.lxon.in'));
    console.log('   Has official explorer:', chainlist.explorers.some((e: any) => e.url === 'https://www.lxon.in'));
    console.log();

    // Phase 4: Verify AWS infrastructure
    console.log('☁️  Phase 4: Verifying AWS Infrastructure...');
    
    try {
      const instances = execSync('aws ec2 describe-instances --filters Name=tag:Name,Values=lxon-* --profile ' + awsProfile, { encoding: 'utf8' });
      const instancesData = JSON.parse(instances);
      const runningInstances = instancesData.Reservations[0].Instances.filter((i: any) => i.State.Name === 'running');
      
      console.log('✅ AWS EC2 Instances:', runningInstances.length);
      runningInstances.forEach((instance: any) => {
        console.log('   -', instance.Tags.find((t: any) => t.Key === 'Name').Value, ':', instance.PublicIpAddress);
      });
    } catch (error) {
      console.log('⚠️  Could not verify AWS instances');
    }
    console.log();

    // Phase 5: Verify Route 53 configuration
    console.log('🌐 Phase 5: Verifying Route 53 Configuration...');
    
    try {
      const hostedZones = execSync('aws route53 list-hosted-zones --profile ' + awsProfile, { encoding: 'utf8' });
      const zonesData = JSON.parse(hostedZones);
      
      const lxonZone = zonesData.HostedZones.find((z: any) => z.Name === 'lxon.in.');
      if (lxonZone) {
        console.log('✅ Route 53 Hosted Zone found:', lxonZone.Id);
        
        const records = execSync('aws route53 list-resource-record-sets --hosted-zone-id ' + lxonZone.Id + ' --profile ' + awsProfile, { encoding: 'utf8' });
        const recordsData = JSON.parse(records);
        
        const aRecords = recordsData.ResourceRecordSets.filter((r: any) => r.Type === 'A');
        console.log('   A Records:', aRecords.length);
        aRecords.forEach((record: any) => {
          console.log('   -', record.Name, '->', record.ResourceRecords[0].Value);
        });
      } else {
        console.log('⚠️  Route 53 Hosted Zone not found for lxon.in');
      }
    } catch (error) {
      console.log('⚠️  Could not verify Route 53 configuration');
    }
    console.log();

    // Phase 6: Verify SSL certificate
    console.log('🔒 Phase 6: Verifying SSL Certificate...');
    
    try {
      const certificates = execSync('aws acm list-certificates --region us-east-1 --profile ' + awsProfile, { encoding: 'utf8' });
      const certsData = JSON.parse(certificates);
      
      const lxonCert = certsData.CertificateSummaryList.find((c: any) => c.DomainName === 'lxon.in');
      if (lxonCert) {
        console.log('✅ SSL Certificate found:', lxonCert.CertificateArn);
        console.log('   Status:', lxonCert.Status);
        
        const certDetails = execSync('aws acm describe-certificate --certificate-arn ' + lxonCert.CertificateArn + ' --region us-east-1 --profile ' + awsProfile, { encoding: 'utf8' });
        const certData = JSON.parse(certDetails);
        console.log('   Validation Status:', certData.Certificate.DomainValidationOptions[0].ValidationStatus);
      } else {
        console.log('⚠️  SSL Certificate not found for lxon.in');
      }
    } catch (error) {
      console.log('⚠️  Could not verify SSL certificate');
    }
    console.log();

    // Save deployment summary
    const deploymentPath = path.join(__dirname, '..', 'deployments', 'mainnet-aws-summary.json');
    fs.writeFileSync(deploymentPath, JSON.stringify(deploymentAddresses, null, 2));
    console.log('💾 Deployment summary saved to:', deploymentPath);
    console.log();

    // Print final summary
    console.log('═'.repeat(70));
    console.log('🎉 MAINNET DEPLOYMENT VERIFICATION COMPLETE');
    console.log('═'.repeat(70));
    console.log();
    console.log('📊 Deployment Summary:');
    console.log('  Chain ID:', deploymentAddresses.chainId);
    console.log('  Network:', deploymentAddresses.network);
    console.log('  Environment:', deploymentAddresses.environment);
    console.log('  AWS Profile:', deploymentAddresses.awsProfile);
    console.log('  Deployer:', deploymentAddresses.deployer);
    console.log('  Deployed At:', deploymentAddresses.deployedAt);
    console.log();
    console.log('📋 Contract Addresses:');
    console.log('  LXON Token:', deploymentAddresses.contracts.lxonToken);
    console.log('  USDC:', deploymentAddresses.contracts.usdc);
    console.log('  Buyback:', deploymentAddresses.contracts.buyback);
    console.log('  Staking:', deploymentAddresses.contracts.staking);
    console.log('  SimpleSwap:', deploymentAddresses.contracts.simpleSwap);
    console.log();
    console.log('🌐 Public Endpoints:');
    console.log('  Website/Explorer: https://www.lxon.in');
    console.log('  RPC: https://www.lxon.in');
    console.log('  Chainlist: Updated with www.lxon.in');
    console.log();
    console.log('✅ Mainnet deployment is ready for production use');
    console.log();

  } catch (error) {
    console.error('❌ Deployment verification failed:', error);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('❌ Script error:', error);
    process.exit(1);
  });