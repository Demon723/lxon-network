import { Module } from '@nestjs/common';
import { SecondaryController } from './secondary.controller';

@Module({
  controllers: [SecondaryController],
})
export class SecondaryModule {}