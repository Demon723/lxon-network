/**
 * Secondary PQ signature admin routes for NestJS.
 *
 * Note: Secondary signature functionality is disabled until WASM/Rust bindings are built.
 */
import { Controller, Get, Post, Body, Param, Headers, HttpException, HttpStatus } from '@nestjs/common';
import { IsOptional, IsString, IsEnum, IsHexadecimal } from 'class-validator';

export enum SecondaryScheme {
  MAYO_1 = 'MAYO-1',
  MAYO_2 = 'MAYO-2',
  MAYO_3 = 'MAYO-3',
  MAYO_5 = 'MAYO-5',
  SQISIGN = 'SQIsign',
}

class AttestDto {
  @IsString()
  @IsHexadecimal()
  commitment: string;

  @IsEnum(SecondaryScheme)
  scheme: SecondaryScheme;
}

class VerifyDto {
  @IsString()
  publicKeyHex: string;

  @IsString()
  messageHex: string;

  @IsString()
  signatureHex: string;

  @IsEnum(SecondaryScheme)
  scheme: SecondaryScheme;
}

@Controller('secondary')
export class SecondaryController {
  private readonly rpcUrl: string;
  private readonly registryAddress: string;
  private readonly enabled: boolean;

  constructor() {
    this.rpcUrl = process.env.RPC_URL || 'http://localhost:8545';
    this.registryAddress = process.env.SECONDARY_REGISTRY || '';
    this.enabled = !!this.registryAddress && process.env.LXON_FLAG_SECONDARY_BACKEND_ROUTES === 'true';
  }

  @Get('status')
  getStatus() {
    return {
      enabled: this.enabled,
      registry: this.registryAddress || null,
      supportedSchemes: ['MAYO-1', 'MAYO-2', 'MAYO-3', 'MAYO-5', 'SQIsign'],
      activeSchemes: this.enabled ? ['MAYO-1', 'MAYO-2', 'MAYO-3', 'MAYO-5'] : [],
      note: 'Secondary signature support is disabled until WASM/Rust bindings are built',
    };
  }

  @Get('verify/:commitment/:scheme')
  async verifyCommitment(@Param('commitment') commitment: string, @Param('scheme') scheme: string) {
    if (!this.enabled) {
      throw new HttpException('Secondary signatures disabled', HttpStatus.SERVICE_UNAVAILABLE);
    }

    if (!/^0x[0-9a-fA-F]{64}$/.test(commitment)) {
      throw new HttpException('Invalid commitment format', HttpStatus.BAD_REQUEST);
    }

    try {
      const body = {
        jsonrpc: '2.0',
        id: 1,
        method: 'eth_call',
        params: [{
          to: this.registryAddress,
          data: this.encodeIsAttested(commitment, scheme),
        }, 'latest'],
      };

      const response = await fetch(this.rpcUrl, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(body),
      });

      const result = await response.json() as { result?: string };
      const attested = result.result === '0x' + '0'.repeat(63) + '1';

      return { commitment, scheme, attested };
    } catch (error) {
      throw new HttpException(
        `Verification failed: ${error.message}`,
        HttpStatus.BAD_GATEWAY
      );
    }
  }

  @Post('commitment')
  computeCommitment(@Body() body: VerifyDto) {
    const crypto = require('crypto');
    const h = crypto.createHash('sha256');
    h.update(Buffer.from(body.messageHex, 'hex'));
    h.update(Buffer.from(body.publicKeyHex, 'hex'));
    h.update(Buffer.from(body.signatureHex, 'hex'));
    return { commitment: '0x' + h.digest('hex') };
  }

  @Post('attest')
  async attest(@Body() body: AttestDto, @Headers('x-admin-token') adminToken: string) {
    if (!this.enabled) {
      throw new HttpException('Secondary signatures disabled', HttpStatus.SERVICE_UNAVAILABLE);
    }

    // Auth check
    if (adminToken !== process.env.ADMIN_TOKEN) {
      throw new HttpException('Forbidden', HttpStatus.FORBIDDEN);
    }

    // For now, return a mock response since actual attestation requires contract interaction
    const crypto = require('crypto');
    return {
      submitted: true,
      commitment: body.commitment,
      scheme: body.scheme,
      txHash: '0x' + crypto.randomBytes(32).toString('hex'),
      note: 'Actual attestation requires contract deployment and WASM/Rust bindings',
    };
  }

  private encodeIsAttested(commitment: string, scheme: string): string {
    const sel = '12345678'; // placeholder selector - update after contract deployment
    const c = commitment.replace(/^0x/, '');
    const schemeId = ({ 'MAYO-1': 1, 'MAYO-2': 2, 'MAYO-3': 3, 'MAYO-5': 4, 'SQIsign': 5 } as Record<string, number>)[scheme] || 0;
    return '0x' + sel + c + schemeId.toString(16).padStart(64, '0');
  }
}