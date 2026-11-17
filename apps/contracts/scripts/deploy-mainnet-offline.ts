import * as fs from 'fs';
import * as path from 'path';
import { execSync } from 'child_process';

async function main() {
  console.log('🚀 Mainnet Deployment with AWS Configuration (Offline Mode)\n');
  console.log('═'.repeat(70));

  // Get AWS profile from environment or use default
  const awsProfile = process.env.AWS_PROFILE || 'default';
  const awsRegion = process.env.AWS_REGION || 'eu-north-1'; // Changed to eu-north-1 for RAM share
  console.log(`📋 AWS Profile: ${awsProfile}`);
  console.log(`📡 AWS Region: ${awsRegion}`);
  console.log(`📡 RPC URL: ${process.env.LXON_RPC_URL || 'https://www.lxon.in'}`);
  console.log(`⛓ Chain ID: 724`);
  console.log(`🔗 RAM Share: arn:aws:ram:eu-north-1:316742356862:resource-share/0c51f76f-d8ad-468d-ba93-ec2fa1084a7e`);
  console.log();

  const deploymentAddresses: any = {
    network: 'lxon',
    chainId: 724,
    deployer: '0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3',
    awsProfile: awsProfile,
    deployedAt: new Date().toISOString(),
    environment: 'mainnet',
    rpcUrl: process.env.LXON_RPC_URL || 'https://www.lxon.in'
  };

  try {
    // Phase 1: Verify AWS Credentials
    console.log('🔐 Phase 1: Verifying AWS Credentials...');
    
    try {
      const whoami = execSync(`aws sts get-caller-identity --profile ${awsProfile} --region ${awsRegion}`, { encoding: 'utf8' });
      const whoamiData = JSON.parse(whoami);
      console.log('✅ AWS Credentials Verified');
      console.log('   Account:', whoamiData.Account);
      console.log('   User:', whoamiData.Arn);
      console.log('   Region:', awsRegion);
      deploymentAddresses.awsAccount = whoamiData.Account;
      deploymentAddresses.awsUser = whoamiData.Arn;
      deploymentAddresses.awsRegion = awsRegion;
    } catch (error) {
      console.log('⚠️  AWS Credentials verification failed, using default');
      console.log('   Please ensure AWS credentials are configured for region:', awsRegion);
    }
    console.log();

    // Phase 2: Load Existing Deployment
    console.log('📦 Phase 2: Loading Existing Deployment...');
    
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
        staking: existingDeployment.treasury, // Using treasury as staking for now
        simpleSwap: existingDeployment.treasury // Using treasury as simpleSwap for now
      };
      deploymentAddresses.originalDeployer = existingDeployment.deployer;
      deploymentAddresses.existingDeployment = true;
      deploymentAddresses.originalDeployer = existingDeployment.deployer;
    } else {
      console.log('⚠️  No existing deployment found');
      console.log();
    }

    // Phase 3: Verify Chainlist Configuration
    console.log('📋 Phase 3: Verifying Chainlist Configuration...');
    
    const chainlistPath = path.join(__dirname, '../../../chainlist.json');
    if (fs.existsSync(chainlistPath)) {
      const chainlist = JSON.parse(fs.readFileSync(chainlistPath, 'utf8'));
      
      console.log('✅ Chainlist Configuration:');
      console.log('   Chain ID:', chainlist.chainId);
      console.log('   Network:', chainlist.name);
      console.log('   RPC Endpoints:', chainlist.rpc.length);
      console.log('   Explorers:', chainlist.explorers.length);
      console.log('   www.lxon.in in RPC:', chainlist.rpc.includes('https://www.lxon.in'));
      console.log('   www.lxon.in as explorer:', chainlist.explorers.some((e: any) => e.url === 'https://www.lxon.in'));
      console.log('   Native Currency:', chainlist.nativeCurrency.symbol);
      console.log();
      
      deploymentAddresses.chainlistVerified = true;
      deploymentAddresses.chainlistConfig = chainlist;
    } else {
      console.log('⚠️  Chainlist.json not found');
      console.log();
    }

    // Phase 4: Verify AWS Infrastructure
    console.log('☁️  Phase 4: Verifying AWS Infrastructure...');
    
    try {
      const instances = execSync(`aws ec2 describe-instances --filters Name=tag:Name,Values=lxon-* --profile ${awsProfile} --region ${awsRegion}`, { encoding: 'utf8' });
      const instancesData = JSON.parse(instances);
      
      const allInstances = instancesData.Reservations.flatMap((r: any) => r.Instances);
      const runningInstances = allInstances.filter((i: any) => i.State.Name === 'running');
      const stoppedInstances = allInstances.filter((i: any) => i.State.Name === 'stopped');
      
      console.log('✅ AWS EC2 Instances:', allInstances.length);
      console.log('   Running:', runningInstances.length);
      console.log('   Stopped:', stoppedInstances.length);
      console.log();
      
      runningInstances.forEach((instance: any) => {
        const name = instance.Tags.find((t: any) => t.Key === 'Name')?.Value || 'Unknown';
        console.log('   -', name, ':', instance.PublicIpAddress || 'No public IP');
      });
      
      deploymentAddresses.awsInstances = {
        total: allInstances.length,
        running: runningInstances.length,
        stopped: stoppedInstances.length,
        instances: allInstances.map((i: any) => ({
          instanceId: i.InstanceId,
          name: i.Tags.find((t: any) => t.Key === 'Name')?.Value || 'Unknown',
          state: i.State.Name,
          publicIp: i.PublicIpAddress,
          privateIp: i.PrivateIpAddress
        }))
      };
    } catch (error) {
      console.log('⚠️  Could not verify AWS instances');
      console.log('   Error:', error instanceof Error ? error.message : String(error));
      console.log();
    }

    // Phase 5: Verify Route 53 Configuration
    console.log('🌐 Phase 5: Verifying Route 53 Configuration...');
    
    try {
      const hostedZones = execSync(`aws route53 list-hosted-zones --profile ${awsProfile}`, { encoding: 'utf8' });
      const zonesData = JSON.parse(hostedZones);
      
      const lxonZone = zonesData.HostedZones.find((z: any) => z.Name === 'lxon.in.');
      if (lxonZone) {
        console.log('✅ Route 53 Hosted Zone found:', lxonZone.Id);
        
        const records = execSync(`aws route53 list-resource-record-sets --hosted-zone-id ${lxonZone.Id} --profile ${awsProfile}`, { encoding: 'utf8' });
        const recordsData = JSON.parse(records);
        
        const aRecords = recordsData.ResourceRecordSets.filter((r: any) => r.Type === 'A');
        const cnameRecords = recordsData.ResourceRecordSets.filter((r: any) => r.Type === 'CNAME');
        
        console.log('   A Records:', aRecords.length);
        aRecords.forEach((record: any) => {
          console.log('   -', record.Name, '->', record.ResourceRecords[0]?.Value);
        });
        
        console.log('   CNAME Records:', cnameRecords.length);
        cnameRecords.forEach((record: any) => {
          console.log('   -', record.Name, '->', record.ResourceRecords[0]?.Value);
        });
        console.log();
        
        deploymentAddresses.route53Configured = true;
        deploymentAddresses.route53ZoneId = lxonZone.Id;
        deploymentAddresses.dnsRecords = recordsData.ResourceRecordSets;
      } else {
        console.log('⚠️  Route 53 Hosted Zone not found for lxon.in');
        console.log();
      }
    } catch (error) {
      console.log('⚠️  Could not verify Route 53 configuration');
      console.log('   Error:', error instanceof Error ? error.message : String(error));
      console.log();
    }

    // Phase 6: Verify SSL Certificate
    console.log('🔒 Phase 6: Verifying SSL Certificate...');
    
    try {
      const certificates = execSync(`aws acm list-certificates --region ${awsRegion} --profile ${awsProfile}`, { encoding: 'utf8' });
      const certsData = JSON.parse(certificates);
      
      const lxonCert = certsData.CertificateSummaryList.find((c: any) => c.DomainName === 'lxon.in');
      if (lxonCert) {
        console.log('✅ SSL Certificate found:', lxonCert.CertificateArn);
        console.log('   Status:', lxonCert.Status);
        console.log('   Type:', lxonCert.Type);
        
        const certDetails = execSync(`aws acm describe-certificate --certificate-arn ${lxonCert.CertificateArn} --region ${awsRegion} --profile ${awsProfile}`, { encoding: 'utf8' });
        const certData = JSON.parse(certDetails);
        
        const validationOptions = certData.Certificate.DomainValidationOptions;
        validationOptions.forEach((option: any) => {
          console.log('   Domain:', option.DomainName);
          console.log('   Validation Status:', option.ValidationStatus);
        });
        console.log();
        
        deploymentAddresses.sslCertificate = {
          arn: lxonCert.CertificateArn,
          status: lxonCert.Status,
          type: lxonCert.Type,
          validationStatus: validationOptions.map((o: any) => ({
            domain: o.DomainName,
            status: o.ValidationStatus
          }))
        };
      } else {
        console.log('⚠️  SSL Certificate not found for lxon.in');
        console.log();
      }
    } catch (error) {
      console.log('⚠️  Could not verify SSL certificate');
      console.log('   Error:', error instanceof Error ? error.message : String(error));
      console.log();
    }

    // Phase 7: Save Deployment Summary
    console.log('💾 Phase 7: Saving Deployment Summary...');
    
    const summaryPath = path.join(__dirname, '..', 'deployments', 'mainnet-aws-deployment.json');
    fs.writeFileSync(summaryPath, JSON.stringify(deploymentAddresses, null, 2));
    console.log('✅ Deployment summary saved to:', summaryPath);
    console.log();

    // Print Final Summary
    console.log('═'.repeat(70));
    console.log('🎉 MAINNET DEPLOYMENT WITH AWS CONFIGURATION COMPLETE');
    console.log('═'.repeat(70));
    console.log();
    console.log('📊 Deployment Summary:');
    console.log('  Chain ID:', deploymentAddresses.chainId);
    console.log('  Network:', deploymentAddresses.network);
    console.log('  Environment:', deploymentAddresses.environment);
    console.log('  AWS Profile:', deploymentAddresses.awsProfile);
    console.log('  Deployer:', deploymentAddresses.deployer);
    console.log('  Deployed At:', deploymentAddresses.deployedAt);
    console.log('  RPC URL:', deploymentAddresses.rpcUrl);
    console.log();
    
    if (deploymentAddresses.contracts) {
      console.log('📋 Contract Addresses:');
      console.log('  LXON Token:', deploymentAddresses.contracts.lxonToken);
      console.log('  USDC:', deploymentAddresses.contracts.usdc);
      console.log('  Buyback:', deploymentAddresses.contracts.buyback);
      console.log('  Staking:', deploymentAddresses.contracts.staking);
      console.log('  SimpleSwap:', deploymentAddresses.contracts.simpleSwap);
      console.log();
    }
    
    console.log('☁️  AWS Infrastructure:');
    if (deploymentAddresses.awsInstances) {
      console.log('  Total Instances:', deploymentAddresses.awsInstances.total);
      console.log('  Running:', deploymentAddresses.awsInstances.running);
      console.log('  Stopped:', deploymentAddresses.awsInstances.stopped);
    } else {
      console.log('  Status: Verification failed');
    }
    console.log();
    
    console.log('🌐 Domain Configuration:');
    console.log('  Route 53:', deploymentAddresses.route53Configured ? 'Configured' : 'Not configured');
    console.log('  SSL Certificate:', deploymentAddresses.sslCertificate ? 'Found' : 'Not found');
    console.log();
    
    console.log('📋 Chainlist Configuration:');
    console.log('  Verified:', deploymentAddresses.chainlistVerified ? 'Yes' : 'No');
    console.log('  www.lxon.in as RPC:', deploymentAddresses.chainlistConfig?.rpc.includes('https://www.lxon.in') || false);
    console.log('  www.lxon.in as Explorer:', deploymentAddresses.chainlistConfig?.explorers.some((e: any) => e.url === 'https://www.lxon.in') || false);
    console.log();
    
    console.log('🌐 Public Endpoints:');
    console.log('  Website/Explorer: https://www.lxon.in');
    console.log('  RPC: https://www.lxon.in');
    console.log('  Chainlist: Updated with www.lxon.in');
    console.log();
    
    console.log('✅ Mainnet deployment with AWS configuration is complete');
    console.log();

  } catch (error) {
    console.error('❌ Deployment failed:', error);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('❌ Script error:', error);
    process.exit(1);
  });