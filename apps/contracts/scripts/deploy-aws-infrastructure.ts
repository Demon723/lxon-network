import * as fs from 'fs';
import * as path from 'path';
import { execSync } from 'child_process';

async function main() {
  console.log('🚀 AWS Blockchain Infrastructure Deployment - Chain ID 724\n');
  console.log('═'.repeat(70));

  const awsAccount = '316742356862';
  const awsRegion = 'eu-north-1';
  const chainId = 724;

  const infrastructureConfig: any = {
    awsAccount: awsAccount,
    awsRegion: awsRegion,
    chainId: chainId,
    network: 'lxon',
    deployedAt: new Date().toISOString(),
    instances: []
  };

  try {
    // Phase 1: Verify AWS credentials
    console.log('🔐 Phase 1: Verifying AWS Credentials...');
    
    try {
      const whoami = execSync(`aws sts get-caller-identity --region ${awsRegion}`, { encoding: 'utf8' });
      const whoamiData = JSON.parse(whoami);
      console.log('✅ AWS Credentials Verified');
      console.log('   Account:', whoamiData.Account);
      console.log('   User:', whoamiData.Arn);
      console.log('   Region:', awsRegion);
      
      if (whoamiData.Account !== awsAccount) {
        console.log('❌ Wrong AWS account detected');
        process.exit(1);
      }
    } catch (error) {
      console.log('❌ AWS credentials verification failed');
      process.exit(1);
    }
    console.log();

    // Phase 2: Create Security Group
    console.log('🔒 Phase 2: Creating Security Group...');
    
    const securityGroupName = 'lxon-blockchain-sg';
    const securityGroupDescription = 'Security group for LXON blockchain nodes';
    
    try {
      // Check if security group exists
      const existingSg = execSync(
        `aws ec2 describe-security-groups --group-names ${securityGroupName} --region ${awsRegion}`,
        { encoding: 'utf8' }
      );
      
      const sgData = JSON.parse(existingSg);
      console.log('✅ Security group already exists:', securityGroupName);
      infrastructureConfig.securityGroupId = sgData.SecurityGroups[0].GroupId;
    } catch (error) {
      // Create new security group
      console.log('   Creating new security group...');
      
      const createSg = execSync(
        `aws ec2 create-security-group --group-name ${securityGroupName} --description "${securityGroupDescription}" --region ${awsRegion}`,
        { encoding: 'utf8' }
      );
      
      const sgData = JSON.parse(createSg);
      console.log('✅ Security group created:', sgData.GroupId);
      
      infrastructureConfig.securityGroupId = sgData.GroupId;
      
      // Add security group rules
      console.log('   Adding security group rules...');
      
      // Allow SSH (port 22)
      execSync(
        `aws ec2 authorize-security-group-ingress --group-id ${sgData.GroupId} --protocol tcp --port 22 --cidr 0.0.0.0/0 --region ${awsRegion}`,
        { encoding: 'utf8' }
      );
      
      // Allow RPC ports (8545, 8546, 8547)
      execSync(
        `aws ec2 authorize-security-group-ingress --group-id ${sgData.GroupId} --protocol tcp --port 8545 --cidr 0.0.0.0/0 --region ${awsRegion}`,
        { encoding: 'utf8' }
      );
      execSync(
        `aws ec2 authorize-security-group-ingress --group-id ${sgData.GroupId} --protocol tcp --port 8546 --cidr 0.0.0.0/0 --region ${awsRegion}`,
        { encoding: 'utf8' }
      );
      execSync(
        `aws ec2 authorize-security-group-ingress --group-id ${sgData.GroupId} --protocol tcp --port 8547 --cidr 0.0.0.0/0 --region ${awsRegion}`,
        { encoding: 'utf8' }
      );
      
      // Allow P2P ports (30303, 30304)
      execSync(
        `aws ec2 authorize-security-group-ingress --group-id ${sgData.GroupId} --protocol tcp --port 30303 --cidr 0.0.0.0/0 --region ${awsRegion}`,
        { encoding: 'utf8' }
      );
      execSync(
        `aws ec2 authorize-security-group-ingress --group-id ${sgData.GroupId} --protocol udp --port 30303 --cidr 0.0.0.0/0 --region ${awsRegion}`,
        { encoding: 'utf8' }
      );
      
      console.log('✅ Security group rules configured');
    }
    console.log();

    // Phase 3: Get Key Pair
    console.log('🔑 Phase 3: Getting Key Pair...');
    
    const keyPairName = 'lxon-blockchain-key';
    
    try {
      const existingKey = execSync(
        `aws ec2 describe-key-pairs --key-names ${keyPairName} --region ${awsRegion}`,
        { encoding: 'utf8' }
      );
      
      console.log('✅ Key pair already exists:', keyPairName);
    } catch (error) {
      console.log('   Creating new key pair...');
      
      const createKey = execSync(
        `aws ec2 create-key-pair --key-name ${keyPairName} --region ${awsRegion}`,
        { encoding: 'utf8' }
      );
      
      const keyData = JSON.parse(createKey);
      console.log('✅ Key pair created:', keyPairName);
      
      // Save private key
      const keyPath = path.join(__dirname, '..', 'deployments', `${keyPairName}.pem`);
      fs.writeFileSync(keyPath, keyData.KeyMaterial);
      fs.chmodSync(keyPath, 0o600);
      
      console.log('✅ Private key saved to:', keyPath);
      infrastructureConfig.keyPairPath = keyPath;
    }
    console.log();

    // Phase 4: Create EC2 Instances
    console.log('🖥️  Phase 4: Creating EC2 Instances...');
    
    const instanceConfig = {
      imageId: 'ami-0339082da191e427e', // Ubuntu 22.04 in eu-north-1
      instanceType: 't3.micro', // Free tier eligible
      keyName: keyPairName,
      securityGroupName: securityGroupName,
      instances: [
        { name: 'lxon-validator-1', role: 'validator', port: 8546 },
        { name: 'lxon-validator-2', role: 'validator', port: 8547 },
        { name: 'lxon-rpc-node', role: 'rpc', port: 8545 }
      ]
    };

    console.log('   Instance Type:', instanceConfig.instanceType);
    console.log('   AMI:', instanceConfig.imageId);
    console.log('   Number of instances:', instanceConfig.instances.length);
    console.log();

    for (const instance of instanceConfig.instances) {
      console.log(`   Creating ${instance.name}...`);
      
      try {
        const runInstance = execSync(
          `aws ec2 run-instances --image-id ${instanceConfig.imageId} --instance-type ${instanceConfig.instanceType} --key-name ${keyPairName} --security-group-ids ${infrastructureConfig.securityGroupId} --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${instance.name}},{Key=Role,Value=${instance.role}},{Key=ChainId,Value=${chainId}}]" --region ${awsRegion}`,
          { encoding: 'utf8' }
        );
        
        const instanceData = JSON.parse(runInstance);
        const instanceId = instanceData.Instances[0].InstanceId;
        
        console.log(`   ✅ ${instance.name} created: ${instanceId}`);
        
        infrastructureConfig.instances.push({
          name: instance.name,
          role: instance.role,
          port: instance.port,
          instanceId: instanceId,
          status: 'created'
        });
        
        // Wait for instance to be running
        console.log(`   Waiting for ${instance.name} to be running...`);
        execSync(
          `aws ec2 wait instance-running --instance-ids ${instanceId} --region ${awsRegion}`,
          { encoding: 'utf8' }
        );
        
        // Get public IP
        const describeInstance = execSync(
          `aws ec2 describe-instances --instance-ids ${instanceId} --region ${awsRegion}`,
          { encoding: 'utf8' }
        );
        
        const describeData = JSON.parse(describeInstance);
        const publicIp = describeData.Reservations[0].Instances[0].PublicIpAddress;
        
        console.log(`   ✅ ${instance.name} is running at ${publicIp}`);
        
        infrastructureConfig.instances[infrastructureConfig.instances.length - 1].publicIp = publicIp;
        infrastructureConfig.instances[infrastructureConfig.instances.length - 1].status = 'running';
        
      } catch (error) {
        console.log(`   ❌ Failed to create ${instance.name}`);
        console.log(`      Error: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
    console.log();

    // Phase 5: Save Infrastructure Configuration
    console.log('💾 Phase 5: Saving Infrastructure Configuration...');
    
    const configPath = path.join(__dirname, '..', 'deployments', 'aws-infrastructure-config.json');
    fs.writeFileSync(configPath, JSON.stringify(infrastructureConfig, null, 2));
    console.log('✅ Infrastructure configuration saved to:', configPath);
    console.log();

    // Print Final Summary
    console.log('═'.repeat(70));
    console.log('🎉 AWS BLOCKCHAIN INFRASTRUCTURE DEPLOYMENT COMPLETE');
    console.log('═'.repeat(70));
    console.log();
    console.log('📊 Infrastructure Summary:');
    console.log('  AWS Account:', infrastructureConfig.awsAccount);
    console.log('  Region:', infrastructureConfig.awsRegion);
    console.log('  Chain ID:', infrastructureConfig.chainId);
    console.log('  Security Group:', infrastructureConfig.securityGroupId || 'Existing');
    console.log('  Key Pair:', infrastructureConfig.keyPairPath || 'Existing');
    console.log();
    
    console.log('🖥️  EC2 Instances:');
    infrastructureConfig.instances.forEach((instance: any) => {
      console.log(`  ${instance.name}:`);
      console.log('    Role:', instance.role);
      console.log('    Instance ID:', instance.instanceId);
      console.log('    Public IP:', instance.publicIp || 'Not assigned yet');
      console.log('    RPC Port:', instance.port);
      console.log('    Status:', instance.status);
    });
    console.log();
    
    console.log('🎯 Next Steps:');
    console.log('  1. Install blockchain node software on each instance');
    console.log('  2. Configure the blockchain network with chain ID 724');
    console.log('  3. Start the blockchain nodes');
    console.log('  4. Configure JSON-RPC endpoints');
    console.log('  5. Update domain DNS to point to RPC node');
    console.log('  6. Test RPC connectivity');
    console.log();
    
    console.log('✅ AWS infrastructure deployment complete');
    console.log('   Ready for blockchain node installation');
    console.log();

  } catch (error) {
    console.error('❌ Infrastructure deployment failed:', error);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('❌ Script error:', error);
    process.exit(1);
  });